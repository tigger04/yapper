// ABOUTME: Orchestrates the full Kokoro-82M inference pipeline from text to audio.
// ABOUTME: Wires together G2P, BERT, duration/prosody prediction, and decoder.

import Foundation
import MLX
import MLXNN
import MLXUtilsLibrary

/// The complete Kokoro-82M inference pipeline.
///
/// Converts text + voice embedding into raw PCM audio by running:
/// G2P -> tokenise -> BERT -> duration prediction -> prosody prediction ->
/// text encoding -> alignment -> decoder -> audio.
///
/// Also produces word-level timestamps from predicted durations.
class KokoroPipeline {
    let bert: BERTModel
    let bertProjection: BERTProjection
    let durationEncoder: DurationEncoder
    let durationPredictor: DurationPredictor
    let prosodyPredictor: KokoroProsodyPredictor
    let textEncoder: KokoroTextEncoder
    let decoder: KokoroDecoder
    let g2p: MisakiG2P

    /// Maximum phoneme token count the model supports (positional embedding limit).
    static let maxTokenCount = 510

    /// Audio sample rate in Hz.
    static let sampleRate = 24000

    /// Initialise the pipeline from sanitised model weights.
    ///
    /// - Parameter weights: dictionary of weight tensors, already sanitised by WeightLoader
    init(weights: [String: MLXArray]) {
        let config = AlbertModelArgs(
            numHiddenLayers: KokoroConfig.PLBert.numHiddenLayers,
            numAttentionHeads: KokoroConfig.PLBert.numAttentionHeads,
            hiddenSize: KokoroConfig.PLBert.hiddenSize,
            intermediateSize: KokoroConfig.PLBert.intermediateSize,
            embeddingSize: KokoroConfig.PLBert.embeddingSize,
            innerGroupNum: KokoroConfig.PLBert.innerGroupNum,
            numHiddenGroups: KokoroConfig.PLBert.numHiddenGroups,
            layerNormEps: KokoroConfig.PLBert.layerNormEps,
            vocabSize: KokoroConfig.nToken
        )

        bert = BERTModel(weights: weights, config: config)
        bertProjection = BERTProjection(weights: weights)

        durationEncoder = DurationEncoder(
            weights: weights,
            dModel: KokoroConfig.hiddenDim,
            styleDim: KokoroConfig.styleDim,
            nLayers: KokoroConfig.nLayer
        )

        durationPredictor = DurationPredictor(
            weights: weights,
            hiddenDim: KokoroConfig.hiddenDim,
            styleDim: KokoroConfig.styleDim
        )

        prosodyPredictor = KokoroProsodyPredictor(
            weights: weights,
            styleDim: KokoroConfig.styleDim,
            dHid: KokoroConfig.hiddenDim
        )

        textEncoder = KokoroTextEncoder(
            weights: weights,
            channels: KokoroConfig.hiddenDim,
            kernelSize: KokoroConfig.textEncoderKernelSize,
            depth: KokoroConfig.nLayer
        )

        decoder = KokoroDecoder(
            weights: weights,
            dimIn: KokoroConfig.hiddenDim,
            styleDim: KokoroConfig.styleDim,
            resblockKernelSizes: KokoroConfig.ISTFTNet.resblockKernelSizes,
            upsampleRates: KokoroConfig.ISTFTNet.upsampleRates,
            upsampleInitialChannel: KokoroConfig.ISTFTNet.upsampleInitialChannel,
            resblockDilationSizes: KokoroConfig.ISTFTNet.resblockDilationSizes,
            upsampleKernelSizes: KokoroConfig.ISTFTNet.upsampleKernelSizes,
            genIstftNFft: KokoroConfig.ISTFTNet.genIstftNFft,
            genIstftHopSize: KokoroConfig.ISTFTNet.genIstftHopSize
        )

        g2p = MisakiG2P()
    }

    /// Synthesise audio from text.
    ///
    /// - Parameters:
    ///   - text: input text
    ///   - voiceEmbedding: voice embedding loaded from VoiceRegistry
    ///   - accent: accent for G2P (american or british)
    ///   - speed: speed multiplier (1.0 = normal)
    /// - Returns: (PCM samples, word timestamps)
    /// - Throws: `YapperError` if text exceeds token limit or synthesis fails
    func synthesise(
        text: String,
        voiceEmbedding: MLXArray,
        accent: Accent,
        speed: Float = 1.0
    ) throws -> ([Float], [WordTimestamp]) {
        // Step 1: G2P
        g2p.configure(accent: accent)
        let (phonemes, tokens) = try g2p.phonemise(text)

        // Step 2: Tokenise
        let tokenIds = KokoroConfig.tokenise(phonemes)
        guard tokenIds.count <= Self.maxTokenCount else {
            throw YapperError.synthesisError(
                message: "Input exceeds \(Self.maxTokenCount) phoneme tokens (\(tokenIds.count))"
            )
        }

        // Step 3: Prepare input tensors
        let (paddedIds, attentionMask, textMask) = prepareInputTensors(tokenIds)

        // Step 4: Extract style embeddings from voice
        let (globalStyle, acousticStyle) = extractStyleEmbeddings(
            voice: voiceEmbedding,
            tokenCount: tokenIds.count
        )

        // Step 5: BERT encoding
        let bertOut = bert(paddedIds, attentionMask: attentionMask)
        let bertProjected = bertProjection(bertOut)
        let bertEncoded = bertProjected.transposed(0, 2, 1)

        // Step 6: Duration encoding and prediction
        let durFeatures = durationEncoder(bertEncoded, style: globalStyle, textMask: textMask)
        let predictedDurations = durationPredictor(durFeatures, speed: speed)

        // Step 7: Build alignment matrix
        let alignmentTarget = buildAlignmentTarget(
            durations: predictedDurations,
            batchSize: paddedIds.shape[1]
        )

        // Step 8: Align encoding
        let alignedEncoding = durFeatures.transposed(0, 2, 1).matmul(alignmentTarget)

        // Step 9: Prosody prediction
        let (f0, n) = prosodyPredictor(alignedEncoding, style: globalStyle)

        // Step 10: Text encoding and alignment
        let textEncoded = textEncoder(paddedIds, textMask: textMask)
        let asrFeatures = MLX.matmul(textEncoded, alignmentTarget)

        // Step 11: Decode to audio
        let audio = decoder(asr: asrFeatures, f0Curve: f0, n: n, style: acousticStyle)

        // Step 12: Extract PCM samples
        let samples: [Float] = audio[0].asArray(Float.self)

        // Step 13: Predict timestamps
        let timestamps = predictTimestamps(tokens: tokens, durations: predictedDurations)

        return (samples, timestamps)
    }

    // MARK: - Private helpers

    /// Prepare padded input IDs, attention mask, and text mask.
    private func prepareInputTensors(_ tokenIds: [Int]) -> (MLXArray, MLXArray, MLXArray) {
        // Add BOS/EOS padding tokens (0)
        let padded = [0] + tokenIds + [0]
        let paddedIds = MLXArray(padded).expandedDimensions(axes: [0])
        let seqLen = padded.count

        // Input lengths
        let inputLengths = MLXArray(seqLen)

        // Text mask: true where padding (for masking in encoders)
        var textMask = MLXArray(0 ..< seqLen)
        textMask = textMask + 1 .> inputLengths
        textMask = textMask.expandedDimensions(axes: [0])

        // Attention mask: 1 for valid, 0 for padding (for BERT)
        let maskBools: [Bool] = textMask.asArray(Bool.self)
        let maskInts = maskBools.map { !$0 ? 1 : 0 }
        let attentionMask = MLXArray(maskInts).reshaped(textMask.shape)

        return (paddedIds, attentionMask, textMask)
    }

    /// Extract global (prosody/duration) and acoustic style embeddings from voice.
    ///
    /// The voice embedding has shape [seqLen, 2, 256]. We index by token count
    /// to get the relevant style vector, then split it:
    /// - indices 128..255 = global style (for duration/prosody)
    /// - indices 0..127 = acoustic style (for decoder)
    private func extractStyleEmbeddings(
        voice: MLXArray,
        tokenCount: Int
    ) -> (MLXArray, MLXArray) {
        // Voice shape: [510, 1, 256] for individual safetensors (v1.0 format)
        // Index by token count, squeeze the middle dim -> [256]
        let refStyle = voice[tokenCount - 1].squeezed()  // [256]

        // Split: indices 128..255 = global style, indices 0..127 = acoustic style
        let globalStyle = refStyle[128...]               // [128]
        let acousticStyle = refStyle[0 ..< 128]          // [128]

        // Expand to [1, 128] for broadcasting in style-conditioned layers
        return (
            globalStyle.expandedDimensions(axes: [0]),
            acousticStyle.expandedDimensions(axes: [0])
        )
    }

    /// Build a one-hot alignment matrix from predicted durations.
    ///
    /// Maps each phoneme to a number of frames proportional to its duration.
    ///
    /// - Parameters:
    ///   - durations: per-phoneme durations [seqLen]
    ///   - batchSize: size of padded input
    /// - Returns: alignment target [1, batchSize, totalFrames]
    private func buildAlignmentTarget(
        durations: MLXArray,
        batchSize: Int
    ) -> MLXArray {
        // Build index array: repeat each phoneme index by its duration
        let indices = MLX.concatenated(
            durations.enumerated().map { index, duration in
                let frameCount: Int = duration.item()
                return MLX.repeated(MLXArray([index]), count: frameCount)
            }
        )

        let totalFrames = indices.shape[0]
        var alignmentArray = [Float](repeating: 0.0, count: totalFrames * batchSize)

        for frame in 0 ..< totalFrames {
            let phonemeIndex: Int = indices[frame].item()
            alignmentArray[phonemeIndex * totalFrames + frame] = 1.0
        }

        let target = MLXArray(alignmentArray).reshaped([batchSize, totalFrames])
        return target.expandedDimensions(axis: 0)
    }

    /// Predict word-level timestamps from MToken array and predicted durations.
    ///
    /// Matches KokoroSwift's TimestampPredictor logic: accumulates half-frames,
    /// divides by 80 to convert to seconds.
    private func predictTimestamps(
        tokens: [MToken],
        durations: MLXArray
    ) -> [WordTimestamp] {
        guard !tokens.isEmpty, durations.shape[0] >= 3 else {
            return []
        }

        let magicDivisor: Float = 80.0
        var left: Float = 0
        var right: Float = 2 * max(0, Float(durations[0].item() as Int32) - 3)
        left = right

        var timestamps: [WordTimestamp] = []
        var i = 1

        for token in tokens {
            guard i < durations.shape[0] - 1 else { break }

            if token.phonemes == nil {
                if !token.whitespace.isEmpty {
                    i += 1
                    let dur: Float = durations[i].item()
                    left = right + dur
                    right = left + dur
                    i += 1
                }
                continue
            }

            let phonemeCount = token.phonemes!.count
            let j = i + phonemeCount
            if j >= durations.shape[0] { break }

            let startTime = Double(left / magicDivisor)
            var tokenDuration: Float = 0
            for k in i ..< j {
                let d: Float = durations[k].item()
                tokenDuration += d
            }
            let spaceDuration: Float = token.whitespace.isEmpty ? 0.0 : Float(durations[j].item() as Int32)
            left = right + (2.0 * tokenDuration) + spaceDuration
            let endTime = Double(left / magicDivisor)
            right = left + spaceDuration
            i = j + (token.whitespace.isEmpty ? 0 : 1)

            let word = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty {
                timestamps.append(WordTimestamp(
                    word: word,
                    startTime: startTime,
                    endTime: endTime
                ))
            }
        }

        return timestamps
    }
}
