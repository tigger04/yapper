// ABOUTME: Tests for VoiceRegistry enumeration and filtering.
// ABOUTME: Covers RT-1.7 through RT-1.10.

import Testing
import Foundation
@testable import YapperKit

@Suite(.serialized)
struct VoiceRegistryTests {

    private static let voicesPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/voices")

    // RT-1.7: Registry lists all Kokoro voices with name, accent, and gender
    @Test("RT-1.7: Registry lists voices with metadata")
    func test_registry_lists_voices_with_metadata_RT1_7() throws {
        let registry = try VoiceRegistry(voicesPath: Self.voicesPath)
        let voices = registry.voices

        #expect(!voices.isEmpty)
        for voice in voices {
            #expect(!voice.name.isEmpty)
        }
    }

    // RT-1.8: Filtering by accent returns only matching voices
    @Test("RT-1.8: Filter by accent returns only matching voices")
    func test_registry_filter_by_accent_RT1_8() throws {
        let registry = try VoiceRegistry(voicesPath: Self.voicesPath)
        let american = registry.list(filter: VoiceFilter(accent: .american))

        #expect(!american.isEmpty)
        for voice in american {
            #expect(voice.accent == .american)
        }

        let british = registry.list(filter: VoiceFilter(accent: .british))
        #expect(!british.isEmpty)
        for voice in british {
            #expect(voice.accent == .british)
        }
    }

    // RT-1.9: Filtering by accent and gender returns only matching voices
    @Test("RT-1.9: Filter by accent and gender returns only matching voices")
    func test_registry_filter_by_accent_and_gender_RT1_9() throws {
        let registry = try VoiceRegistry(voicesPath: Self.voicesPath)
        let britishFemale = registry.list(
            filter: VoiceFilter(accent: .british, gender: .female)
        )

        #expect(!britishFemale.isEmpty)
        for voice in britishFemale {
            #expect(voice.accent == .british)
            #expect(voice.gender == .female)
            #expect(voice.name.hasPrefix("bf_"))
        }
    }

    // RT-1.10: Empty filter returns all voices
    @Test("RT-1.10: Nil filter returns all voices")
    func test_registry_nil_filter_returns_all_RT1_10() throws {
        let registry = try VoiceRegistry(voicesPath: Self.voicesPath)
        let all = registry.list(filter: nil)
        #expect(all.count == registry.voices.count)
    }
}
