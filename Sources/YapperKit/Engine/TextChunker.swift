// ABOUTME: Splits long text into chunks within the 510-token budget.
// ABOUTME: Uses NLTokenizer for sentence boundary detection.

import Foundation
import NaturalLanguage

/// A chunk of text sized to fit within Kokoro's 510-token limit.
public struct TextChunk: Sendable {
    /// The text content of this chunk.
    public let text: String
    /// Estimated phoneme token count for this chunk.
    public let estimatedTokenCount: Int
}

/// Splits text into chunks at sentence boundaries, each fitting within
/// the Kokoro model's 510 phoneme token limit.
public class TextChunker {
    /// Conservative estimate: ~3 phoneme tokens per character on average.
    /// This is intentionally conservative to avoid exceeding the limit.
    private let tokensPerChar: Double = 2.5
    private let maxTokens: Int = 510

    public init() {}

    /// Split text into chunks that fit within the 510-token budget.
    ///
    /// - Parameter text: Input text of any length.
    /// - Returns: Array of TextChunks, each within the token limit.
    public func chunk(_ text: String) -> [TextChunk] {
        let sentences = splitSentences(text)

        guard !sentences.isEmpty else {
            return []
        }

        var chunks: [TextChunk] = []
        var currentSentences: [String] = []
        var currentTokenEstimate = 0

        for sentence in sentences {
            let sentenceTokens = estimateTokens(sentence)

            // If a single sentence exceeds the limit, split at clause boundaries
            if sentenceTokens > maxTokens {
                // Flush current accumulator first
                if !currentSentences.isEmpty {
                    let chunkText = currentSentences.joined(separator: " ")
                    chunks.append(TextChunk(
                        text: chunkText,
                        estimatedTokenCount: estimateTokens(chunkText)
                    ))
                    currentSentences = []
                    currentTokenEstimate = 0
                }
                // Split the oversized sentence at clause boundaries
                let subChunks = splitAtClauseBoundaries(sentence)
                chunks.append(contentsOf: subChunks)
                continue
            }

            // Would adding this sentence exceed the limit?
            if currentTokenEstimate + sentenceTokens > maxTokens && !currentSentences.isEmpty {
                let chunkText = currentSentences.joined(separator: " ")
                chunks.append(TextChunk(
                    text: chunkText,
                    estimatedTokenCount: estimateTokens(chunkText)
                ))
                currentSentences = []
                currentTokenEstimate = 0
            }

            currentSentences.append(sentence)
            currentTokenEstimate += sentenceTokens
        }

        // Flush remaining
        if !currentSentences.isEmpty {
            let chunkText = currentSentences.joined(separator: " ")
            chunks.append(TextChunk(
                text: chunkText,
                estimatedTokenCount: estimateTokens(chunkText)
            ))
        }

        return chunks
    }

    /// Split text into sentences using NLTokenizer.
    private func splitSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return sentences
    }

    /// Split an oversized sentence at clause boundaries (commas, semicolons).
    private func splitAtClauseBoundaries(_ sentence: String) -> [TextChunk] {
        let delimiters = CharacterSet(charactersIn: ",;:")
        let parts = sentence.components(separatedBy: delimiters)

        var chunks: [TextChunk] = []
        var current: [String] = []
        var currentTokens = 0

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let partTokens = estimateTokens(trimmed)

            if currentTokens + partTokens > maxTokens && !current.isEmpty {
                let text = current.joined(separator: ", ")
                chunks.append(TextChunk(text: text, estimatedTokenCount: estimateTokens(text)))
                current = []
                currentTokens = 0
            }
            current.append(trimmed)
            currentTokens += partTokens
        }

        if !current.isEmpty {
            let text = current.joined(separator: ", ")
            chunks.append(TextChunk(text: text, estimatedTokenCount: estimateTokens(text)))
        }

        return chunks
    }

    /// Estimate phoneme token count from text length.
    private func estimateTokens(_ text: String) -> Int {
        Int(Double(text.count) * tokensPerChar)
    }
}
