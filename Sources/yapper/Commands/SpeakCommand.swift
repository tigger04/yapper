// ABOUTME: CLI command for live TTS playback through system speakers.
// ABOUTME: Reads text from argument or stdin, synthesises and plays audio via per-chunk streaming.

import ArgumentParser
import AVFoundation
import Foundation
import YapperKit

// Global state for SIGINT handling in the streaming playback path.
// Must be global because C signal handlers cannot capture Swift context.
private nonisolated(unsafe) var speakInterrupted = false
private nonisolated(unsafe) var speakCurrentAfplay: Process?
private nonisolated(unsafe) var speakPid: Int32 = 0

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

    @Flag(name: .shortAndLong, help: "Suppress progress output.")
    var quiet: Bool = false

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

        // Look-ahead synthesis: synthesise chunk N+1 while chunk N plays.
        // Eliminates the audible gaps between chunks that occurred when synthesis
        // and playback were sequential.
        speakPid = ProcessInfo.processInfo.processIdentifier
        speakInterrupted = false
        speakCurrentAfplay = nil
        let tmpDir = FileManager.default.temporaryDirectory

        // Pre-chunk for progress reporter and look-ahead coordination
        let chunker = TextChunker()
        let chunks = chunker.chunk(inputText)
        var reporter = ProgressReporter(totalChunks: chunks.count, quiet: quiet)

        signal(SIGINT) { _ in
            speakInterrupted = true
            speakCurrentAfplay?.interrupt()
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(atPath: NSTemporaryDirectory()) {
                for file in files where file.hasPrefix("yapper_speak_\(speakPid)") {
                    try? fm.removeItem(atPath: NSTemporaryDirectory() + file)
                }
            }
            _exit(130)
        }

        // For single-chunk input, no look-ahead needed — synthesise and play directly
        if chunks.count <= 1 {
            try engine.stream(text: inputText, voice: selectedVoice, speed: speed) { chunk in
                guard !speakInterrupted else { return }
                reporter.update(chunkText: chunks.first?.text ?? "")
                let tmpPath = tmpDir.appendingPathComponent("yapper_speak_\(speakPid)_1.wav")
                do {
                    try writeWav(samples: chunk.samples, sampleRate: 24000, to: tmpPath)
                    let afplay = Process()
                    afplay.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                    afplay.arguments = [tmpPath.path]
                    afplay.standardInput = FileHandle.nullDevice
                    speakCurrentAfplay = afplay
                    try afplay.run()
                    afplay.waitUntilExit()
                    speakCurrentAfplay = nil
                    try? FileManager.default.removeItem(at: tmpPath)
                } catch {
                    try? FileManager.default.removeItem(at: tmpPath)
                }
            }
        } else {
            // Multi-chunk: producer-consumer with look-ahead of 1.
            // Synthesis thread calls engine.stream() which produces chunks sequentially.
            // Each chunk's WAV is handed to the main thread for playback.
            // While the main thread plays chunk N, the synthesis thread is already
            // producing chunk N+1.
            nonisolated(unsafe) var synthesisError: Error? = nil
            nonisolated(unsafe) var chunkIndex = 0
            nonisolated(unsafe) var reporterCopy = reporter

            // Synchronisation: ready = "a WAV is available", consumed = "playback took it"
            let readySemaphore = DispatchSemaphore(value: 0)
            let consumedSemaphore = DispatchSemaphore(value: 1)
            nonisolated(unsafe) var nextWavPath: URL?

            let synthQueue = DispatchQueue(label: "yapper.speak.synthesis")
            nonisolated(unsafe) let engineRef = engine
            let voiceRef = selectedVoice
            let speedVal = speed
            let inputRef = inputText
            let chunksRef = chunks
            synthQueue.async {
                do {
                    var isFirstChunk = true
                    try engineRef.stream(text: inputRef, voice: voiceRef, speed: speedVal) { chunk in
                        guard !speakInterrupted else { return }

                        chunkIndex += 1
                        let chunkText = chunkIndex <= chunksRef.count ? chunksRef[chunkIndex - 1].text : ""
                        // Update progress at synthesis-start
                        reporterCopy.update(chunkText: chunkText)

                        let wavPath = tmpDir.appendingPathComponent(
                            "yapper_speak_\(speakPid)_\(chunkIndex).wav")
                        do {
                            try self.writeWav(samples: chunk.samples, sampleRate: 24000, to: wavPath)

                            if isFirstChunk {
                                // First chunk: no previous chunk to wait for
                                isFirstChunk = false
                                nextWavPath = wavPath
                                readySemaphore.signal()
                            } else {
                                // Wait for consumer to take the previous chunk, then offer this one
                                consumedSemaphore.wait()
                                nextWavPath = wavPath
                                readySemaphore.signal()
                            }
                        } catch {
                            synthesisError = error
                            readySemaphore.signal()
                        }
                    }
                } catch {
                    synthesisError = error
                }

                // Signal end-of-stream
                consumedSemaphore.wait()
                nextWavPath = nil
                readySemaphore.signal()
            }

            // Main thread: play WAV files as they become available
            while !speakInterrupted {
                readySemaphore.wait()
                guard let wavPath = nextWavPath else {
                    consumedSemaphore.signal()
                    break
                }

                do {
                    let afplay = Process()
                    afplay.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                    afplay.arguments = [wavPath.path]
                    afplay.standardInput = FileHandle.nullDevice
                    speakCurrentAfplay = afplay

                    // Release producer to start next chunk while this one plays
                    consumedSemaphore.signal()

                    try afplay.run()
                    afplay.waitUntilExit()

                    speakCurrentAfplay = nil
                    try? FileManager.default.removeItem(at: wavPath)
                } catch {
                    consumedSemaphore.signal()
                    try? FileManager.default.removeItem(at: wavPath)
                    break
                }
            }

            if let error = synthesisError {
                throw error
            }
        }

        reporter.finish(summary: "")

        // Final cleanup — remove any lingering temp files for this PID
        let pid = speakPid
        if let files = try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path) {
            for file in files where file.hasPrefix("yapper_speak_\(pid)") {
                try? FileManager.default.removeItem(at: tmpDir.appendingPathComponent(file))
            }
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
