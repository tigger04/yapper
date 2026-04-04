// ABOUTME: CLI command for converting text files to audio (M4A/MP3).
// ABOUTME: Synthesises via YapperKit, encodes via ffmpeg.

import ArgumentParser
import AVFoundation
import Foundation
import YapperKit

struct ConvertCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert text files to audio."
    )

    @Argument(help: "Input file(s) to convert.")
    var inputs: [String]

    @Option(name: .shortAndLong, help: "Output file path.")
    var output: String?

    @Option(name: .long, help: "Output format: m4a (default), mp3.")
    var format: String = "m4a"

    @Option(name: .long, help: "Voice name (e.g. af_heart, bm_daniel).")
    var voice: String?

    @Option(name: .long, help: "Speech speed multiplier (default: 1.0).")
    var speed: Float = 1.0

    @Option(name: .long, help: "Author metadata for the output file.")
    var author: String?

    @Option(name: .long, help: "Title metadata for the output file.")
    var title: String?

    @Flag(name: .long, help: "Show what would be done without converting.")
    var dryRun: Bool = false

    func run() throws {
        guard !inputs.isEmpty else {
            throw ValidationError("No input files specified.")
        }

        guard ["m4a", "mp3"].contains(format.lowercased()) else {
            throw ValidationError("Unsupported format '\(format)'. Use m4a or mp3.")
        }

        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )
        let selectedVoice = try resolveVoice(engine: engine)

        var failures = 0
        for input in inputs {
            do {
                try convertFile(
                    input: input,
                    engine: engine,
                    voice: selectedVoice
                )
            } catch {
                fputs("Error converting \(input): \(error.localizedDescription)\n", stderr)
                failures += 1
            }
        }

        if failures > 0 {
            fputs("\(failures) of \(inputs.count) files failed.\n", stderr)
            throw ExitCode(1)
        }
    }

    private func convertFile(
        input: String,
        engine: YapperEngine,
        voice: Voice
    ) throws {
        // Validate input exists
        guard FileManager.default.fileExists(atPath: input) else {
            throw ValidationError("Input file not found: \(input)")
        }

        // Read and validate text
        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        guard let text = String(data: data, encoding: .utf8) else {
            throw ValidationError(
                "File is not valid UTF-8: \(input). Convert to UTF-8 first."
            )
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError("File is empty or whitespace-only: \(input)")
        }

        // Determine output path
        let outputPath = resolveOutputPath(for: input)

        // Dry run
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

        // Back up existing output
        if FileManager.default.fileExists(atPath: outputPath) {
            let backupPath = nextBackupPath(for: outputPath)
            try FileManager.default.moveItem(atPath: outputPath, toPath: backupPath)
            fputs("Backed up existing \(outputPath) to \(backupPath)\n", stderr)
        }

        // Synthesise
        fputs("Synthesising \(input)...\n", stderr)
        let result = try engine.synthesize(text: trimmed, voice: voice, speed: speed)

        // Write temp WAV
        let tmpWav = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_convert_\(ProcessInfo.processInfo.processIdentifier).wav")
        try writeWav(samples: result.samples, sampleRate: result.sampleRate, to: tmpWav)
        defer { try? FileManager.default.removeItem(at: tmpWav) }

        // Encode via ffmpeg
        try encodeWithFFmpeg(input: tmpWav.path, output: outputPath)

        let duration = Double(result.samples.count) / Double(result.sampleRate)
        fputs("Created \(outputPath) (\(String(format: "%.1f", duration))s)\n", stderr)
    }

    private func resolveOutputPath(for input: String) -> String {
        if let output { return output }
        let url = URL(fileURLWithPath: input)
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent().path
        return "\(dir)/\(base).\(format)"
    }

    private func nextBackupPath(for path: String) -> String {
        let bak = "\(path).bak"
        if !FileManager.default.fileExists(atPath: bak) { return bak }
        var n = 1
        while FileManager.default.fileExists(atPath: "\(path).\(n).bak") { n += 1 }
        return "\(path).\(n).bak"
    }

    private func encodeWithFFmpeg(input: String, output: String) throws {
        guard let ffmpegPath = findTool("ffmpeg") else {
            throw ValidationError(
                "ffmpeg not found. Install via: brew install ffmpeg"
            )
        }

        var args = ["-y", "-i", input]

        if format.lowercased() == "m4a" {
            args += ["-c:a", "aac", "-b:a", "64k"]
        } else {
            args += ["-c:a", "libmp3lame", "-b:a", "128k"]
        }

        if let author {
            args += ["-metadata", "artist=\(author)", "-metadata", "album_artist=\(author)"]
        }
        if let title {
            args += ["-metadata", "album=\(title)"]
        }

        args.append(output)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ValidationError("ffmpeg exited with status \(process.terminationStatus)")
        }
    }

    private func findTool(_ name: String) -> String? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func resolveVoice(engine: YapperEngine) throws -> Voice {
        if let voiceName = voice {
            guard let v = engine.voiceRegistry.voices.first(where: { $0.name == voiceName }) else {
                let available = engine.voiceRegistry.voices.prefix(5).map(\.name).joined(separator: ", ")
                throw ValidationError("Voice '\(voiceName)' not found. Available: \(available)...")
            }
            return v
        }
        return engine.voiceRegistry.voices.first { $0.name == "af_heart" }
            ?? engine.voiceRegistry.voices[0]
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
