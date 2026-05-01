// ABOUTME: POC #30 — contextual dialogue synthesis comparison.
// ABOUTME: Mode B: synthesise full scene per voice, splice by word timestamps.

import ArgumentParser
import AVFoundation
import Foundation
import YapperKit

struct ContextPOC: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "context-poc",
        abstract: "POC: synthesise full dialogue per voice, splice into scene order."
    )

    @Argument(help: "Input script file (.org, .md, .fountain).")
    var input: String

    @Option(name: .long, help: "Script config YAML file.")
    var scriptConfig: String?

    @Option(name: .long, help: "Scene number (1-indexed). Defaults to first scene.")
    var scene: Int?

    @Option(name: .long, help: "Speech speed multiplier (default: 1.0).")
    var speed: Float = 1.0

    @Option(name: .long, help: "Output directory for WAV files.")
    var outputDir: String = "/tmp/poc-30"

    @Option(name: .long, help: "Pause between lines in seconds (default: 0.3).")
    var pause: Double = 0.3

    func run() throws {
        // Parse script
        let config: ScriptConfig?
        if let sc = scriptConfig {
            config = try ScriptConfig.load(from: sc)
        } else {
            let inputDir = URL(fileURLWithPath: input).deletingLastPathComponent().path
            var found: ScriptConfig?
            for name in ["script.yaml", "yapper.yaml"] {
                let path = "\(inputDir)/\(name)"
                if FileManager.default.fileExists(atPath: path) {
                    found = try ScriptConfig.load(from: path)
                    break
                }
            }
            config = found
        }

        guard let script = try ScriptParser.parse(filePath: input, config: config) else {
            throw ValidationError("Could not parse \(input) as a script.")
        }
        guard !script.scenes.isEmpty else {
            throw ValidationError("Script has no scenes.")
        }

        let sceneIdx = (scene ?? 1) - 1
        guard sceneIdx >= 0 && sceneIdx < script.scenes.count else {
            throw ValidationError("Scene \(sceneIdx + 1) out of range (1..\(script.scenes.count)).")
        }
        let targetScene = script.scenes[sceneIdx]

        // Set up engine and voices
        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )
        let (charVoices, narrator) = VoiceAssigner.assign(
            characters: script.characters,
            config: config,
            registry: engine.voiceRegistry,
            narratorVoiceName: config?.narratorVoice
        )

        try FileManager.default.createDirectory(
            atPath: outputDir, withIntermediateDirectories: true
        )

        fputs("Scene: \(targetScene.title)\n", stderr)
        fputs("Entries: \(targetScene.entries.count)\n", stderr)
        fputs("Cast: \(script.characters.map { "\($0)=\(charVoices[$0]?.name ?? "?")" }.joined(separator: ", "))\n\n", stderr)

        // Build dialogue entries: (text, voiceName, speaker)
        struct DialogueLine {
            let text: String
            let voiceName: String
            let speaker: String
        }

        let terminators: Set<Character> = [".", "!", "?", ";", ":", "\u{2014}"]
        var dialogueLines: [DialogueLine] = []

        for entry in targetScene.entries {
            switch entry.type {
            case .dialogue(let char):
                guard let v = charVoices[char] else { continue }
                dialogueLines.append(DialogueLine(
                    text: entry.text, voiceName: v.name, speaker: char
                ))
            case .stageDirection, .transition:
                // Skip stage directions and transitions for this POC
                continue
            }
        }

        guard !dialogueLines.isEmpty else {
            throw ValidationError("No dialogue lines in scene \(sceneIdx + 1).")
        }

        // Build the concatenated dialogue string (periods where no punctuation)
        let concatenated = dialogueLines.map { line in
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if let last = trimmed.last, terminators.contains(last) {
                return trimmed
            }
            return trimmed + "."
        }.joined(separator: " ")

        fputs("Concatenated (\(concatenated.count) chars):\n  \(concatenated.prefix(120))...\n\n", stderr)

        // Identify unique voices
        let uniqueVoices = Array(Set(dialogueLines.map(\.voiceName))).sorted()
        fputs("Unique voices: \(uniqueVoices.joined(separator: ", "))\n\n", stderr)

        // Word count per line (for timestamp splitting)
        let wordCounts = dialogueLines.map { $0.text.split(separator: " ").count }

        // Synthesise the full dialogue in each voice and collect timestamps
        struct VoiceSynthesis {
            let samples: [Float]
            let timestamps: [WordTimestamp]
            let sampleRate: Int
        }

        var syntheses: [String: VoiceSynthesis] = [:]

        for voiceName in uniqueVoices {
            guard let voice = engine.voiceRegistry.voices.first(where: { $0.name == voiceName }) else {
                fputs("  WARNING: voice \(voiceName) not found\n", stderr)
                continue
            }
            fputs("  Synthesising as \(voiceName)...", stderr)
            let start = CFAbsoluteTimeGetCurrent()
            let result = try engine.synthesize(text: concatenated, voice: voice, speed: speed)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let duration = Double(result.samples.count) / Double(result.sampleRate)
            fputs(" \(String(format: "%.2f", elapsed))s wall, \(String(format: "%.1f", duration))s audio, \(result.timestamps.count) words\n", stderr)

            syntheses[voiceName] = VoiceSynthesis(
                samples: result.samples,
                timestamps: result.timestamps,
                sampleRate: result.sampleRate
            )

            // Write the full voice rendering for reference
            let fullPath = URL(fileURLWithPath: outputDir)
                .appendingPathComponent("full_\(voiceName).wav")
            try writeWav(samples: result.samples, sampleRate: result.sampleRate, to: fullPath)
        }

        // Map each line to a timestamp range in each voice's synthesis
        fputs("\nSplicing:\n", stderr)
        let pauseSamples = [Float](repeating: 0, count: Int(pause * 24000))
        var spliced: [Float] = []

        for (i, line) in dialogueLines.enumerated() {
            guard let synth = syntheses[line.voiceName] else {
                fputs("  [\(i)] SKIP — no synthesis for \(line.voiceName)\n", stderr)
                continue
            }

            // Find the word range for this line
            let startWord = wordCounts.prefix(i).reduce(0, +)
            let endWord = startWord + wordCounts[i]

            guard startWord < synth.timestamps.count else {
                fputs("  [\(i)] SKIP — timestamp out of range (\(startWord) >= \(synth.timestamps.count))\n", stderr)
                continue
            }
            let clampedEnd = min(endWord, synth.timestamps.count)

            let startTime = synth.timestamps[startWord].startTime
            let endTime = synth.timestamps[clampedEnd - 1].endTime

            let startSample = max(0, Int(startTime * Double(synth.sampleRate)))
            let endSample = min(synth.samples.count, Int(endTime * Double(synth.sampleRate)))

            guard startSample < endSample else {
                fputs("  [\(i)] SKIP — invalid sample range\n", stderr)
                continue
            }

            let segment = Array(synth.samples[startSample..<endSample])
            let segDur = Double(segment.count) / Double(synth.sampleRate)

            fputs("  [\(i)] \(line.speaker) (\(line.voiceName)): \(String(format: "%.0f", startTime * 1000))-\(String(format: "%.0f", endTime * 1000))ms (\(String(format: "%.2f", segDur))s) — \(line.text)\n", stderr)

            if !spliced.isEmpty {
                spliced.append(contentsOf: pauseSamples)
            }
            spliced.append(contentsOf: segment)
        }

        // Write Mode B output
        let modeBPath = URL(fileURLWithPath: outputDir).appendingPathComponent("mode_b.wav")
        try writeWav(samples: spliced, sampleRate: 24000, to: modeBPath)
        let modeBDur = Double(spliced.count) / 24000.0
        fputs("\nMode B output: \(modeBPath.path) (\(String(format: "%.1f", modeBDur))s)\n", stderr)

        // Summary
        fputs("\n=== Files ===\n", stderr)
        fputs("  mode_b.wav — contextual spliced output\n", stderr)
        for v in uniqueVoices {
            fputs("  full_\(v).wav — full dialogue in \(v)\n", stderr)
        }
        fputs("\nRun Mode A separately:\n", stderr)
        fputs("  yapper convert \(input) --script-config <config> -o \(outputDir)/mode_a.m4b\n", stderr)
        fputs("  ffmpeg -i \(outputDir)/mode_a.m4b -c:a pcm_s16le \(outputDir)/mode_a.wav\n", stderr)
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
