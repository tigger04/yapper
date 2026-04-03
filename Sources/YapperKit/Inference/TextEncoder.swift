// ABOUTME: CNN + BiLSTM text encoder for the Kokoro-82M pipeline.
// ABOUTME: Encodes phoneme token sequences into features used by the decoder.

import MLX
import MLXNN

/// Text encoder that transforms tokenised phoneme sequences into contextual
/// embeddings for the decoder.
///
/// Architecture: Embedding -> N x (Conv1d + LayerNorm + LeakyReLU) -> BiLSTM.
/// Operates in [batch, channels, seqLen] layout internally, matching KokoroSwift.
class KokoroTextEncoder {
    let embedding: Embedding
    let cnnConvs: [ConvWeighted]
    let cnnNorms: [LayerNormInference]
    let lstm: BiLSTM

    /// Initialise the text encoder from model weights.
    ///
    /// - Parameters:
    ///   - weights: sanitised model weight dictionary
    ///   - channels: hidden dimension (512)
    ///   - kernelSize: CNN kernel size (5)
    ///   - depth: number of CNN blocks (3)
    init(weights: [String: MLXArray], channels: Int, kernelSize: Int, depth: Int) {
        embedding = Embedding(weight: weights["text_encoder.embedding.weight"]!)
        let padding = (kernelSize - 1) / 2

        var convs: [ConvWeighted] = []
        var norms: [LayerNormInference] = []
        for i in 0 ..< depth {
            convs.append(ConvWeighted(
                weightG: weights["text_encoder.cnn.\(i).0.weight_g"]!,
                weightV: weights["text_encoder.cnn.\(i).0.weight_v"]!,
                bias: weights["text_encoder.cnn.\(i).0.bias"]!,
                padding: padding
            ))
            norms.append(LayerNormInference(
                gamma: weights["text_encoder.cnn.\(i).1.gamma"]!,
                beta: weights["text_encoder.cnn.\(i).1.beta"]!
            ))
        }
        cnnConvs = convs
        cnnNorms = norms

        let halfHidden = channels / 2
        lstm = BiLSTM(
            forwardWeights: LSTMDirectionWeights(
                weightIH: weights["text_encoder.lstm.weight_ih_l0"]!,
                weightHH: weights["text_encoder.lstm.weight_hh_l0"]!,
                biasIH: weights["text_encoder.lstm.bias_ih_l0"]!,
                biasHH: weights["text_encoder.lstm.bias_hh_l0"]!
            ),
            backwardWeights: LSTMDirectionWeights(
                weightIH: weights["text_encoder.lstm.weight_ih_l0_reverse"]!,
                weightHH: weights["text_encoder.lstm.weight_hh_l0_reverse"]!,
                biasIH: weights["text_encoder.lstm.bias_ih_l0_reverse"]!,
                biasHH: weights["text_encoder.lstm.bias_hh_l0_reverse"]!
            ),
            hiddenSize: halfHidden
        )
    }

    /// Encode token sequences.
    ///
    /// - Parameters:
    ///   - x: padded token IDs [batch, seqLen]
    ///   - textMask: boolean mask where true = padding [batch, seqLen]
    /// - Returns: encoded features [batch, channels, seqLen]
    func callAsFunction(_ x: MLXArray, textMask: MLXArray) -> MLXArray {
        // Embed tokens: [batch, seqLen, embedDim]
        var h = embedding(x)

        // Transpose to [batch, channels, seqLen]
        h = h.transposed(0, 2, 1)

        // Expand mask for broadcasting: [batch, 1, seqLen]
        let mask = textMask.expandedDimensions(axis: 1)

        // Zero out padding positions
        h = MLX.where(mask, 0.0, h)

        // Process through CNN blocks — h is channels-first [batch, channels, seqLen]
        for i in 0 ..< cnnConvs.count {
            // ConvWeighted handles channels-first internally
            h = cnnConvs[i](h)

            // LayerNorm: transpose to [batch, seqLen, channels], norm, transpose back
            h = h.transposed(0, 2, 1)
            h = cnnNorms[i](h)
            h = h.transposed(0, 2, 1)

            // LeakyReLU
            h = leakyRelu(h, negativeSlope: 0.2)

            // Reapply mask
            h = MLX.where(mask, 0.0, h)
        }

        // BiLSTM expects [batch, seqLen, channels]
        h = h.transposed(0, 2, 1)
        h = lstm(h)
        h = h.transposed(0, 2, 1)

        // Pad to original mask length if needed
        let targetLen = mask.shape[mask.shape.count - 1]
        if h.shape[2] < targetLen {
            let pad = MLX.zeros([h.shape[0], h.shape[1], targetLen])
            pad[0 ..< h.shape[0], 0 ..< h.shape[1], 0 ..< h.shape[2]] = h
            h = pad
        }

        // Final mask application
        return MLX.where(mask, 0.0, h)
    }
}
