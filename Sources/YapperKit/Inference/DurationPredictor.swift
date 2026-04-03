// ABOUTME: Duration encoder and predictor for phoneme timing in Kokoro-82M.
// ABOUTME: Alternates BiLSTM and AdaLayerNorm layers with style conditioning.

import MLX
import MLXNN

/// Duration encoder that processes BERT-encoded features with style conditioning
/// to produce representations for duration prediction.
///
/// Architecture: alternating BiLSTM and AdaLayerNorm layers, with style
/// embeddings concatenated at each stage.
class DurationEncoder {
    /// Alternating layers: even indices = BiLSTM, odd indices = AdaLayerNorm.
    let lstmLayers: [BiLSTM]
    let normLayers: [AdaLayerNorm]
    let layerCount: Int

    /// Initialise from model weights.
    ///
    /// - Parameters:
    ///   - weights: sanitised model weight dictionary
    ///   - dModel: model hidden dimension (512)
    ///   - styleDim: style embedding dimension (128)
    ///   - nLayers: number of LSTM/norm pairs (3)
    init(weights: [String: MLXArray], dModel: Int, styleDim: Int, nLayers: Int) {
        layerCount = nLayers
        var lstms: [BiLSTM] = []
        var norms: [AdaLayerNorm] = []

        for i in 0 ..< nLayers {
            let lstmIdx = i * 2
            let normIdx = i * 2 + 1

            let halfHidden = dModel / 2
            lstms.append(BiLSTM(
                forwardWeights: LSTMDirectionWeights(
                    weightIH: weights["predictor.text_encoder.lstms.\(lstmIdx).weight_ih_l0"]!,
                    weightHH: weights["predictor.text_encoder.lstms.\(lstmIdx).weight_hh_l0"]!,
                    biasIH: weights["predictor.text_encoder.lstms.\(lstmIdx).bias_ih_l0"]!,
                    biasHH: weights["predictor.text_encoder.lstms.\(lstmIdx).bias_hh_l0"]!
                ),
                backwardWeights: LSTMDirectionWeights(
                    weightIH: weights["predictor.text_encoder.lstms.\(lstmIdx).weight_ih_l0_reverse"]!,
                    weightHH: weights["predictor.text_encoder.lstms.\(lstmIdx).weight_hh_l0_reverse"]!,
                    biasIH: weights["predictor.text_encoder.lstms.\(lstmIdx).bias_ih_l0_reverse"]!,
                    biasHH: weights["predictor.text_encoder.lstms.\(lstmIdx).bias_hh_l0_reverse"]!
                ),
                hiddenSize: halfHidden
            ))

            norms.append(AdaLayerNorm(
                fcWeight: weights["predictor.text_encoder.lstms.\(normIdx).fc.weight"]!,
                fcBias: weights["predictor.text_encoder.lstms.\(normIdx).fc.bias"]!
            ))
        }

        lstmLayers = lstms
        normLayers = norms
    }

    /// Encode features with style conditioning.
    ///
    /// - Parameters:
    ///   - x: BERT-encoded features [batch, channels, seqLen]
    ///   - style: style embedding [batch, styleDim]
    ///   - textMask: boolean mask where true = padding [batch, seqLen]
    /// - Returns: duration features [batch, seqLen, dModel]
    func callAsFunction(_ x: MLXArray, style: MLXArray, textMask: MLXArray) -> MLXArray {
        let seqLen = x.dim(2)
        let batch = x.dim(0)
        let styleDim = style.dim(style.ndim - 1)

        // Transpose x to [seqLen, batch, channels]
        var h = x.transposed(2, 0, 1)

        // Broadcast style to [seqLen, batch, styleDim]
        let sBroadcast = MLX.broadcast(style, to: [seqLen, batch, styleDim])

        // Concatenate features with style: [seqLen, batch, channels+styleDim]
        h = MLX.concatenated([h, sBroadcast], axis: -1)

        // Apply mask: expand [batch, seqLen] -> [seqLen, batch, 1] for masking
        let maskT = textMask.expandedDimensions(axes: [-1]).transposed(1, 0, 2)
        h = MLX.where(maskT, MLXArray.zeros(like: h), h)

        // Transpose to [batch, channels+styleDim, seqLen]
        h = h.transposed(1, 2, 0)

        // Style in [batch, styleDim, seqLen] layout for re-concatenation
        let styleForConcat = sBroadcast.transposed(1, 2, 0)

        // Mask in [batch, 1, seqLen] layout for reapplying
        let maskBCS = textMask.expandedDimensions(axes: [1])

        for i in 0 ..< layerCount {
            // BiLSTM expects [batch, seqLen, features]
            // h is [batch, 640, seqLen] -> transpose to [batch, seqLen, 640]
            let lstmIn = h.transposed(0, 2, 1)
            // BiLSTM output: [batch, seqLen, 2*hiddenSize] = [batch, seqLen, 512]
            let lstmOut = lstmLayers[i](lstmIn)
            // Transpose to [batch, 512, seqLen]
            h = lstmOut.transposed(0, 2, 1)

            // AdaLayerNorm expects [..., features], pass [batch, seqLen, 512]
            h = normLayers[i](h.transposed(0, 2, 1), style: style).transposed(0, 2, 1)

            // Re-concatenate style: [batch, 512, seqLen] + [batch, 128, seqLen] -> [batch, 640, seqLen]
            h = MLX.concatenated([h, styleForConcat], axis: 1)

            // Reapply mask: [batch, 1, seqLen] broadcasts over features
            h = MLX.where(maskBCS, MLXArray.zeros(like: h), h)
        }

        // Output: [batch, seqLen, features]
        return h.transposed(0, 2, 1)
    }
}

/// Predicts per-phoneme durations from encoded features.
///
/// Uses a BiLSTM followed by a linear projection with sigmoid activation.
/// The predicted durations determine the alignment matrix that maps phoneme
/// features to mel-spectrogram frames.
class DurationPredictor {
    let lstm: BiLSTM
    let projection: Linear

    /// Initialise from model weights.
    init(weights: [String: MLXArray], hiddenDim: Int, styleDim: Int) {
        let halfHidden = hiddenDim / 2
        lstm = BiLSTM(
            forwardWeights: LSTMDirectionWeights(
                weightIH: weights["predictor.lstm.weight_ih_l0"]!,
                weightHH: weights["predictor.lstm.weight_hh_l0"]!,
                biasIH: weights["predictor.lstm.bias_ih_l0"]!,
                biasHH: weights["predictor.lstm.bias_hh_l0"]!
            ),
            backwardWeights: LSTMDirectionWeights(
                weightIH: weights["predictor.lstm.weight_ih_l0_reverse"]!,
                weightHH: weights["predictor.lstm.weight_hh_l0_reverse"]!,
                biasIH: weights["predictor.lstm.bias_ih_l0_reverse"]!,
                biasHH: weights["predictor.lstm.bias_hh_l0_reverse"]!
            ),
            hiddenSize: halfHidden
        )
        projection = Linear(
            weight: weights["predictor.duration_proj.linear_layer.weight"]!,
            bias: weights["predictor.duration_proj.linear_layer.bias"]!
        )
    }

    /// Predict durations from duration-encoded features.
    ///
    /// - Parameters:
    ///   - features: duration encoder output [batch, seqLen, features]
    ///   - speed: speed multiplier (higher = shorter durations)
    /// - Returns: integer durations per phoneme [seqLen] (first batch element)
    func callAsFunction(_ features: MLXArray, speed: Float) -> MLXArray {
        let lstmOut = lstm(features)
        let logits = projection(lstmOut)

        // Sigmoid -> sum over last dim -> divide by speed -> round -> clamp to >= 1
        let durFloat = MLX.sigmoid(logits).sum(axis: -1) / speed
        return MLX.clip(durFloat.round(), min: 1).asType(.int32)[0]
    }
}
