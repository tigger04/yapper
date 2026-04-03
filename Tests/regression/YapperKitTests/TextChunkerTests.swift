// ABOUTME: Tests for TextChunker sentence-boundary splitting.
// ABOUTME: Covers RT-2.9 through RT-2.12.

import Testing
import Foundation
@testable import YapperKit

// RT-2.9: Text within 510 tokens is returned as a single chunk
@Test("RT-2.9: Short text returns single chunk")
func test_short_text_single_chunk_RT2_9() throws {
    let chunker = TextChunker()
    let chunks = chunker.chunk("Hello, this is a short sentence.")
    #expect(chunks.count == 1)
    #expect(chunks[0].text == "Hello, this is a short sentence.")
}

// RT-2.10: Text exceeding 510 tokens is split into multiple chunks
@Test("RT-2.10: Long text splits into multiple chunks")
func test_long_text_multiple_chunks_RT2_10() throws {
    let chunker = TextChunker()
    // Generate text with many sentences to exceed 510 phoneme tokens
    let sentences = (1...50).map { "This is sentence number \($0) with enough words to accumulate tokens." }
    let longText = sentences.joined(separator: " ")
    let chunks = chunker.chunk(longText)
    #expect(chunks.count > 1)
    // Reconstructed text should match original
    let reconstructed = chunks.map(\.text).joined(separator: " ")
    #expect(reconstructed == longText)
}

// RT-2.11: Every chunk is at or below the 510-token limit
@Test("RT-2.11: All chunks within token limit")
func test_chunks_within_token_limit_RT2_11() throws {
    let chunker = TextChunker()
    let sentences = (1...50).map { "This is sentence number \($0) with enough words to accumulate tokens." }
    let longText = sentences.joined(separator: " ")
    let chunks = chunker.chunk(longText)
    for chunk in chunks {
        #expect(chunk.estimatedTokenCount <= 510)
    }
}

// RT-2.12: Chunks split only at sentence boundaries
@Test("RT-2.12: Chunks split at sentence boundaries")
func test_chunks_split_at_sentence_boundaries_RT2_12() throws {
    let chunker = TextChunker()
    let text = "First sentence. Second sentence. Third sentence. Fourth sentence."
    let chunks = chunker.chunk(text)
    // Each chunk should end with a complete sentence (period + space or end of text)
    for chunk in chunks {
        let trimmed = chunk.text.trimmingCharacters(in: .whitespaces)
        #expect(trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?"))
    }
}
