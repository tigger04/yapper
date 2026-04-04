// ABOUTME: CLI command for converting text files to audio (M4A/MP3/M4B).
// ABOUTME: Synthesises via YapperKit, encodes via ffmpeg. Supports audiobook mode.

import ArgumentParser
import AVFoundation
import Foundation
import YapperKit

struct ConvertCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert text files to audio or audiobooks."
    )

    @Argument(help: "Input file(s) to convert.")
    var inputs: [String]

    @Option(name: .shortAndLong, help: "Output file path.")
    var output: String?

    @Option(name: .long, help: "Output format: m4a (default), m4b, mp3. Auto-selects m4b for multi-chapter input.")
    var format: String?

    @Option(name: .long, help: "Voice name for all chapters (e.g. af_heart).")
    var voice: String?

    @Option(name: .long, help: "Random voice filter (e.g. bf for British female). Default: random per chapter.")
    var randomVoice: String?

    @Option(name: .long, help: "Speech speed multiplier (default: 1.0).")
    var speed: Float = 1.0

    @Option(name: .long, help: "Author metadata for the output file.")
    var author: String?

    @Option(name: .long, help: "Title metadata for the output file.")
    var title: String?

    @Flag(name: .long, help: "Show what would be done without converting.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Force interactive prompts even when stdin is not a TTY.")
    var interactive: Bool = false

    func run() throws {
        guard !inputs.isEmpty else {
            throw ValidationError("No input files specified.")
        }

        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )

        // Determine if this is audiobook mode (multi-chapter input)
        let chapters = try gatherChapters()

        if chapters.count > 1 {
            try runAudiobookMode(engine: engine, chapters: chapters)
        } else {
            try runSingleFileMode(engine: engine)
        }
    }

    // MARK: - Chapter gathering

    private func gatherChapters() throws -> [Chapter] {
        var allChapters: [Chapter] = []

        for input in inputs {
            guard FileManager.default.fileExists(atPath: input) else {
                throw ValidationError("Input file not found: \(input)")
            }

            let ext = URL(fileURLWithPath: input).pathExtension.lowercased()
            if ["epub", "mobi", "pdf", "docx", "odt", "md", "html", "txt"].contains(ext) {
                let chapters = try DocumentConverter.convert(input)
                allChapters.append(contentsOf: chapters)
            } else {
                // Try as plain text
                let data = try Data(contentsOf: URL(fileURLWithPath: input))
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ValidationError("File is not valid UTF-8: \(input)")
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw ValidationError("File is empty: \(input)")
                }
                let name = URL(fileURLWithPath: input).deletingPathExtension().lastPathComponent
                allChapters.append(Chapter(title: name, text: trimmed))
            }
        }

        return allChapters
    }

    // MARK: - Audiobook mode

    private func runAudiobookMode(engine: YapperEngine, chapters: [Chapter]) throws {
        let outputFormat = resolveFormat(multiChapter: true)
        let outputPath = resolveAudiobookOutputPath(format: outputFormat)

        // Resolve metadata
        let (resolvedAuthor, resolvedTitle) = resolveMetadata(chapters: chapters)

        // Assign voices
        let voices = assignVoices(engine: engine, chapterCount: chapters.count)

        if dryRun {
            print("Audiobook conversion plan:")
            print("  Output: \(outputPath)")
            print("  Format: \(outputFormat)")
            print("  Chapters: \(chapters.count)")
            if let resolvedAuthor { print("  Author: \(resolvedAuthor)") }
            if let resolvedTitle { print("  Title: \(resolvedTitle)") }
            for (i, chapter) in chapters.enumerated() {
                print("  [\(i + 1)/\(chapters.count)] \(chapter.title) (\(voices[i].name))")
            }
            return
        }

        // Back up existing output
        if FileManager.default.fileExists(atPath: outputPath) {
            let backupPath = nextBackupPath(for: outputPath)
            try FileManager.default.moveItem(atPath: outputPath, toPath: backupPath)
            fputs("Backed up existing \(outputPath) to \(backupPath)\n", stderr)
        }

        fputs("Converting: \(inputs.joined(separator: ", ")) (\(chapters.count) chapters)\n", stderr)

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_audiobook_\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var chapterInfo: [(title: String, aacPath: String, duration: Double)] = []

        for (i, chapter) in chapters.enumerated() {
            let voice = voices[i]
            fputs("  [\(i + 1)/\(chapters.count)] \(chapter.title) (\(voice.name)) ... ", stderr)

            let result = try engine.synthesize(text: chapter.text, voice: voice, speed: speed)
            let duration = Double(result.samples.count) / Double(result.sampleRate)

            // Write WAV
            let wavPath = tmpDir.appendingPathComponent("ch\(i + 1).wav")
            try writeWav(samples: result.samples, sampleRate: result.sampleRate, to: wavPath)

            // Encode AAC
            let aacPath = tmpDir.appendingPathComponent("ch\(i + 1).aac").path
            try AudiobookAssembler.encodeAAC(wavPath: wavPath.path, output: aacPath)
            try? FileManager.default.removeItem(at: wavPath)

            chapterInfo.append((title: chapter.title, aacPath: aacPath, duration: duration))
            fputs("\(String(format: "%.1f", duration))s\n", stderr)
        }

        if outputFormat == "m4b" {
            // Assemble M4B with chapter markers
            try AudiobookAssembler.assembleM4B(
                chapters: chapterInfo,
                output: outputPath,
                title: resolvedTitle,
                author: resolvedAuthor,
                coverArtPath: nil // TODO: extract from epub
            )
        } else {
            // For MP3/M4A: concatenate and encode
            try assembleSingleFile(chapterInfo: chapterInfo, output: outputPath,
                                   format: outputFormat, author: resolvedAuthor, title: resolvedTitle)
        }

        let totalDuration = chapterInfo.reduce(0.0) { $0 + $1.duration }
        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        fputs("Created \(outputPath) (\(minutes):\(String(format: "%02d", seconds)))\n", stderr)
    }

    // MARK: - Single file mode

    private func runSingleFileMode(engine: YapperEngine) throws {
        let fmt = resolveFormat(multiChapter: false)

        guard ["m4a", "mp3", "m4b"].contains(fmt) else {
            throw ValidationError("Unsupported format '\(fmt)'. Use m4a, mp3, or m4b.")
        }

        let selectedVoice = try resolveVoice(engine: engine, voiceName: voice)

        var failures = 0
        for input in inputs {
            do {
                try convertSingleFile(input: input, engine: engine, voice: selectedVoice, format: fmt)
            } catch {
                fputs("Error converting \(input): \(error)\n", stderr)
                failures += 1
            }
        }

        if failures > 0 {
            fputs("\(failures) of \(inputs.count) files failed.\n", stderr)
            throw ExitCode(1)
        }
    }

    private func convertSingleFile(input: String, engine: YapperEngine, voice: Voice, format: String) throws {
        guard FileManager.default.fileExists(atPath: input) else {
            throw ValidationError("Input file not found: \(input)")
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        guard let text = String(data: data, encoding: .utf8) else {
            throw ValidationError("File is not valid UTF-8: \(input). Convert to UTF-8 first.")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError("File is empty or whitespace-only: \(input)")
        }

        let outputPath = resolveOutputPath(for: input, format: format)

        if dryRun {
            print("Would convert: \(input)")
            print("  Output: \(outputPath)")
            print("  Format: \(format)")
            print("  Voice: \(voice.name)")
            print("  Speed: \(speed)")
            if let author { print("  Author: \(author)") }
            if let title { print("  Title: \(title)") }
            return
        }

        if FileManager.default.fileExists(atPath: outputPath) {
            let backupPath = nextBackupPath(for: outputPath)
            try FileManager.default.moveItem(atPath: outputPath, toPath: backupPath)
            fputs("Backed up existing \(outputPath) to \(backupPath)\n", stderr)
        }

        fputs("Synthesising \(input)...\n", stderr)
        let result = try engine.synthesize(text: trimmed, voice: voice, speed: speed)

        let tmpWav = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_convert_\(ProcessInfo.processInfo.processIdentifier).wav")
        try writeWav(samples: result.samples, sampleRate: result.sampleRate, to: tmpWav)
        defer { try? FileManager.default.removeItem(at: tmpWav) }

        try encodeWithFFmpeg(input: tmpWav.path, output: outputPath, format: format)

        let duration = Double(result.samples.count) / Double(result.sampleRate)
        fputs("Created \(outputPath) (\(String(format: "%.1f", duration))s)\n", stderr)
    }

    // MARK: - Voice assignment

    private func assignVoices(engine: YapperEngine, chapterCount: Int) -> [Voice] {
        if let voiceName = voice {
            let v = engine.voiceRegistry.voices.first { $0.name == voiceName }
                ?? engine.voiceRegistry.voices[0]
            return Array(repeating: v, count: chapterCount)
        }

        // Random per chapter, seeded by first input filename
        let seed = inputs.first.map { $0.hashValue } ?? 0
        let filter: VoiceFilter?
        if let randomVoice {
            let accent = Accent(rawValue: String(randomVoice.prefix(1)))
            let gender = randomVoice.count > 1 ? Gender(rawValue: String(randomVoice.dropFirst().prefix(1))) : nil
            filter = VoiceFilter(accent: accent, gender: gender)
        } else {
            filter = nil
        }

        return (0..<chapterCount).map { i in
            engine.voiceRegistry.random(filter: filter, seed: UInt64(abs(seed &+ i))) ?? engine.voiceRegistry.voices[0]
        }
    }

    // MARK: - Metadata resolution

    private func resolveMetadata(chapters: [Chapter]) -> (author: String?, title: String?) {
        var resolvedAuthor = author
        var resolvedTitle = title

        // Try extracting from epub
        if resolvedAuthor == nil || resolvedTitle == nil {
            for input in inputs {
                let ext = URL(fileURLWithPath: input).pathExtension.lowercased()
                if ext == "epub", let result = try? EpubParser.parse(input) {
                    if resolvedTitle == nil { resolvedTitle = result.metadata.title }
                    if resolvedAuthor == nil { resolvedAuthor = result.metadata.author }
                    break
                }
            }
        }

        // Interactive prompts if TTY
        let isTTY = isatty(FileHandle.standardInput.fileDescriptor) != 0
        if isTTY || interactive {
            if let defaultTitle = resolvedTitle {
                fputs("Enter title [\(defaultTitle)]: ", stderr)
            } else {
                fputs("Enter title (optional): ", stderr)
            }
            if let input = readLine(), !input.isEmpty {
                resolvedTitle = input
            }

            if let defaultAuthor = resolvedAuthor {
                fputs("Enter author [\(defaultAuthor)]: ", stderr)
            } else {
                fputs("Enter author (optional): ", stderr)
            }
            if let input = readLine(), !input.isEmpty {
                resolvedAuthor = input
            }
        }

        return (resolvedAuthor, resolvedTitle)
    }

    // MARK: - Format resolution

    private func resolveFormat(multiChapter: Bool) -> String {
        if let format { return format.lowercased() }
        return multiChapter ? "m4b" : "m4a"
    }

    // MARK: - Helpers

    private func resolveOutputPath(for input: String, format: String) -> String {
        if let output { return output }
        let url = URL(fileURLWithPath: input)
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent().path
        return "\(dir)/\(base).\(format)"
    }

    private func resolveAudiobookOutputPath(format: String) -> String {
        if let output { return output }
        let firstInput = URL(fileURLWithPath: inputs[0])
        let base = firstInput.deletingPathExtension().lastPathComponent
        let dir = firstInput.deletingLastPathComponent().path
        return "\(dir)/\(base).\(format)"
    }

    private func nextBackupPath(for path: String) -> String {
        let bak = "\(path).bak"
        if !FileManager.default.fileExists(atPath: bak) { return bak }
        var n = 1
        while FileManager.default.fileExists(atPath: "\(path).\(n).bak") { n += 1 }
        return "\(path).\(n).bak"
    }

    private func resolveVoice(engine: YapperEngine, voiceName: String?) throws -> Voice {
        if let voiceName {
            guard let v = engine.voiceRegistry.voices.first(where: { $0.name == voiceName }) else {
                let available = engine.voiceRegistry.voices.prefix(5).map(\.name).joined(separator: ", ")
                throw ValidationError("Voice '\(voiceName)' not found. Available: \(available)...")
            }
            return v
        }
        return engine.voiceRegistry.voices.first { $0.name == "af_heart" }
            ?? engine.voiceRegistry.voices[0]
    }

    private func encodeWithFFmpeg(input: String, output: String, format: String) throws {
        let ffmpegPath = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .first { FileManager.default.fileExists(atPath: $0) }
        guard let ffmpeg = ffmpegPath else {
            throw ValidationError("ffmpeg not found. Install via: brew install ffmpeg")
        }

        var args = ["-y", "-i", input]
        if format == "mp3" {
            args += ["-c:a", "libmp3lame", "-b:a", "128k"]
        } else {
            args += ["-c:a", "aac", "-b:a", "64k"]
        }

        if let author {
            args += ["-metadata", "artist=\(author)", "-metadata", "album_artist=\(author)"]
        }
        if let title {
            args += ["-metadata", "album=\(title)"]
        }

        args.append(output)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ValidationError("ffmpeg exited with status \(process.terminationStatus)")
        }
    }

    private func assembleSingleFile(
        chapterInfo: [(title: String, aacPath: String, duration: Double)],
        output: String,
        format: String,
        author: String?,
        title: String?
    ) throws {
        // Simple concatenation for MP3/M4A (no chapter markers)
        let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .first { FileManager.default.fileExists(atPath: $0) }!

        let tmpConcat = FileManager.default.temporaryDirectory
            .appendingPathComponent("concat_\(UUID().uuidString).txt")
        let content = chapterInfo.map { "file '\($0.aacPath)'" }.joined(separator: "\n")
        try content.write(to: tmpConcat, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpConcat) }

        var args = ["-y", "-f", "concat", "-safe", "0", "-i", tmpConcat.path]

        if format == "mp3" {
            args += ["-c:a", "libmp3lame", "-b:a", "128k"]
        } else {
            args += ["-c", "copy"]
        }

        if let author { args += ["-metadata", "artist=\(author)"] }
        if let title { args += ["-metadata", "album=\(title)"] }
        args.append(output)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    private func writeWav(samples: [Float], sampleRate: Int, to url: URL) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ValidationError("Failed to create audio buffer")
        }
        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
