// ABOUTME: Proof-of-concept for batched character synthesis.
// ABOUTME: Compares sequential per-line synthesis vs period-joined batch synthesis.

import ArgumentParser
import AVFoundation
import Foundation
import YapperKit

struct BatchPOC: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch-poc",
        abstract: "POC: compare sequential vs batched character synthesis."
    )

    @Argument(help: "Input script file (.md or .org).")
    var input: String

    @Option(name: .long, help: "Character name to batch (e.g. ALICE). Defaults to first character.")
    var character: String?

    @Option(name: .long, help: "Scene number (1-indexed). Defaults to largest scene.")
    var scene: Int?

    @Option(name: .long, help: "Voice name (e.g. bf_emma). Defaults to auto-assign.")
    var voice: String?

    @Option(name: .long, help: "Script config YAML file.")
    var scriptConfig: String?

    @Option(name: .long, help: "Speech speed multiplier (default: 1.0).")
    var speed: Float = 1.0

    @Option(name: .long, help: "Output directory for WAV files.")
    var outputDir: String = "/tmp/yapper_batch_poc"

    func run() throws {
        // Parse script
        let config = try scriptConfig.flatMap { try ScriptConfig.load(from: $0) }
        guard let script = try ScriptParser.parse(filePath: input, config: config) else {
            throw ValidationError("Could not parse \(input) as a script.")
        }

        guard !script.scenes.isEmpty else {
            throw ValidationError("Script has no scenes.")
        }

        // Pick scene
        let sceneIdx: Int
        if let s = scene {
            guard s >= 1 && s <= script.scenes.count else {
                throw ValidationError("Scene \(s) out of range (1..\(script.scenes.count)).")
            }
            sceneIdx = s - 1
        } else {
            // Pick scene with most entries
            sceneIdx = script.scenes.enumerated().max(by: { $0.element.entries.count < $1.element.entries.count })!.offset
        }
        let targetScene = script.scenes[sceneIdx]

        // Pick character
        let charName: String
        if let c = character {
            charName = c.uppercased()
        } else {
            // Pick character with most lines in this scene
            var counts: [String: Int] = [:]
            for entry in targetScene.entries {
                if case .dialogue(let c) = entry.type { counts[c, default: 0] += 1 }
            }
            guard let best = counts.max(by: { $0.value < $1.value }) else {
                throw ValidationError("Scene has no dialogue.")
            }
            charName = best.key
        }

        // Extract this character's lines from the scene
        let lines = targetScene.entries.compactMap { entry -> String? in
            if case .dialogue(let c) = entry.type, c == charName { return entry.text }
            return nil
        }

        guard !lines.isEmpty else {
            throw ValidationError("\(charName) has no lines in scene \(sceneIdx + 1).")
        }

        fputs("Scene: \(targetScene.title)\n", stderr)
        fputs("Character: \(charName)\n", stderr)
        fputs("Lines: \(lines.count)\n", stderr)
        for (i, line) in lines.enumerated() {
            fputs("  [\(i + 1)] \(line)\n", stderr)
        }
        fputs("\n", stderr)

        // Set up engine
        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )
        let resolvedVoice: Voice
        if let v = voice {
            guard let found = engine.voiceRegistry.voices.first(where: { $0.name == v }) else {
                throw ValidationError("Voice \(v) not found.")
            }
            resolvedVoice = found
        } else {
            let (assigned, _) = VoiceAssigner.assign(
                characters: script.characters,
                config: config,
                registry: engine.voiceRegistry
            )
            resolvedVoice = assigned[charName] ?? engine.voiceRegistry.voices[0]
        }
        fputs("Voice: \(resolvedVoice.name)\n\n", stderr)

        // Create output directory
        try FileManager.default.createDirectory(
            atPath: outputDir,
            withIntermediateDirectories: true
        )

        // --- Sequential: one synthesize() call per line ---
        fputs("=== Sequential (one call per line) ===\n", stderr)
        let seqStart = CFAbsoluteTimeGetCurrent()
        var seqSamples: [Float] = []
        for (i, line) in lines.enumerated() {
            let lineStart = CFAbsoluteTimeGetCurrent()
            let result = try engine.synthesize(text: line, voice: resolvedVoice, speed: speed)
            let lineTime = CFAbsoluteTimeGetCurrent() - lineStart
            fputs("  Line \(i + 1): \(String(format: "%.2f", lineTime))s (\(result.samples.count) samples)\n", stderr)
            seqSamples.append(contentsOf: result.samples)
        }
        let seqTotal = CFAbsoluteTimeGetCurrent() - seqStart
        let seqDuration = Double(seqSamples.count) / 24000.0
        fputs("  Total: \(String(format: "%.2f", seqTotal))s wall, \(String(format: "%.1f", seqDuration))s audio\n", stderr)
        fputs("  RTF: \(String(format: "%.2fx", seqDuration / seqTotal))\n\n", stderr)

        let seqURL = URL(fileURLWithPath: outputDir).appendingPathComponent("sequential.wav")
        try writeWav(samples: seqSamples, sampleRate: 24000, to: seqURL)
        fputs("  Written: \(seqURL.path)\n\n", stderr)

        // --- Batched: join lines with periods, one synthesize() call ---
        fputs("=== Batched (period-joined, one call) ===\n", stderr)
        let terminators: Set<Character> = [".", "!", "?", ";", ":", "\u{2014}"]
        let joined = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let last = trimmed.last, terminators.contains(last) {
                return trimmed
            }
            return trimmed + "."
        }.joined(separator: " ")
        fputs("  Joined text (\(joined.count) chars): \(joined.prefix(120))...\n", stderr)

        let batchStart = CFAbsoluteTimeGetCurrent()
        let batchResult = try engine.synthesize(text: joined, voice: resolvedVoice, speed: speed)
        let batchTotal = CFAbsoluteTimeGetCurrent() - batchStart
        let batchDuration = Double(batchResult.samples.count) / 24000.0
        fputs("  Total: \(String(format: "%.2f", batchTotal))s wall, \(String(format: "%.1f", batchDuration))s audio\n", stderr)
        fputs("  RTF: \(String(format: "%.2fx", batchDuration / batchTotal))\n", stderr)
        fputs("  Speedup: \(String(format: "%.1fx", seqTotal / batchTotal))\n\n", stderr)

        let batchURL = URL(fileURLWithPath: outputDir).appendingPathComponent("batched.wav")
        try writeWav(samples: batchResult.samples, sampleRate: 24000, to: batchURL)
        fputs("  Written: \(batchURL.path)\n\n", stderr)

        // --- Batched with \n\n: join lines with paragraph breaks ---
        fputs("=== Batched (paragraph-joined, one call) ===\n", stderr)
        let parJoined = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let last = trimmed.last, terminators.contains(last) {
                return trimmed
            }
            return trimmed + "."
        }.joined(separator: "\n\n")

        let parStart = CFAbsoluteTimeGetCurrent()
        let parResult = try engine.synthesize(text: parJoined, voice: resolvedVoice, speed: speed)
        let parTotal = CFAbsoluteTimeGetCurrent() - parStart
        let parDuration = Double(parResult.samples.count) / 24000.0
        fputs("  Total: \(String(format: "%.2f", parTotal))s wall, \(String(format: "%.1f", parDuration))s audio\n", stderr)
        fputs("  RTF: \(String(format: "%.2fx", parDuration / parTotal))\n", stderr)
        fputs("  Speedup vs seq: \(String(format: "%.1fx", seqTotal / parTotal))\n\n", stderr)

        let parURL = URL(fileURLWithPath: outputDir).appendingPathComponent("paragraph.wav")
        try writeWav(samples: parResult.samples, sampleRate: 24000, to: parURL)
        fputs("  Written: \(parURL.path)\n\n", stderr)

        // Summary
        fputs("=== Summary ===\n", stderr)
        fputs("  Sequential:  \(String(format: "%.2f", seqTotal))s (\(lines.count) calls)\n", stderr)
        fputs("  Batched (.): \(String(format: "%.2f", batchTotal))s (1 call)\n", stderr)
        fputs("  Batched (¶): \(String(format: "%.2f", parTotal))s (1 call, \(lines.count) chunks)\n", stderr)
        fputs("\nListen to the WAVs in \(outputDir) to compare quality.\n", stderr)
    }

    private func writeWav(samples: [Float], sampleRate: Int, to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw ValidationError("Could not create audio format.")
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw ValidationError("Could not create audio buffer.")
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        for (i, sample) in samples.enumerated() {
            channelData[i] = sample
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
