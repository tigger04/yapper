// ABOUTME: Parses play/screenplay scripts into structured dialogue and stage directions.
// ABOUTME: Supports markdown and org-mode formats with character detection and scene boundaries.

import Foundation
import YapperKit

/// A single entry in a parsed script — either dialogue or a stage direction.
struct ScriptEntry {
    enum EntryType {
        case dialogue(character: String)
        case stageDirection
    }
    let type: EntryType
    let text: String
}

/// A scene in a parsed script, containing a title and a sequence of entries.
struct ScriptScene {
    let title: String
    var entries: [ScriptEntry]
}

/// The fully parsed script structure.
struct ScriptDocument {
    var title: String?
    var author: String?
    var characters: [String]
    var scenes: [ScriptScene]
}

/// Detects whether a file contains script patterns and parses accordingly.
struct ScriptParser {

    /// Attempt to parse a file as a script. Returns nil if no script patterns found.
    static func parse(filePath: String, config: ScriptConfig?) throws -> ScriptDocument? {
        let knownChars: Set<String>
        if let keys = config?.characterVoices?.keys {
            knownChars = Set(keys.map { $0.uppercased() })
        } else {
            knownChars = []
        }
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        switch ext {
        case "org":
            return parseOrg(content: content, config: config, knownCharacters: knownChars)
        case "md", "markdown":
            return parseMd(content: content, config: config, knownCharacters: knownChars)
        default:
            return nil
        }
    }

    // MARK: - Markdown parser

    /// Parse markdown-format script.
    /// `**CHARACTER:**` at line start = dialogue.
    /// `*italic text*` at line start = stage direction.
    /// `### Scene Title` = scene boundary.
    private static func parseMd(content: String, config: ScriptConfig?, knownCharacters: Set<String>) -> ScriptDocument? {
        let lines = content.components(separatedBy: "\n")

        // Check for script patterns in first 100 lines.
        // Match **ANYTHING:** where the content starts with an ALL-CAPS word.
        // Handles: **BOB:**, **BOB softly:**, **BOB (softly):**, **BOB, firmly:**
        let sample = lines.prefix(100).joined(separator: "\n")
        let dialoguePattern = try? NSRegularExpression(pattern: #"^\*\*[A-Z\u00C0-\u024F][^*]*:?\*\*"#, options: .anchorsMatchLines)
        let sampleRange = NSRange(sample.startIndex..., in: sample)
        let matchCount = dialoguePattern?.numberOfMatches(in: sample, range: sampleRange) ?? 0
        if matchCount < 2 {
            return nil // Not a script
        }

        var title: String?
        var author: String?
        var scenes: [ScriptScene] = []
        var currentScene = ScriptScene(title: "Untitled", entries: [])
        var currentCharacter: String?
        var dialogueLines: [String] = []
        var characters = Set<String>()
        var sceneStarted = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Extract metadata
            if trimmed.hasPrefix("# ") && title == nil {
                title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.hasPrefix("*by ") && trimmed.hasSuffix("*") && author == nil {
                author = String(trimmed.dropFirst(4).dropLast(1)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Scene boundary: ### heading
            if trimmed.hasPrefix("### ") {
                // Flush current dialogue
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                if sceneStarted {
                    scenes.append(currentScene)
                }
                let sceneTitle = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentScene = ScriptScene(title: sceneTitle, entries: [])
                sceneStarted = true
                continue
            }

            // Skip ## headings (act markers)
            if trimmed.hasPrefix("## ") || trimmed.hasPrefix("# ") {
                continue
            }

            // Stage direction: *italic text* (single asterisks, full line)
            if trimmed.hasPrefix("*") && !trimmed.hasPrefix("**") && trimmed.hasSuffix("*") && trimmed.count > 2 {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                let stageText = String(trimmed.dropFirst(1).dropLast(1)).trimmingCharacters(in: .whitespaces)
                if !stageText.isEmpty {
                    currentScene.entries.append(ScriptEntry(type: .stageDirection, text: stageText))
                }
                continue
            }

            // Dialogue attribution: **CHARACTER:** or **CHARACTER (notes):**
            if trimmed.hasPrefix("**") {
                if let endBold = trimmed.range(of: "**", range: trimmed.index(trimmed.startIndex, offsetBy: 2)..<trimmed.endIndex) {
                    flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                    var charRaw = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<endBold.lowerBound])
                    // Remove trailing colon
                    if charRaw.hasSuffix(":") { charRaw = String(charRaw.dropLast()) }
                    let charName = extractCharacterName(charRaw, knownCharacters: knownCharacters)
                    if !charName.isEmpty {
                        currentCharacter = charName
                    }
                    continue
                }
            }

            // Dialogue text (continuation of current character)
            if currentCharacter != nil && !trimmed.isEmpty {
                dialogueLines.append(trimmed)
            }
        }

        // Flush remaining
        flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
        if sceneStarted {
            scenes.append(currentScene)
        }

        // If no scenes were found but there are entries, wrap in a single scene
        if scenes.isEmpty && !currentScene.entries.isEmpty {
            scenes.append(currentScene)
        }

        guard !scenes.isEmpty else { return nil }

        return ScriptDocument(
            title: config?.title ?? title,
            author: config?.author ?? author,
            characters: Array(characters).sorted(),
            scenes: scenes
        )
    }

    // MARK: - Org-mode parser

    /// Parse org-mode-format script.
    /// `***` (L3 heading) = stage direction.
    /// `****` (L4 heading) = dialogue attribution.
    /// Body text below L4 = dialogue.
    private static func parseOrg(content: String, config: ScriptConfig?, knownCharacters: Set<String>) -> ScriptDocument? {
        let lines = content.components(separatedBy: "\n")

        var title: String?
        var author: String?
        var scenes: [ScriptScene] = []
        var currentScene = ScriptScene(title: "Untitled", entries: [])
        var currentCharacter: String?
        var dialogueLines: [String] = []
        var characters = Set<String>()
        var sceneStarted = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Extract org metadata
            if trimmed.hasPrefix("#+TITLE:") && title == nil {
                title = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.hasPrefix("#+AUTHOR:") && author == nil {
                author = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Scene boundary: ** heading (L2)
            if trimmed.hasPrefix("** ") && !trimmed.hasPrefix("*** ") {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                if sceneStarted {
                    scenes.append(currentScene)
                }
                let sceneTitle = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentScene = ScriptScene(title: sceneTitle, entries: [])
                sceneStarted = true
                continue
            }

            // Dialogue attribution: **** CHARACTER or **** CHARACTER (notes)
            if trimmed.hasPrefix("**** ") {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                let charRaw = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                let charName = extractCharacterName(charRaw, knownCharacters: knownCharacters)
                if !charName.isEmpty {
                    currentCharacter = charName
                }
                continue
            }

            // Stage direction: *** heading (L3)
            if trimmed.hasPrefix("*** ") {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                let stageText = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if !stageText.isEmpty {
                    currentScene.entries.append(ScriptEntry(type: .stageDirection, text: stageText))
                }
                continue
            }

            // Skip * headings (act/top-level markers)
            if trimmed.hasPrefix("* ") || trimmed.hasPrefix("#+") {
                continue
            }

            // Skip table rows and empty lines in header area
            if trimmed.hasPrefix("|") || trimmed.isEmpty {
                if currentCharacter == nil { continue }
            }

            // Dialogue text (continuation of current character)
            if currentCharacter != nil && !trimmed.isEmpty {
                dialogueLines.append(trimmed)
            }
        }

        // Flush remaining
        flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
        if sceneStarted {
            scenes.append(currentScene)
        }

        if scenes.isEmpty && !currentScene.entries.isEmpty {
            scenes.append(currentScene)
        }

        guard !scenes.isEmpty else { return nil }

        return ScriptDocument(
            title: config?.title ?? title,
            author: config?.author ?? author,
            characters: Array(characters).sorted(),
            scenes: scenes
        )
    }

    // MARK: - Character name extraction

    /// Extract the character name from an attribution line, stripping acting
    /// directions. ALL-CAPS words are character name, first non-caps word
    /// starts the direction which is discarded.
    ///
    /// Examples:
    ///   `KEVIN` → KEVIN
    ///   `KEVIN softly` → KEVIN
    ///   `KEVIN, softly` → KEVIN
    ///   `KEVIN (softly)` → KEVIN
    ///   `KEVIN, (softly)` → KEVIN
    ///   `KEVIN Softly` → KEVIN
    ///   `GDA CONLON` → GDA CONLON (multi-word, all caps)
    ///   `CÁIT gives him a look.` → CÁIT
    ///   `KEVIN offstage, sounding closer` → KEVIN
    private static func extractCharacterName(
        _ raw: String,
        knownCharacters: Set<String>
    ) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)

        // Strip parenthesised content
        if let parenStart = text.firstIndex(of: "(") {
            text = String(text[..<parenStart]).trimmingCharacters(in: .whitespaces)
        }

        // Strip trailing comma and everything after
        if let commaIdx = text.firstIndex(of: ",") {
            text = String(text[..<commaIdx]).trimmingCharacters(in: .whitespaces)
        }

        // Take only leading ALL-CAPS words. A word is ALL-CAPS if every letter
        // in it is uppercase (handles accented characters like CÁIT).
        // Stop at the first word that contains any lowercase letter.
        let words = text.components(separatedBy: .whitespaces)
        var nameWords: [String] = []
        for word in words {
            guard !word.isEmpty else { continue }
            let letters = word.filter { $0.isLetter }
            if letters.isEmpty {
                // Punctuation-only token — skip
                continue
            }
            let allUpper = letters.allSatisfy { $0.isUppercase }
            if allUpper {
                nameWords.append(word)
            } else {
                break
            }
        }

        let name = nameWords.joined(separator: " ")
        return name.isEmpty ? text : name
    }

    // MARK: - Helpers

    private static func flushDialogue(
        _ character: inout String?,
        _ lines: inout [String],
        _ scene: inout ScriptScene,
        _ characters: inout Set<String>
    ) {
        guard let char = character, !lines.isEmpty else {
            character = nil
            lines.removeAll()
            return
        }
        characters.insert(char)
        let text = lines.joined(separator: " ")
        scene.entries.append(ScriptEntry(type: .dialogue(character: char), text: text))
        character = nil
        lines.removeAll()
    }
}
