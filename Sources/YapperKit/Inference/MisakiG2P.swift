// ABOUTME: Wraps MisakiSwift's EnglishG2P for grapheme-to-phoneme conversion.
// ABOUTME: Converts text to phoneme strings and MToken arrays for the Kokoro pipeline.

import Foundation
import MisakiSwift
import MLXUtilsLibrary

/// Wrapper around MisakiSwift's EnglishG2P that handles language initialisation
/// and provides a simplified interface for the Kokoro pipeline.
///
/// The G2P output is a phoneme string (IPA-like notation) plus an array of
/// MToken objects that carry word boundaries needed for timestamp prediction.
class MisakiG2P {
    private var g2p: EnglishG2P?
    private var currentAccent: Accent?

    /// Initialise or re-initialise the G2P engine for the given accent.
    ///
    /// Caches the engine so repeated calls with the same accent are free.
    func configure(accent: Accent) {
        guard accent != currentAccent else { return }
        let british = (accent == .british)
        g2p = EnglishG2P(british: british)
        currentAccent = accent
    }

    /// Convert text to phonemes.
    ///
    /// - Parameter text: Input text string
    /// - Returns: Tuple of (phoneme string, MToken array for timestamp alignment)
    /// - Throws: `YapperError.synthesisError` if the G2P engine is not configured
    func phonemise(_ text: String) throws -> (String, [MToken]) {
        guard let g2p else {
            throw YapperError.synthesisError(
                message: "G2P engine not configured — call configure(accent:) first"
            )
        }
        let (phonemes, tokens) = g2p.phonemize(text: text)
        return (phonemes, tokens)
    }
}
