// ABOUTME: Proof-of-concept for multi-process concurrent synthesis.
// ABOUTME: Spawns separate yapper processes per character to get independent Metal contexts.

import ArgumentParser
import AVFoundation
import Foundation
import YapperKit

struct BatchPOC: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch-poc",
        abstract: "POC: multi-process concurrent synthesis vs sequential."
    )

    // Public mode: run the comparison
    @Argument(help: "Input script file (.md or .org).")
    var input: String

    @Option(name: .long, help: "Scene number (1-indexed). Defaults to largest scene.")
    var scene: Int?

    @Option(name: .long, help: "Script config YAML file.")
    var scriptConfig: String?

    @Option(name: .long, help: "Speech speed multiplier (default: 1.0).")
    var speed: Float = 1.0

    @Option(name: .long, help: "Output directory for WAV files.")
    var outputDir: String = "/tmp/yapper_batch_poc"

    @Option(name: .long, help: "Pause between lines in seconds (default: 0.3).")
    var pause: Double = 0.3

    // Internal: worker mode (synthesise a single line, write WAV, exit)
    @Option(name: .long, help: .hidden)
    var workerText: String?

    @Option(name: .long, help: .hidden)
    var workerVoice: String?

    @Option(name: .long, help: .hidden)
    var workerOutput: String?

    func run() throws {
        // Worker mode: synthesise one line and exit
        if let text = workerText, let voiceName = workerVoice, let output = workerOutput {
            try runWorker(text: text, voiceName: voiceName, output: output)
            return
        }

        // Main mode: run comparison
        try runComparison()
    }

    private func runWorker(text: String, voiceName: String, output: String) throws {
        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )
        guard let voice = engine.voiceRegistry.voices.first(where: { $0.name == voiceName }) else {
            throw ValidationError("Voice \(voiceName) not found.")
        }
        let result = try engine.synthesize(text: text, voice: voice, speed: speed)
        let url = URL(fileURLWithPath: output)
        try writeWav(samples: result.samples, sampleRate: 24000, to: url)
    }

    private func runComparison() throws {
        // Parse script
        let config: ScriptConfig?
        if let sc = scriptConfig {
            config = try ScriptConfig.load(from: sc)
        } else {
            let inputDir = URL(fileURLWithPath: input).deletingLastPathComponent().path
            let autoPath = "\(inputDir)/script.yaml"
            if FileManager.default.fileExists(atPath: autoPath) {
                config = try ScriptConfig.load(from: autoPath)
            } else {
                config = nil
            }
        }
        guard let script = try ScriptParser.parse(filePath: input, config: config) else {
            throw ValidationError("Could not parse \(input) as a script.")
        }

        guard !script.scenes.isEmpty else {
            throw ValidationError("Script has no scenes.")
        }

        let sceneIdx: Int
        if let s = scene {
            guard s >= 1 && s <= script.scenes.count else {
                throw ValidationError("Scene \(s) out of range (1..\(script.scenes.count)).")
            }
            sceneIdx = s - 1
        } else {
            sceneIdx = script.scenes.enumerated().max(by: { $0.element.entries.count < $1.element.entries.count })!.offset
        }
        let targetScene = script.scenes[sceneIdx]
        let readStage = config?.readStageDirections ?? true

        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )
        let (charVoices, narrator) = VoiceAssigner.assign(
            characters: script.characters,
            config: config,
            registry: engine.voiceRegistry
        )

        fputs("Scene: \(targetScene.title)\n", stderr)
        fputs("Entries: \(targetScene.entries.count)\n", stderr)
        fputs("Cast: \(script.characters.map { "\($0)=\(charVoices[$0]?.name ?? "?")" }.joined(separator: ", "))\n", stderr)
        fputs("Narrator: \(narrator.name)\n", stderr)
        fputs("Speed: \(speed), Pause: \(pause)s\n\n", stderr)

        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        let pauseSamples = [Float](repeating: 0, count: Int(pause * 24000))

        struct WorkItem {
            let index: Int
            let text: String
            let voiceName: String
            let label: String
        }

        var workItems: [WorkItem] = []
        for (i, entry) in targetScene.entries.enumerated() {
            switch entry.type {
            case .dialogue(let char):
                guard let v = charVoices[char] else { continue }
                workItems.append(WorkItem(index: i, text: entry.text, voiceName: v.name, label: char))
            case .stageDirection:
                guard readStage else { continue }
                workItems.append(WorkItem(index: i, text: entry.text, voiceName: narrator.name, label: "[stage]"))
            }
        }

        fputs("Work items: \(workItems.count)\n\n", stderr)

        // ============================================================
        // Sequential baseline (in-process)
        // ============================================================
        fputs("=== Sequential (in-process) ===\n", stderr)
        let seqStart = CFAbsoluteTimeGetCurrent()
        var seqResults: [Int: [Float]] = [:]

        for item in workItems {
            let voice = engine.voiceRegistry.voices.first(where: { $0.name == item.voiceName })!
            let result = try engine.synthesize(text: item.text, voice: voice, speed: speed)
            seqResults[item.index] = result.samples
        }

        let seqTotal = CFAbsoluteTimeGetCurrent() - seqStart
        let seqSamples = assembleSamples(seqResults, pause: pauseSamples)
        let seqAudio = Double(seqSamples.count) / 24000.0
        fputs("  Total: \(String(format: "%.2f", seqTotal))s wall, \(String(format: "%.1f", seqAudio))s audio\n", stderr)
        let seqURL = URL(fileURLWithPath: outputDir).appendingPathComponent("sequential.wav")
        try writeWav(samples: seqSamples, sampleRate: 24000, to: seqURL)
        fputs("  Written: \(seqURL.path)\n\n", stderr)

        // ============================================================
        // Multi-process concurrent
        // ============================================================
        // Find the yapper binary path
        let yapperPath = CommandLine.arguments[0]
        let tmpDir = URL(fileURLWithPath: outputDir).appendingPathComponent("worker_wavs")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        for concurrency in [2, 3, 4] {
            fputs("=== Multi-process (\(concurrency)-way) ===\n", stderr)

            // Clean worker dir
            let items = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path)) ?? []
            for item in items {
                try? FileManager.default.removeItem(atPath: tmpDir.appendingPathComponent(item).path)
            }

            let concStart = CFAbsoluteTimeGetCurrent()
            let semaphore = DispatchSemaphore(value: concurrency)
            let group = DispatchGroup()
            let lock = NSLock()
            var failures: [String] = []

            for item in workItems {
                semaphore.wait()
                group.enter()

                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        semaphore.signal()
                        group.leave()
                    }

                    let wavPath = tmpDir.appendingPathComponent("entry_\(String(format: "%03d", item.index)).wav").path

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: yapperPath)
                    process.arguments = [
                        "batch-poc", self.input,
                        "--worker-text", item.text,
                        "--worker-voice", item.voiceName,
                        "--worker-output", wavPath,
                        "--speed", String(self.speed)
                    ]
                    process.standardInput = FileHandle.nullDevice
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice

                    do {
                        try process.run()
                        process.waitUntilExit()
                        if process.terminationStatus != 0 {
                            lock.lock()
                            failures.append("[\(item.index)] \(item.label): exit \(process.terminationStatus)")
                            lock.unlock()
                        }
                    } catch {
                        lock.lock()
                        failures.append("[\(item.index)] \(item.label): \(error)")
                        lock.unlock()
                    }
                }
            }

            group.wait()
            let concTotal = CFAbsoluteTimeGetCurrent() - concStart

            if !failures.isEmpty {
                fputs("  Failures:\n", stderr)
                for f in failures { fputs("    \(f)\n", stderr) }
                fputs("\n", stderr)
                continue
            }

            // Read back WAVs and assemble
            var concResults: [Int: [Float]] = [:]
            for item in workItems {
                let wavPath = tmpDir.appendingPathComponent("entry_\(String(format: "%03d", item.index)).wav")
                let samples = try readWavSamples(from: wavPath)
                concResults[item.index] = samples
            }

            let concSamples = assembleSamples(concResults, pause: pauseSamples)
            let concAudio = Double(concSamples.count) / 24000.0
            fputs("  Total: \(String(format: "%.2f", concTotal))s wall, \(String(format: "%.1f", concAudio))s audio\n", stderr)
            fputs("  Speedup vs sequential: \(String(format: "%.2fx", seqTotal / concTotal))\n", stderr)

            let concURL = URL(fileURLWithPath: outputDir).appendingPathComponent("concurrent_\(concurrency)way.wav")
            try writeWav(samples: concSamples, sampleRate: 24000, to: concURL)
            fputs("  Written: \(concURL.path)\n\n", stderr)
        }

        fputs("\n=== Summary ===\n", stderr)
        fputs("  Sequential: \(String(format: "%.2f", seqTotal))s\n", stderr)
        fputs("  Listen to WAVs in \(outputDir)\n", stderr)
    }

    private func assembleSamples(_ results: [Int: [Float]], pause: [Float]) -> [Float] {
        var samples: [Float] = []
        for idx in results.keys.sorted() {
            if !samples.isEmpty { samples.append(contentsOf: pause) }
            samples.append(contentsOf: results[idx]!)
        }
        return samples
    }

    private func readWavSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ValidationError("Could not create buffer for \(url.path)")
        }
        try file.read(into: buffer)
        let channelData = buffer.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
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
