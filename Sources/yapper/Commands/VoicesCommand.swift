// ABOUTME: CLI command to list available voices and preview them.
// ABOUTME: Displays voice metadata in a formatted table.

import ArgumentParser
import Foundation
import YapperKit

struct VoicesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "voices",
        abstract: "List available voices or preview a voice."
    )

    @Option(name: .long, help: "Preview a voice by speaking a sample sentence.")
    var preview: String?

    func run() throws {
        if let previewName = preview {
            // Preview needs full engine (model loading + synthesis)
            let engine = try YapperEngine(
                modelPath: defaultModelPath(),
                voicesPath: defaultVoicesPath()
            )
            try previewVoice(engine: engine, name: previewName)
        } else {
            // Listing only needs the voice registry (no model loading)
            let registry = try VoiceRegistry(voicesPath: defaultVoicesPath())
            listVoices(registry: registry)
        }
    }

    private func listVoices(registry: VoiceRegistry) {
        let voices = registry.voices

        if voices.isEmpty {
            fputs("No voices found in \(defaultVoicesPath().path)\n", stderr)
            fputs("Download voices from https://huggingface.co/mlx-community/Kokoro-82M-bf16\n", stderr)
            return
        }

        // Header
        print(String(format: "%-14s %-10s %s", "Name", "Accent", "Gender"))
        print(String(repeating: "-", count: 34))

        for voice in voices {
            let accentLabel = voice.accent == .american ? "American" : "British"
            let genderLabel = voice.gender == .female ? "Female" : "Male"
            print(String(format: "%-14s %-10s %s", voice.name, accentLabel, genderLabel))
        }

        print("\n\(voices.count) voices available.")
    }

    private func previewVoice(engine: YapperEngine, name: String) throws {
        guard let voice = engine.voiceRegistry.voices.first(where: { $0.name == name }) else {
            let available = engine.voiceRegistry.voices.prefix(5).map(\.name).joined(separator: ", ")
            throw ValidationError("Voice '\(name)' not found. Available: \(available)...")
        }

        let sampleText = "Hello, this is the \(name) voice."
        let player = AudioPlayer()

        signal(SIGINT) { _ in _exit(130) }

        var started = false
        try engine.stream(text: sampleText, voice: voice, speed: 1.0) { chunk in
            try? player.scheduleBuffer(chunk.samples)
            if !started {
                try? player.play()
                started = true
            }
        }

        if !started, player.state == .idle {
            try player.play()
        }

        while player.state == .playing {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
    }
}
