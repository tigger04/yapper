// ABOUTME: Data types for synthesis output — PCM audio with timestamps.
// ABOUTME: Used as return type from YapperEngine.synthesize().

import Foundation

/// Result of TTS synthesis: PCM audio samples with word-level timestamps.
public struct AudioResult: Sendable {
    /// Raw PCM audio samples, mono, at sampleRate Hz.
    public let samples: [Float]
    /// Sample rate in Hz (always 24000 for Kokoro).
    public let sampleRate: Int
    /// Word-level timestamps aligned to the audio.
    public let timestamps: [WordTimestamp]

    public init(samples: [Float], sampleRate: Int = 24000, timestamps: [WordTimestamp] = []) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.timestamps = timestamps
    }
}

/// A chunk of synthesised audio, used for streaming playback.
public struct AudioChunk: Sendable {
    /// PCM audio samples for this chunk.
    public let samples: [Float]
    /// Timestamps for words in this chunk.
    public let timestamps: [WordTimestamp]
    /// True if this is the last chunk.
    public let isLast: Bool
}
