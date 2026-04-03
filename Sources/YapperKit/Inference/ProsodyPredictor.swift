// ABOUTME: Predicts F0 (pitch) and N (voicing) contours for the Kokoro decoder.
// ABOUTME: Uses a shared BiLSTM followed by parallel AdainResBlk1d branches.

import MLX
import MLXNN

/// Simple 1D convolution for inference with pre-loaded weights.
///
/// Used by the prosody predictor's projection layers and noise convolutions.
class Conv1dInference {
    let weight: MLXArray
    let bias: MLXArray?
    let padding: Int
    let stride: Int
    let dilation: Int
    let groups: Int

    init(
        weight: MLXArray,
        bias: MLXArray? = nil,
        stride: Int = 1,
        padding: Int = 0,
        dilation: Int = 1,
        groups: Int = 1
    ) {
        self.weight = weight
        self.bias = bias
        self.padding = padding
        self.stride = stride
        self.dilation = dilation
        self.groups = groups
    }

    /// Input: [batch, channels, seqLen] (channels-first)
    /// Output: [batch, outChannels, seqLen'] (channels-first)
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        // Transpose to channels-last for MLX conv1d
        let xCL = x.transposed(0, 2, 1)
        var y = conv1d(xCL, weight, stride: stride, padding: padding, dilation: dilation, groups: groups)
        if let bias {
            y = y + bias
        }
        return y.transposed(0, 2, 1)
    }
}

/// Prosody predictor that generates pitch (F0) and voicing (N) curves.
///
/// Based on the StyleTTS2 architecture:
/// 1. Shared BiLSTM processes input with style conditioning
/// 2. Two parallel branches (F0 and N) each pass through AdainResBlk1d blocks
/// 3. 1x1 convolution projects to single-channel output
class KokoroProsodyPredictor {
    let shared: BiLSTM
    let f0Blocks: [AdainResBlk1d]
    let nBlocks: [AdainResBlk1d]
    let f0Proj: Conv1dInference
    let nProj: Conv1dInference

    /// Initialise from model weights.
    ///
    /// - Parameters:
    ///   - weights: sanitised model weight dictionary
    ///   - styleDim: style embedding dimension (128)
    ///   - dHid: hidden dimension (512)
    init(weights: [String: MLXArray], styleDim: Int, dHid: Int) {
        let halfHidden = dHid / 2

        shared = BiLSTM(
            forwardWeights: LSTMDirectionWeights(
                weightIH: weights["predictor.shared.weight_ih_l0"]!,
                weightHH: weights["predictor.shared.weight_hh_l0"]!,
                biasIH: weights["predictor.shared.bias_ih_l0"]!,
                biasHH: weights["predictor.shared.bias_hh_l0"]!
            ),
            backwardWeights: LSTMDirectionWeights(
                weightIH: weights["predictor.shared.weight_ih_l0_reverse"]!,
                weightHH: weights["predictor.shared.weight_hh_l0_reverse"]!,
                biasIH: weights["predictor.shared.bias_ih_l0_reverse"]!,
                biasHH: weights["predictor.shared.bias_hh_l0_reverse"]!
            ),
            hiddenSize: halfHidden
        )

        f0Blocks = Self.buildAdainBlocks(weights: weights, prefix: "predictor.F0", dHid: dHid, styleDim: styleDim)
        nBlocks = Self.buildAdainBlocks(weights: weights, prefix: "predictor.N", dHid: dHid, styleDim: styleDim)

        f0Proj = Conv1dInference(
            weight: weights["predictor.F0_proj.weight"]!,
            bias: weights["predictor.F0_proj.bias"]!
        )

        nProj = Conv1dInference(
            weight: weights["predictor.N_proj.weight"]!,
            bias: weights["predictor.N_proj.bias"]!
        )
    }

    /// Build the three AdainResBlk1d blocks for an F0 or N branch.
    private static func buildAdainBlocks(
        weights: [String: MLXArray],
        prefix: String,
        dHid: Int,
        styleDim: Int
    ) -> [AdainResBlk1d] {
        // Block 0: dHid -> dHid, no upsample
        // Block 1: dHid -> dHid/2, with upsample
        // Block 2: dHid/2 -> dHid/2, no upsample
        let halfHid = dHid / 2
        let configs: [(Int, Int, ConvTransposedWeighted?)] = [
            (dHid, dHid, nil),
            (dHid, halfHid, buildPool(weights: weights, prefix: "\(prefix).1", dimIn: dHid)),
            (halfHid, halfHid, nil),
        ]

        var blocks: [AdainResBlk1d] = []
        for (i, (dimIn, dimOut, pool)) in configs.enumerated() {
            let p = "\(prefix).\(i)"
            let conv1x1: ConvWeighted? = (dimIn != dimOut)
                ? ConvWeighted(
                    weightG: weights["\(p).conv1x1.weight_g"]!,
                    weightV: weights["\(p).conv1x1.weight_v"]!
                )
                : nil

            blocks.append(AdainResBlk1d(
                conv1: ConvWeighted(
                    weightG: weights["\(p).conv1.weight_g"]!,
                    weightV: weights["\(p).conv1.weight_v"]!,
                    bias: weights["\(p).conv1.bias"]!,
                    padding: 1
                ),
                conv2: ConvWeighted(
                    weightG: weights["\(p).conv2.weight_g"]!,
                    weightV: weights["\(p).conv2.weight_v"]!,
                    bias: weights["\(p).conv2.bias"]!,
                    padding: 1
                ),
                norm1: AdaIN1d(
                    fcWeight: weights["\(p).norm1.fc.weight"]!,
                    fcBias: weights["\(p).norm1.fc.bias"]!,
                    numFeatures: dimIn
                ),
                norm2: AdaIN1d(
                    fcWeight: weights["\(p).norm2.fc.weight"]!,
                    fcBias: weights["\(p).norm2.fc.bias"]!,
                    numFeatures: dimIn
                ),
                pool: pool,
                conv1x1: conv1x1
            ))
        }
        return blocks
    }

    /// Build the transposed convolution pool for upsampling blocks.
    private static func buildPool(
        weights: [String: MLXArray],
        prefix: String,
        dimIn: Int
    ) -> ConvTransposedWeighted {
        return ConvTransposedWeighted(
            weightG: weights["\(prefix).pool.weight_g"]!,
            weightV: weights["\(prefix).pool.weight_v"]!,
            bias: weights["\(prefix).pool.bias"]!,
            stride: 2,
            padding: 1,
            groups: dimIn
        )
    }

    /// Predict F0 and N curves from aligned encoding.
    ///
    /// - Parameters:
    ///   - x: aligned encoding [batch, channels, seqLen]
    ///   - style: global style embedding [batch, styleDim]
    /// - Returns: (F0 curve, N curve) each [batch, timeSteps]
    func callAsFunction(_ x: MLXArray, style: MLXArray) -> (MLXArray, MLXArray) {
        // Shared LSTM: input [batch, channels, seqLen] -> [batch, seqLen, channels] for LSTM
        let sharedOut = shared(x.transposed(0, 2, 1))
        // Back to channels-first: [batch, channels, seqLen]
        let sharedCF = sharedOut.transposed(0, 2, 1)

        // F0 branch: all in channels-first [batch, channels, seqLen]
        var f0 = sharedCF
        for block in f0Blocks {
            f0 = block(f0, style: style)
        }
        f0 = f0Proj(f0)  // [batch, 1, seqLen]

        // N branch
        var n = sharedCF
        for block in nBlocks {
            n = block(n, style: style)
        }
        n = nProj(n)  // [batch, 1, seqLen]

        // Squeeze channel dim (size 1) -> [batch, timeSteps]
        return (f0.squeezed(axis: 1), n.squeezed(axis: 1))
    }
}
