// ABOUTME: Adaptive Instance Normalisation conditioned on a style vector.
// ABOUTME: Applies instance norm then modulates with learned gamma/beta from style.

import MLX
import MLXNN

/// Adaptive Instance Normalisation (AdaIN) for 1D sequences.
///
/// Given input x of shape [batch, channels, seqLen] and a style vector,
/// computes: (1 + gamma) * InstanceNorm(x) + beta
/// where gamma and beta are derived from the style via a linear projection.
/// Instance norm is across the time dimension (axis 2, channels-first layout).
class AdaIN1d {
    let fcWeight: MLXArray
    let fcBias: MLXArray
    let numFeatures: Int
    let eps: Float

    /// - Parameters:
    ///   - fcWeight: weight for the style projection [2*numFeatures, styleDim]
    ///   - fcBias: bias for the style projection [2*numFeatures]
    ///   - numFeatures: number of channels in the input
    ///   - eps: small constant for numerical stability in instance norm
    init(fcWeight: MLXArray, fcBias: MLXArray, numFeatures: Int, eps: Float = 1e-5) {
        self.fcWeight = fcWeight
        self.fcBias = fcBias
        self.numFeatures = numFeatures
        self.eps = eps
    }

    /// - Parameters:
    ///   - x: input tensor [batch, channels, seqLen] (channels-first)
    ///   - style: style vector [batch, styleDim]
    /// - Returns: normalised and modulated tensor [batch, channels, seqLen]
    func callAsFunction(_ x: MLXArray, style: MLXArray) -> MLXArray {
        // Project style to gamma and beta: [batch, 2*numFeatures]
        let projected = matmul(style, fcWeight.transposed()) + fcBias

        // Split into gamma and beta: each [batch, numFeatures]
        let parts = projected.split(parts: 2, axis: -1)
        let gamma = parts[0]
        let beta = parts[1]

        // Instance normalisation: normalise across the time dimension (axis 2, channels-first)
        let m = mean(x, axis: 2, keepDims: true)
        let v = x.variance(axis: 2, keepDims: true)
        let xNorm = (x - m) * (v + eps).rsqrt()

        // Expand gamma and beta for broadcasting: [batch, numFeatures, 1]
        let gammaExp = gamma.expandedDimensions(axis: -1)
        let betaExp = beta.expandedDimensions(axis: -1)

        return (1 + gammaExp) * xNorm + betaExp
    }
}
