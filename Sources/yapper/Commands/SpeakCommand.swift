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

    func run() throws {
        let inputText = try resolveInputText()

        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )
        let selectedVoice = try resolveVoice(engine: engine)

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
