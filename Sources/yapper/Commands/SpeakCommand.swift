// ABOUTME: CLI command for live TTS playback through system speakers.
// ABOUTME: Reads text from argument or stdin, synthesises and plays audio.

import ArgumentParser
import AVFoundation
import Foundation
import YapperKit

struct SpeakCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "speak",
        abstract: "Speak text aloud through system speakers."
    )

    @Argument(help: "Text to speak. If omitted, reads from stdin.")
    var text: String?

    @Option(name: .long, help: "Voice name (e.g. af_heart, bm_daniel).")
    var voice: String?

    @Option(name: .long, help: "Speech speed multiplier (default: 1.0).")
    var speed: Float = 1.0

    @Flag(name: .long, help: "Print resolved voice, speed, and text without performing synthesis.")
    var dryRun: Bool = false

    func run() throws {
        let inputText = try resolveInputText()

        // Dry-run path: load only the voice registry (cheap, no 327MB model weights),
        // resolve the voice, print the resolved parameters, and exit without synthesising.
        if dryRun {
            let registry = try VoiceRegistry(voicesPath: defaultVoicesPath())
            let resolved = try resolveVoice(registry: registry)
            print("voice:  \(resolved.name)")
            print("speed:  \(speed)")
            print("text:   \(inputText)")
            print("(dry run — no synthesis performed)")
            return
        }

        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )
        let selectedVoice = try resolveVoice(registry: engine.voiceRegistry)

        // Synthesise
        let result = try engine.synthesize(text: inputText, voice: selectedVoice, speed: speed)

        // Write to temp WAV and play via afplay (AVAudioEngine doesn't reliably
        // produce sound from CLI processes without an audio session)
        let tmpPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_speak_\(ProcessInfo.processInfo.processIdentifier).wav")
        try writeWav(samples: result.samples, sampleRate: result.sampleRate, to: tmpPath)
        defer { try? FileManager.default.removeItem(at: tmpPath) }

        let afplay = Process()
        afplay.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        afplay.arguments = [tmpPath.path]

        signal(SIGINT) { _ in
            // afplay handles its own cleanup
            _exit(130)
        }

        try afplay.run()
        afplay.waitUntilExit()
    }

    private func resolveInputText() throws -> String {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        // Read from stdin if no argument and stdin is piped
        if isatty(FileHandle.standardInput.fileDescriptor) == 0 {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let stdinText = String(data: data, encoding: .utf8),
                  !stdinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError("No text provided. Stdin was empty or not valid UTF-8.")
            }
            return stdinText
        }

        throw ValidationError(
            "No text provided. Usage: yapper speak \"text\" or echo \"text\" | yapper speak"
        )
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

    /// Resolve the voice to use for this invocation.
    ///
    /// Precedence (highest first):
    ///   1. `--voice <name>` CLI flag
    ///   2. `$YAPPER_VOICE` environment variable
    ///   3. Random selection from the registry (non-deterministic per call)
    ///
    /// Invalid names from either --voice or $YAPPER_VOICE produce a clear error
    /// identifying the source — no silent fallback to random or any hardcoded voice.
    private func resolveVoice(registry: VoiceRegistry) throws -> Voice {
        // 1. --voice CLI flag wins unconditionally
        if let voiceName = voice {
            return try lookupVoice(voiceName, in: registry, source: "--voice flag")
        }
        // 2. $YAPPER_VOICE env var — whitespace-only treated as unset
        if let raw = ProcessInfo.processInfo.environment["YAPPER_VOICE"] {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return try lookupVoice(trimmed, in: registry, source: "$YAPPER_VOICE")
            }
        }
        // 3. Random selection — no hardcoded voice name fallback
        guard let chosen = registry.randomSystem() else {
            throw ValidationError(
                "No voices found in the registry at \(registry.voicesPath.path)."
            )
        }
        return chosen
    }

    private func lookupVoice(_ name: String, in registry: VoiceRegistry, source: String) throws -> Voice {
        guard let v = registry.voices.first(where: { $0.name == name }) else {
            let available = registry.voices.prefix(5).map(\.name).joined(separator: ", ")
            throw ValidationError(
                "Voice '\(name)' not found (from \(source)). Available: \(available)..."
            )
        }
        return v
    }
}
