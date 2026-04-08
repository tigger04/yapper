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

    @Flag(name: .long, help: "Skip interactive prompts regardless of TTY state.")
    var nonInteractive: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress progress output.")
    var quiet: Bool = false

    func run() throws {
        guard !inputs.isEmpty else {
            throw ValidationError("No input files specified.")
        }

        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )

        // The OUTPUT FORMAT determines the file topology:
        //
        // M4B → package everything into one audiobook file with chapter markers.
        //       Works for single multi-chapter inputs (epub, PDF) and for
        //       multiple independent inputs (treated as chapters of one book).
        //
        // M4A/MP3 → one output file per chapter or per input file.
        //           An epub with 12 chapters produces 12 M4As. Three text files
        //           produce three M4As. Metadata is applied to each file.
        // The OUTPUT FORMAT determines the file topology:
        //
        // M4B → always package everything into one audiobook file.
        //       A single epub or multiple txt files become chapters.
        //
        // M4A/MP3 with a single multi-chapter input (epub, PDF) →
        //       one file per chapter, named by chapter title.
        //
        // M4A/MP3 with multiple independent input files →
        //       one file per input, named after the input file.
        //       Missing/invalid files are skipped with a warning (not aborted).
        if inputs.count == 1 {
            let chapters = try gatherChapters()
            let fmt = resolveFormat(multiChapter: chapters.count > 1)
            if fmt == "m4b" {
                try runAudiobookMode(engine: engine, chapters: chapters)
            } else if chapters.count > 1 {
                try runChapterPerFileMode(engine: engine, chapters: chapters, format: fmt)
            } else {
                try runSingleFileMode(engine: engine)
            }
        } else if let format, format.lowercased() == "m4b" {
            // Multiple inputs + explicit M4B → package as audiobook
            let chapters = try gatherChapters()
            try runAudiobookMode(engine: engine, chapters: chapters)
        } else {
            // Multiple inputs + M4A/MP3 → one file per input, skip failures
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

    // MARK: - Chapter-per-file mode (M4A/MP3 from multi-chapter input)

    /// Produces one output file per chapter. Used when a multi-chapter input
    /// (epub, PDF with headings, or multiple input files) is converted to M4A
    /// or MP3 — formats that don't support chapter markers.
    private func runChapterPerFileMode(engine: YapperEngine, chapters: [Chapter], format: String) throws {
        let voices = assignVoices(engine: engine, chapterCount: chapters.count)
        let (resolvedAuthor, resolvedTitle) = resolveMetadata(chapters: chapters)

        // Derive output directory from -o flag or first input's directory
        let outputDir: String
        if let output {
            // If -o points to a directory, use it; if it's a file path, use its directory
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: output, isDirectory: &isDir), isDir.boolValue {
                outputDir = output
            } else {
                outputDir = URL(fileURLWithPath: output).deletingLastPathComponent().path
            }
        } else {
            outputDir = URL(fileURLWithPath: inputs[0]).deletingLastPathComponent().path
        }

        if dryRun {
            print("Chapter-per-file conversion plan:")
            print("  Output directory: \(outputDir)")
            print("  Format: \(format)")
            print("  Chapters: \(chapters.count)")
            if let resolvedAuthor { print("  Author: \(resolvedAuthor)") }
            if let resolvedTitle { print("  Title: \(resolvedTitle)") }
            for (i, chapter) in chapters.enumerated() {
                let filename = chapterFilename(index: i, title: chapter.title, format: format)
                print("  [\(i + 1)/\(chapters.count)] \(filename) (\(voices[i].name))")
            }
            return
        }

        fputs("Converting: \(chapters.count) chapters to \(format)\n", stderr)

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_chapters_\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        for (i, chapter) in chapters.enumerated() {
            let voice = voices[i]
            let filename = chapterFilename(index: i, title: chapter.title, format: format)
            let outputPath = "\(outputDir)/\(filename)"

            fputs("  [\(i + 1)/\(chapters.count)] \(filename) (\(voice.name)) ... ", stderr)

            let result = try engine.synthesize(text: chapter.text, voice: voice, speed: speed)
            let duration = Double(result.samples.count) / Double(result.sampleRate)

            // Write WAV
            let wavPath = tmpDir.appendingPathComponent("ch\(i + 1).wav")
            try writeWav(samples: result.samples, sampleRate: result.sampleRate, to: wavPath)

            // Encode to target format with metadata
            if FileManager.default.fileExists(atPath: outputPath) {
                let backupPath = nextBackupPath(for: outputPath)
                try FileManager.default.moveItem(atPath: outputPath, toPath: backupPath)
            }
            try encodeWithFFmpeg(
                input: wavPath.path,
                output: outputPath,
                format: format,
                author: resolvedAuthor,
                title: resolvedTitle,
                trackNumber: i + 1,
                trackTotal: chapters.count,
                trackTitle: chapter.title
            )
            try? FileManager.default.removeItem(at: wavPath)

            fputs("\(String(format: "%.1f", duration))s\n", stderr)
        }

        fputs("Created \(chapters.count) files in \(outputDir)\n", stderr)
    }

    /// Generate a filename for an individual chapter output file.
    private func chapterFilename(index: Int, title: String, format: String) -> String {
        let paddedIndex = String(format: "%02d", index + 1)
        // Sanitise the title for use as a filename
        let safe = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if safe.isEmpty {
            return "chapter_\(paddedIndex).\(format)"
        }
        return "\(paddedIndex)_\(safe).\(format)"
    }

    // MARK: - Single file mode

    private func runSingleFileMode(engine: YapperEngine) throws {
        let fmt = resolveFormat(multiChapter: false)

        guard ["m4a", "mp3", "m4b"].contains(fmt) else {
            throw ValidationError("Unsupported format '\(fmt)'. Use m4a, mp3, or m4b.")
        }

        let selectedVoice = try resolveVoice(engine: engine, voiceName: voice)

        // Resolve metadata (prompts interactively if TTY, pre-fills from epub)
        let chapters = inputs.map { Chapter(title: URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent, text: "") }
        let (resolvedAuthor, resolvedTitle) = resolveMetadata(chapters: chapters)

        // Extract track numbers from filenames
        let trackNumbers = extractTrackNumbers(from: inputs)

        var successes: [String] = []
        var failures: [String] = []
        for (i, input) in inputs.enumerated() {
            if inputs.count > 1 {
                let voiceName = selectedVoice.name
                ProgressReporter.fileHeader("[\(i + 1)/\(inputs.count)] \(URL(fileURLWithPath: input).lastPathComponent) (\(voiceName))", quiet: quiet)
            }
            do {
                try convertSingleFile(
                    input: input,
                    engine: engine,
                    voice: selectedVoice,
                    format: fmt,
                    author: resolvedAuthor,
                    title: resolvedTitle,
                    trackNumber: trackNumbers[i],
                    trackTotal: inputs.count
                )
                successes.append(input)
            } catch {
                fputs("Error converting \(input): \(error)\n", stderr)
                failures.append(input)
            }
        }

        // Batch summary
        if inputs.count > 1 && !quiet {
            if !successes.isEmpty {
                fputs("\(successes.count) of \(inputs.count) files converted successfully.\n", stderr)
            }
            if !failures.isEmpty {
                fputs("\(failures.count) of \(inputs.count) files failed:\n", stderr)
                for f in failures { fputs("  \(f)\n", stderr) }
            }
        }
        if !failures.isEmpty {
            throw ExitCode(1)
        }
    }

    private func convertSingleFile(
        input: String,
        engine: YapperEngine,
        voice: Voice,
        format: String,
        author: String? = nil,
        title: String? = nil,
        trackNumber: Int? = nil,
        trackTotal: Int? = nil
    ) throws {
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

        // Clean text of residual markup from pandoc extraction
        let cleaned = cleanMarkup(trimmed)

        let outputPath = resolveOutputPath(for: input, format: format)
        let trackTitle = URL(fileURLWithPath: input).deletingPathExtension().lastPathComponent

        if dryRun {
            print("Would convert: \(input)")
            print("  Output: \(outputPath)")
            print("  Format: \(format)")
            print("  Voice: \(voice.name)")
            print("  Speed: \(speed)")
            if let author { print("  Author: \(author)") }
            if let title { print("  Title: \(title)") }
            if let trackNumber {
                let trackStr = trackTotal != nil ? "\(trackNumber)/\(trackTotal!)" : "\(trackNumber)"
                print("  Track: \(trackStr)")
            }
            print("  Track title: \(trackTitle)")
            print("  Text: \(cleaned)")
            return
        }

        // Check output directory exists before spending time on synthesis
        let outputDir = URL(fileURLWithPath: outputPath).deletingLastPathComponent().path
        if !outputDir.isEmpty && outputDir != "." {
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: outputDir, isDirectory: &isDir) || !isDir.boolValue {
                throw ValidationError("Output directory does not exist: \(outputDir)")
            }
        }

        if FileManager.default.fileExists(atPath: outputPath) {
            let backupPath = nextBackupPath(for: outputPath)
            try FileManager.default.moveItem(atPath: outputPath, toPath: backupPath)
            fputs("Backed up existing \(outputPath) to \(backupPath)\n", stderr)
        }

        // Pre-chunk for progress reporting
        let chunker = TextChunker()
        let textChunks = chunker.chunk(cleaned)
        let fileLabel = URL(fileURLWithPath: input).lastPathComponent
        ProgressReporter.fileHeader("Synthesising \(fileLabel)...", quiet: quiet)
        var reporter = ProgressReporter(totalChunks: textChunks.count, quiet: quiet)

        // Synthesise with per-chunk progress
        var allSamples: [Float] = []
        var chunkIdx = 0
        try engine.stream(text: cleaned, voice: voice, speed: speed) { chunk in
            let chunkText = chunkIdx < textChunks.count ? textChunks[chunkIdx].text : ""
            chunkIdx += 1
            reporter.update(chunkText: chunkText)
            allSamples.append(contentsOf: chunk.samples)
        }
        let sampleRate = 24000
        reporter.finish(summary: "")

        let tmpWav = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_convert_\(ProcessInfo.processInfo.processIdentifier).wav")
        try writeWav(samples: allSamples, sampleRate: sampleRate, to: tmpWav)
        defer { try? FileManager.default.removeItem(at: tmpWav) }

        try encodeWithFFmpeg(
            input: tmpWav.path,
            output: outputPath,
            format: format,
            author: author,
            title: title,
            trackNumber: trackNumber,
            trackTotal: trackTotal,
            trackTitle: trackTitle
        )

        let duration = Double(allSamples.count) / Double(sampleRate)
        if !quiet {
            fputs("Created \(outputPath) (\(String(format: "%.1f", duration))s)\n", stderr)
        }
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

        // Interactive prompts if TTY (unless --non-interactive)
        let isTTY = isatty(FileHandle.standardInput.fileDescriptor) != 0
        if !nonInteractive && (isTTY || interactive) {
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

    // MARK: - Text cleanup

    /// Clean residual markup from pandoc-extracted text before synthesis.
    /// Without this, TTS reads HTML tags, markdown image syntax, and other
    /// markup aloud. Inherited from make-audiobook's sed cleanup pipeline.
    private func cleanMarkup(_ text: String) -> String {
        var result = text

        // Strip HTML/XML tags
        result = result.replacingOccurrences(
            of: "<[^>]*>", with: "", options: .regularExpression)

        // Strip markdown image links: ![alt](url)
        result = result.replacingOccurrences(
            of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)

        // Strip image references: !(path)
        result = result.replacingOccurrences(
            of: #"!\([^)]*\)"#, with: "", options: .regularExpression)

        // Convert markdown links [text](url) to just text
        result = result.replacingOccurrences(
            of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)

        // Strip {class} attribute blocks
        result = result.replacingOccurrences(
            of: #"\{[^}]*\}"#, with: "", options: .regularExpression)

        // Strip ::: directive lines
        result = result.replacingOccurrences(
            of: #"(?m)^:::.*$"#, with: "", options: .regularExpression)

        // Strip stray backslashes
        result = result.replacingOccurrences(of: "\\", with: "")

        // Strip empty bracket pairs
        result = result.replacingOccurrences(of: "[]", with: "")

        // Collapse multiple blank lines
        result = result.replacingOccurrences(
            of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Track number extraction

    /// Extract track numbers from input filenames when they form a consecutive
    /// sequence (starting from 0 or 1, incrementing by 1, allowing zero-padding).
    /// Returns an array of track numbers (1-based for metadata), or positional
    /// fallback (1, 2, 3, ...) when no valid sequence is detected.
    private func extractTrackNumbers(from inputs: [String]) -> [Int] {
        let filenames = inputs.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }

        // Extract the first integer from each filename
        let regex = try? NSRegularExpression(pattern: #"(\d+)"#)
        let extracted: [Int?] = filenames.map { name in
            guard let regex,
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let range = Range(match.range(at: 1), in: name) else {
                return nil
            }
            return Int(name[range])
        }

        // Check if all filenames have integers
        let allHaveIntegers = extracted.allSatisfy { $0 != nil }
        guard allHaveIntegers, let numbers = extracted as? [Int] else {
            // Positional fallback
            return Array(1...inputs.count)
        }

        // Check if they form a consecutive sequence starting from 0 or 1
        let sorted = numbers.sorted()
        let startsCorrectly = sorted.first == 0 || sorted.first == 1
        let isConsecutive = zip(sorted, sorted.dropFirst()).allSatisfy { $1 - $0 == 1 }

        if startsCorrectly && isConsecutive {
            // Use the extracted numbers but shift 0-based sequences to 1-based
            // for metadata (track 0 is not meaningful in ID3/MP4 tags)
            if sorted.first == 0 {
                return numbers.map { $0 + 1 }
            }
            return numbers
        }

        // Non-consecutive or doesn't start from 0/1 → positional fallback
        return Array(1...inputs.count)
    }

    // MARK: - FFmpeg encoding

    private func encodeWithFFmpeg(input: String, output: String, format: String) throws {
        try encodeWithFFmpeg(input: input, output: output, format: format,
                            author: self.author, title: self.title,
                            trackNumber: nil, trackTotal: nil, trackTitle: nil)
    }

    private func encodeWithFFmpeg(
        input: String,
        output: String,
        format: String,
        author: String?,
        title: String?,
        trackNumber: Int?,
        trackTotal: Int?,
        trackTitle: String?
    ) throws {
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
        if let trackNumber {
            let trackStr = trackTotal != nil ? "\(trackNumber)/\(trackTotal!)" : "\(trackNumber)"
            args += ["-metadata", "track=\(trackStr)"]
        }
        if let trackTitle {
            args += ["-metadata", "title=\(trackTitle)"]
        }

        args.append(output)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
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
