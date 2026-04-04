// ABOUTME: CLI command for live TTS playback through system speakers.
// ABOUTME: Reads text from argument or stdin, synthesises and plays audio.

import ArgumentParser
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

    func run() throws {
        let inputText = try resolveInputText()

        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )
        let selectedVoice = try resolveVoice(engine: engine)
        let player = AudioPlayer()

        // Register SIGINT handler for clean shutdown
        signal(SIGINT) { _ in
            _exit(130)
        }

        // Stream chunk-by-chunk for perceived low latency
        var started = false
        try engine.stream(text: inputText, voice: selectedVoice, speed: speed) { chunk in
            try? player.scheduleBuffer(chunk.samples)
            if !started {
                try? player.play()
                started = true
            }
        }

        // If single chunk and not started yet
        if !started, player.state == .idle {
            try player.play()
        }

        // Wait for playback to finish
        while player.state == .playing {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
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
}
