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

    enum CodingKeys: String, CodingKey {
        case title, author
        case autoAssignVoices = "auto-assign-voices"
        case readStageDirections = "read-stage-directions"
        case narratorVoice = "narrator-voice"
        case characterVoices = "character-voices"
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
