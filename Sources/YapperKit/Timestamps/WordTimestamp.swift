// ABOUTME: Word-level timestamp data for synthesised audio.
// ABOUTME: Maps words to their start/end times in the audio stream.

import Foundation

/// A word's time position within synthesised audio.
public struct WordTimestamp: Sendable, Equatable {
    /// The word text.
    public let word: String
    /// Start time in seconds from the beginning of the audio.
    public let startTime: Double
    /// End time in seconds from the beginning of the audio.
    public let endTime: Double

    public init(word: String, startTime: Double, endTime: Double) {
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
    }
}
