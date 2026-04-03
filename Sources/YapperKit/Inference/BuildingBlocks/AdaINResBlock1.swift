// ABOUTME: Generator residual block with Snake activation for HiFi-GAN.
// ABOUTME: Uses dilated convolutions with AdaIN and Snake activation across 3 iterations.

import MLX
import MLXNN

/// Snake activation: x + (1/alpha) * sin(alpha * x)^2
///
/// Used in place of standard activations in the HiFi-GAN generator for
/// better modelling of periodic audio signals.
private func snakeActivation(_ x: MLXArray, alpha: MLXArray) -> MLXArray {
    return x + (1.0 / alpha) * MLX.pow(MLX.sin(alpha * x), 2)
}

/// HiFi-GAN generator residual block with Snake activation and AdaIN.
///
/// Each of the 3 iterations applies:
///   adain1 -> snake -> dilatedConv1 -> adain2 -> snake -> conv2 -> residual add
///
/// The dilated convolutions use increasing dilation rates to capture
/// multi-scale temporal patterns in the audio signal.
class AdaINResBlock1 {
    let convs1: [ConvWeighted]
    let convs2: [ConvWeighted]
    let adain1: [AdaIN1d]
    let adain2: [AdaIN1d]
    let alpha1: [MLXArray]
    let alpha2: [MLXArray]

    /// - Parameters:
    ///   - convs1: array of 3 dilated convolutions (first conv per iteration)
    ///   - convs2: array of 3 convolutions (second conv per iteration)
    ///   - adain1: array of 3 AdaIN layers (before first conv)
    ///   - adain2: array of 3 AdaIN layers (before second conv)
    ///   - alpha1: array of 3 Snake alpha parameters (first activation)
    ///   - alpha2: array of 3 Snake alpha parameters (second activation)
    init(
        convs1: [ConvWeighted],
        convs2: [ConvWeighted],
        adain1: [AdaIN1d],
        adain2: [AdaIN1d],
        alpha1: [MLXArray],
        alpha2: [MLXArray]
    ) {
        self.convs1 = convs1
        self.convs2 = convs2
        self.adain1 = adain1
        self.adain2 = adain2
        self.alpha1 = alpha1
        self.alpha2 = alpha2
    }

    /// - Parameters:
    ///   - x: input tensor [batch, seqLen, channels]
    ///   - style: style vector [batch, styleDim]
    /// - Returns: output tensor [batch, seqLen, channels]
    func callAsFunction(_ x: MLXArray, style: MLXArray) -> MLXArray {
        var h = x

        for i in 0 ..< convs1.count {
            let residual = h

            // First half: adain1 -> snake -> dilated conv
            h = adain1[i](h, style: style)
            h = snakeActivation(h, alpha: alpha1[i])
            h = convs1[i](h)

            // Second half: adain2 -> snake -> conv
            h = adain2[i](h, style: style)
            h = snakeActivation(h, alpha: alpha2[i])
            h = convs2[i](h)

            // Residual connection
            h = h + residual
        }

        return h
    }
}
