// ABOUTME: Residual block with AdaIN and optional upsampling for the style decoder.
// ABOUTME: Combines two conv layers with adaptive instance norm and a shortcut path.

import MLX
import MLXNN

/// Residual block with Adaptive Instance Normalisation.
///
/// Forward: (residual(x, style) + shortcut(x)) / sqrt(2)
///
/// Residual path: norm1 -> LeakyReLU(0.2) -> [transposed conv upsample + pad] -> conv1 -> norm2 -> LeakyReLU(0.2) -> conv2
/// Shortcut path: [nearest-neighbour 2x upsample] -> [conv1x1 if channel dims differ], else identity
///
/// NOTE: The shortcut uses nearest-neighbour upsampling, NOT transposed convolution.
/// The residual path uses transposed conv + padding for upsampling.
/// This matches KokoroSwift's implementation.
class AdainResBlk1d {
    let conv1: ConvWeighted
    let conv2: ConvWeighted
    let norm1: AdaIN1d
    let norm2: AdaIN1d
    let pool: ConvTransposedWeighted?
    let conv1x1: ConvWeighted?
    let hasUpsample: Bool

    init(
        conv1: ConvWeighted,
        conv2: ConvWeighted,
        norm1: AdaIN1d,
        norm2: AdaIN1d,
        pool: ConvTransposedWeighted? = nil,
        conv1x1: ConvWeighted? = nil
    ) {
        self.conv1 = conv1
        self.conv2 = conv2
        self.norm1 = norm1
        self.norm2 = norm2
        self.pool = pool
        self.conv1x1 = conv1x1
        self.hasUpsample = pool != nil
    }

    /// - Parameters:
    ///   - x: input tensor [batch, channels, seqLen] (channels-first)
    ///   - style: style vector [batch, styleDim]
    /// - Returns: output tensor [batch, channels', seqLen']
    func callAsFunction(_ x: MLXArray, style: MLXArray) -> MLXArray {
        let residual = residualPath(x, style: style)
        let shortcut = shortcutPath(x)

        return (residual + shortcut) / Float(2.0).squareRoot()
    }

    private func residualPath(_ x: MLXArray, style: MLXArray) -> MLXArray {
        var h = norm1(x, style: style)
        h = leakyRelu(h, negativeSlope: 0.2)

        if let pool {
            // Transposed conv upsample in residual path
            h = pool(h)
            // Pad time dimension by 1 at the start (channels-first: axis 2)
            h = MLX.padded(h, widths: [
                IntOrPair([0, 0]),  // batch
                IntOrPair([0, 0]),  // channels
                IntOrPair([1, 0])   // time: pad 1 at start
            ])
        }

        h = conv1(h)
        h = norm2(h, style: style)
        h = leakyRelu(h, negativeSlope: 0.2)
        h = conv2(h)

        return h
    }

    private func shortcutPath(_ x: MLXArray) -> MLXArray {
        var h = x

        if hasUpsample {
            // Shortcut uses nearest-neighbour 2x upsample, NOT transposed conv.
            // Transpose to channels-last for MLXNN Upsample, then back.
            h = h.transposed(0, 2, 1)  // [batch, seqLen, channels]
            h = Upsample(scaleFactor: 2.0, mode: .nearest)(h)
            h = h.transposed(0, 2, 1)  // [batch, channels, seqLen*2]
        }

        if let conv1x1 {
            h = conv1x1(h)
        }

        return h
    }
}
