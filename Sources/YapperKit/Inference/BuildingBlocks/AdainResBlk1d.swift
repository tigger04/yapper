// ABOUTME: Residual block with AdaIN and optional upsampling for the style decoder.
// ABOUTME: Combines two conv layers with adaptive instance norm and a shortcut path.

import MLX
import MLXNN

/// Residual block with Adaptive Instance Normalisation.
///
/// Forward: (residual(x, style) + shortcut(x)) / sqrt(2)
///
/// Residual path: norm1 -> LeakyReLU(0.2) -> [upsample] -> conv1 -> norm2 -> LeakyReLU(0.2) -> conv2
/// Shortcut path: [upsample] -> [conv1x1 if channel dims differ], else identity
class AdainResBlk1d {
    let conv1: ConvWeighted
    let conv2: ConvWeighted
    let norm1: AdaIN1d
    let norm2: AdaIN1d
    let pool: ConvTransposedWeighted?
    let conv1x1: ConvWeighted?

    /// - Parameters:
    ///   - conv1: first convolution in the residual path
    ///   - conv2: second convolution in the residual path
    ///   - norm1: first AdaIN layer
    ///   - norm2: second AdaIN layer
    ///   - pool: optional transposed convolution for upsampling (nil if no upsampling)
    ///   - conv1x1: optional 1x1 convolution for channel projection on the shortcut (nil if channels match)
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
            h = pool(h)
        }

        h = conv1(h)
        h = norm2(h, style: style)
        h = leakyRelu(h, negativeSlope: 0.2)
        h = conv2(h)

        return h
    }

    private func shortcutPath(_ x: MLXArray) -> MLXArray {
        var h = x

        if let pool {
            h = pool(h)
        }

        if let conv1x1 {
            h = conv1x1(h)
        }

        return h
    }
}
