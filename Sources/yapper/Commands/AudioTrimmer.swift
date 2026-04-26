// ABOUTME: Trims model-generated leading/trailing silence from synthesised audio.
// ABOUTME: Prefers Whisper word timestamps via `transcribe` CLI; falls back to heuristic offsets.

import AVFoundation
import Foundation

/// Trims leading and trailing silence from synthesised audio segments.
struct AudioTrimmer {

    /// Whether the `transcribe` CLI tool is available on this system.
    static let transcribeAvailable: Bool = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["command", "-v", "transcribe"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }()

    // Heuristic trim offsets derived from Kokoro output measurements.
    // Leading silence: ~280ms consistently. Trim 300ms (7200 samples at 24kHz).
    // Trailing silence: 0-80ms. Trim 100ms (2400 samples at 24kHz).
    private static let heuristicLeadSamples = 7200   // 300ms at 24kHz
    private static let heuristicTrailSamples = 2400   // 100ms at 24kHz

    /// Trim silence from a WAV file. Returns trimmed samples.
    ///
    /// Uses Whisper word timestamps when `transcribe` is available for exact
    /// trim points. Falls back to heuristic fixed-offset trimming otherwise.
    static func trim(wavPath: String) -> [Float] {
        let samples = readWavSamples(from: URL(fileURLWithPath: wavPath))
        guard !samples.isEmpty else { return samples }

        if transcribeAvailable {
            if let trimmed = trimWithWhisper(wavPath: wavPath, samples: samples) {
                return trimmed
            }
        }
        return trimHeuristic(samples: samples)
    }

    /// Trim using Whisper word-level timestamps from `transcribe`.
    private static func trimWithWhisper(wavPath: String, samples: [Float]) -> [Float]? {
        let jsonPath = wavPath + ".words.json"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["transcribe", "words", wavPath, "--output", jsonPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
        } catch {
            return nil
        }

        defer { try? FileManager.default.removeItem(atPath: jsonPath) }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transcription = json["transcription"] as? [[String: Any]] else {
            return nil
        }

        // Find earliest word start and latest word end across all segments
        var earliestStart: Double?
        var latestEnd: Double?

        for segment in transcription {
            guard let tokens = segment["tokens"] as? [[String: Any]] else { continue }
            for token in tokens {
                guard let text = token["text"] as? String,
                      !text.hasPrefix("["),
                      let offsets = token["offsets"] as? [String: Any],
                      let from = offsets["from"] as? Int,
                      let to = offsets["to"] as? Int else { continue }
                let startSec = Double(from) / 1000.0
                let endSec = Double(to) / 1000.0
                if earliestStart == nil || startSec < earliestStart! {
                    earliestStart = startSec
                }
                if latestEnd == nil || endSec > latestEnd! {
                    latestEnd = endSec
                }
            }
        }

        guard let start = earliestStart, let end = latestEnd else { return nil }

        let startSample = max(0, Int(start * 24000))
        let endSample = min(samples.count, Int(end * 24000))
        guard startSample < endSample else { return nil }

        return Array(samples[startSample..<endSample])
    }

    /// Trim using fixed heuristic offsets.
    private static func trimHeuristic(samples: [Float]) -> [Float] {
        let leadTrim = min(heuristicLeadSamples, samples.count / 2)
        let trailTrim = min(heuristicTrailSamples, samples.count / 2)
        let start = leadTrim
        let end = max(start, samples.count - trailTrim)
        return Array(samples[start..<end])
    }

    /// Read float32 samples from a WAV file.
    static func readWavSamples(from url: URL) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return []
        }
        do {
            try file.read(into: buffer)
        } catch {
            return []
        }
        guard let channelData = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
    }
}
