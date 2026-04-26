// ABOUTME: YAML configuration for script reading mode.
// ABOUTME: Defines ScriptConfig parsed from script.yaml alongside the input file.

import Foundation
import Yams

/// Configuration for script-reading mode, parsed from a YAML file.
struct ScriptConfig: Decodable {
    var title: String?
    var author: String?
    var autoAssignVoices: Bool?
    var readStageDirections: Bool?
    var narratorVoice: String?
    var characterVoices: [String: String]?

    // Issue #25: concurrent synthesis, gaps, speed
    var threads: Int?
    var gapAfterDialogue: Double?
    var gapAfterStageDirection: Double?
    var gapAfterScene: Double?
    var dialogueSpeed: Float?
    var stageDirectionSpeed: Float?

    // Issue #24: preamble, footnotes
    var renderIntro: Bool?
    var introVoice: String?
    var renderFootnotes: Bool?

    // Pronunciation substitutions: applied to text before synthesis
    var speechSubstitution: [String: String]?

    enum CodingKeys: String, CodingKey {
        case title, author, threads
        case autoAssignVoices = "auto-assign-voices"
        case readStageDirections = "read-stage-directions"
        case narratorVoice = "narrator-voice"
        case characterVoices = "character-voices"
        case gapAfterDialogue = "gap-after-dialogue"
        case gapAfterStageDirection = "gap-after-stage-direction"
        case gapAfterScene = "gap-after-scene"
        case dialogueSpeed = "dialogue-speed"
        case stageDirectionSpeed = "stage-direction-speed"
        case renderIntro = "render-intro"
        case introVoice = "intro-voice"
        case renderFootnotes = "render-footnotes"
        case speechSubstitution = "speech-substitution"
    }

    /// Load config from a YAML file path.
    static func load(from path: String) throws -> ScriptConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw ScriptError.invalidConfig(path: path, message: "File is not valid UTF-8")
        }
        do {
            return try YAMLDecoder().decode(ScriptConfig.self, from: yaml)
        } catch {
            throw ScriptError.invalidConfig(path: path, message: error.localizedDescription)
        }
    }
}

enum ScriptError: Error, CustomStringConvertible {
    case invalidConfig(path: String, message: String)
    case noScriptPatterns(path: String)

    var description: String {
        switch self {
        case .invalidConfig(let path, let message):
            return "Invalid script config at \(path): \(message)"
        case .noScriptPatterns(let path):
            return "No script patterns found in \(path) — treating as prose"
        }
    }
}
