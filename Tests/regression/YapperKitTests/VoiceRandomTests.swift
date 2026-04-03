// ABOUTME: Tests for VoiceRegistry random voice selection.
// ABOUTME: Covers RT-1.11 through RT-1.13.

import Testing
import Foundation
@testable import YapperKit

@Suite(.serialized)
struct VoiceRandomTests {

    private static let voicesPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/voices")

    // RT-1.11: Random selection returns a valid voice from the registry
    @Test("RT-1.11: Random selection returns a valid voice")
    func test_random_returns_valid_voice_RT1_11() throws {
        let registry = try VoiceRegistry(voicesPath: Self.voicesPath)
        let voice = registry.random()
        #expect(voice != nil)
        #expect(registry.voices.contains(voice!))
    }

    // RT-1.12: Random selection with filter returns only voices matching the filter
    @Test("RT-1.12: Random with filter returns matching voice")
    func test_random_with_filter_returns_matching_RT1_12() throws {
        let registry = try VoiceRegistry(voicesPath: Self.voicesPath)
        let filter = VoiceFilter(accent: .british)
        let voice = registry.random(filter: filter)

        #expect(voice != nil)
        #expect(voice!.accent == .british)
    }

    // RT-1.13: Random selection with the same seed produces the same voice
    @Test("RT-1.13: Same seed produces same voice")
    func test_random_deterministic_with_seed_RT1_13() throws {
        let registry = try VoiceRegistry(voicesPath: Self.voicesPath)
        let seed: UInt64 = 42

        let first = registry.random(seed: seed)
        let second = registry.random(seed: seed)

        #expect(first != nil)
        #expect(first == second)
    }
}
