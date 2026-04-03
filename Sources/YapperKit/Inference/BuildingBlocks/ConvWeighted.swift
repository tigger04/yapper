// ABOUTME: Conv1d with weight normalisation for Kokoro-82M inference.
// ABOUTME: Provides both standard and transposed conv1d with normalised weights.

import MLX
import MLXNN

/// Conv1d with weight normalisation: weight = (v / ||v||) * g.
///
/// The pipeline operates in channels-first [batch, channels, seqLen] format
/// (matching PyTorch). MLX conv1d uses channels-last [batch, seqLen, channels].
/// This class handles the transposition automatically.
class ConvWeighted {
    let weightG: MLXArray
    let weightV: MLXArray
    let bias: MLXArray?
    let stride: Int
    let padding: Int
    let dilation: Int
    let groups: Int

    init(
        weightG: MLXArray,
        weightV: MLXArray,
        bias: MLXArray? = nil,
        stride: Int = 1,
        padding: Int = 0,
        dilation: Int = 1,
        groups: Int = 1
    ) {
        self.weightG = weightG
        self.weightV = weightV
        self.bias = bias
        self.stride = stride
        self.padding = padding
        self.dilation = dilation
        self.groups = groups
    }

    /// Compute the weight-normalised kernel.
    ///
    /// weightV shape: [outChannels, kernelSize, inChannels]
    /// weightG shape: [outChannels, 1, 1]
    /// Epsilon added for numerical stability (matches KokoroSwift).
    private func normalisedWeight() -> MLXArray {
        let vNorm = MLXLinalg.norm(weightV, axes: [1, 2], keepDims: true) + 1e-7
        return (weightV / vNorm) * weightG
    }

    /// Input: [batch, channels, seqLen] (channels-first)
    /// Output: [batch, outChannels, seqLen'] (channels-first)
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let w = normalisedWeight()
        // Transpose to channels-last for MLX conv1d
        let xCL = x.transposed(0, 2, 1)  // [batch, seqLen, inChannels]
        var y = conv1d(xCL, w, stride: stride, padding: padding, dilation: dilation, groups: groups)
        if let bias {
            y = y + bias
        }
        // Transpose back to channels-first
        return y.transposed(0, 2, 1)  // [batch, outChannels, seqLen']
    }
}

/// Transposed Conv1d with weight normalisation.
///
/// Used for upsampling in residual blocks. Also handles channels-first layout.
class ConvTransposedWeighted {
    let weightG: MLXArray
    let weightV: MLXArray
    let bias: MLXArray?
    let stride: Int
    let padding: Int
    let dilation: Int
    let groups: Int

    init(
        weightG: MLXArray,
        weightV: MLXArray,
        bias: MLXArray? = nil,
        stride: Int = 1,
        padding: Int = 0,
        dilation: Int = 1,
        groups: Int = 1
    ) {
        self.weightG = weightG
        self.weightV = weightV
        self.bias = bias
        self.stride = stride
        self.padding = padding
        self.dilation = dilation
        self.groups = groups
    }

    private func normalisedWeight() -> MLXArray {
        let vNorm = MLXLinalg.norm(weightV, axes: [1, 2], keepDims: true) + 1e-7
        return (weightV / vNorm) * weightG
    }

    /// Input: [batch, channels, seqLen] (channels-first)
    /// Output: [batch, outChannels, seqLen'] (channels-first)
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var w = normalisedWeight()
        // WeightLoader sanitises weight_v via transposeIfNeeded.
        // After sanitisation, regular transposed conv weights are [inCh, kernel, outCh].
        // MLX convTransposed1d expects [outCh, kernel, inCh].
        // So we need: transposed(2, 1, 0) to swap inCh and outCh.
        // For grouped depthwise: sanitised weight is [inCh, kernel, 1] — needs [inCh, kernel, 1]
        //   which is already correct (outCh=inCh for depthwise, groups handles the rest).
        if groups <= 1 {
            w = w.transposed(2, 1, 0)
        }
        // For groups > 1, weight is already in correct MLX layout after sanitisation

        let xCL = x.transposed(0, 2, 1)
        var y = convTransposed1d(
            xCL, w, stride: stride, padding: padding, dilation: dilation, groups: groups
        )
        if let bias {
            y = y + bias
        }
        return y.transposed(0, 2, 1)
    }
}
