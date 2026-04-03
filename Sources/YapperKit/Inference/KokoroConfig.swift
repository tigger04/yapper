// ABOUTME: Hardcoded model configuration constants for Kokoro-82M.
// ABOUTME: Eliminates the need for a bundled config.json file.

import Foundation

/// Model configuration for Kokoro-82M, matching the config.json shipped with the model.
///
/// All values are hardcoded from the canonical config rather than loaded at runtime,
/// since the model architecture is fixed at 82M parameters.
struct KokoroConfig {

    // MARK: - Top-level model parameters

    static let dimIn = 64
    static let hiddenDim = 512
    static let styleDim = 128
    static let nMels = 80
    static let nToken = 178
    static let nLayer = 3
    static let maxDur = 50
    static let textEncoderKernelSize = 5

    // MARK: - PLBERT (ALBERT) encoder parameters

    struct PLBert {
        static let hiddenSize = 768
        static let numAttentionHeads = 12
        static let intermediateSize = 2048
        static let maxPositionEmbeddings = 512
        static let numHiddenLayers = 12
        static let embeddingSize = 128
        static let innerGroupNum = 1
        static let numHiddenGroups = 1
        static let layerNormEps: Float = 1e-12
    }

    // MARK: - iSTFTNet decoder parameters

    struct ISTFTNet {
        static let upsampleKernelSizes = [20, 12]
        static let upsampleRates = [10, 6]
        static let genIstftHopSize = 5
        static let genIstftNFft = 20
        static let resblockDilationSizes = [[1, 3, 5], [1, 3, 5], [1, 3, 5]]
        static let resblockKernelSizes = [3, 7, 11]
        static let upsampleInitialChannel = 512
    }

    // MARK: - Phoneme vocabulary

    /// Maps phoneme characters to token IDs, matching the model's training vocabulary.
    static let vocab: [Character: Int] = [
        ";": 1, ":": 2, ",": 3, ".": 4, "!": 5, "?": 6,
        "\u{2014}": 9,   // em dash
        "\u{2026}": 10,  // ellipsis
        "\"": 11, "(": 12, ")": 13,
        "\u{201C}": 14,  // left double quotation mark
        "\u{201D}": 15,  // right double quotation mark
        " ": 16,
        "\u{0303}": 17,  // combining tilde
        "\u{02A3}": 18,  // dz
        "\u{02A5}": 19,  // dz with curl
        "\u{02A6}": 20,  // ts
        "\u{02A8}": 21,  // tc with curl
        "\u{1D5D}": 22,  // modifier letter small beta
        "\u{AB67}": 23,  // Latin small letter turned r with middle tilde
        "A": 24, "I": 25, "O": 31, "Q": 33, "S": 35, "T": 36,
        "W": 39, "Y": 41,
        "\u{1D4A}": 42,  // modifier letter small schwa
        "a": 43, "b": 44, "c": 45, "d": 46, "e": 47, "f": 48,
        "h": 50, "i": 51, "j": 52, "k": 53, "l": 54, "m": 55,
        "n": 56, "o": 57, "p": 58, "q": 59, "r": 60, "s": 61,
        "t": 62, "u": 63, "v": 64, "w": 65, "x": 66, "y": 67,
        "z": 68,
        "\u{0251}": 69,  // ɑ
        "\u{0250}": 70,  // ɐ
        "\u{0252}": 71,  // ɒ
        "\u{00E6}": 72,  // æ
        "\u{03B2}": 75,  // β
        "\u{0254}": 76,  // ɔ
        "\u{0255}": 77,  // ɕ
        "\u{00E7}": 78,  // ç
        "\u{0256}": 80,  // ɖ
        "\u{00F0}": 81,  // ð
        "\u{02A4}": 82,  // dʒ
        "\u{0259}": 83,  // ə
        "\u{025A}": 85,  // ɚ
        "\u{025B}": 86,  // ɛ
        "\u{025C}": 87,  // ɜ
        "\u{025F}": 90,  // ɟ
        "\u{0261}": 92,  // ɡ
        "\u{0265}": 99,  // ɥ
        "\u{0268}": 101, // ɨ
        "\u{026A}": 102, // ɪ
        "\u{029D}": 103, // ʝ
        "\u{026F}": 110, // ɯ
        "\u{0270}": 111, // ɰ
        "\u{014B}": 112, // ŋ
        "\u{0273}": 113, // ɳ
        "\u{0272}": 114, // ɲ
        "\u{0274}": 115, // ɴ
        "\u{00F8}": 116, // ø
        "\u{0278}": 118, // ɸ
        "\u{03B8}": 119, // θ
        "\u{0153}": 120, // œ
        "\u{0279}": 123, // ɹ
        "\u{027E}": 125, // ɾ
        "\u{027B}": 126, // ɻ
        "\u{0281}": 128, // ʁ
        "\u{027D}": 129, // ɽ
        "\u{0282}": 130, // ʂ
        "\u{0283}": 131, // ʃ
        "\u{0288}": 132, // ʈ
        "\u{02A7}": 133, // tʃ
        "\u{028A}": 135, // ʊ
        "\u{028B}": 136, // ʋ
        "\u{028C}": 138, // ʌ
        "\u{0263}": 139, // ɣ
        "\u{0264}": 140, // ɤ
        "\u{03C7}": 142, // χ
        "\u{028E}": 143, // ʎ
        "\u{0292}": 147, // ʒ
        "\u{0294}": 148, // ʔ
        "\u{02C8}": 156, // ˈ (primary stress)
        "\u{02CC}": 157, // ˌ (secondary stress)
        "\u{02D0}": 158, // ː (length)
        "\u{02B0}": 162, // ʰ (aspiration)
        "\u{02B2}": 164, // ʲ (palatalisation)
        "\u{2193}": 169, // ↓
        "\u{2192}": 171, // →
        "\u{2197}": 172, // ↗
        "\u{2198}": 173, // ↘
        "\u{1D7B}": 177, // ᵻ
    ]

    /// Tokenise a phoneme string to an array of integer token IDs.
    ///
    /// Characters not present in the vocabulary are silently dropped,
    /// matching KokoroSwift's Tokenizer behaviour.
    static func tokenise(_ phonemes: String) -> [Int] {
        return phonemes.compactMap { vocab[$0] }
    }
}
