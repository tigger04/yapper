// ABOUTME: Voice model and related types for Kokoro TTS voices.
// ABOUTME: Defines Voice, Accent, Gender, and VoiceFilter.

import Foundation

/// Accent classification for Kokoro voices.
public enum Accent: String, CaseIterable, Sendable {
    case american = "a"
    case british = "b"
}

/// Gender classification for Kokoro voices.
public enum Gender: String, CaseIterable, Sendable {
    case female = "f"
    case male = "m"
}

/// A Kokoro TTS voice with its metadata.
public struct Voice: Sendable, Equatable {
    /// Voice identifier, e.g. "af_heart"
    public let name: String
    /// Accent derived from name prefix
    public let accent: Accent
    /// Gender derived from name prefix
    public let gender: Gender

    /// Parse a voice from its name string.
    /// Name format: {accent}{gender}_{identifier}, e.g. "af_heart", "bm_daniel"
    public init?(name: String) {
        guard name.count >= 3,
              let accentChar = name.first,
              let accent = Accent(rawValue: String(accentChar)),
              let genderChar = name.dropFirst().first,
              let gender = Gender(rawValue: String(genderChar)) else {
            return nil
        }
        self.name = name
        self.accent = accent
        self.gender = gender
    }
}

/// Filter criteria for voice selection.
public struct VoiceFilter: Sendable {
    public let accent: Accent?
    public let gender: Gender?

    public init(accent: Accent? = nil, gender: Gender? = nil) {
        self.accent = accent
        self.gender = gender
    }

    /// Returns true if the voice matches this filter's criteria.
    public func matches(_ voice: Voice) -> Bool {
        if let accent, voice.accent != accent { return false }
        if let gender, voice.gender != gender { return false }
        return true
    }
}
