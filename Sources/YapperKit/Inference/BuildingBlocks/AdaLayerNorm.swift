// ABOUTME: Layer normalisation conditioned on a style vector.
// ABOUTME: Applies layer norm then modulates with learned gamma/beta from style.

import MLX
import MLXNN

/// Adaptive Layer Normalisation conditioned on a style vector.
///
/// Given input x and a style vector, computes:
/// (1 + gamma) * LayerNorm(x) + beta
/// where gamma and beta are derived from the style via a linear projection.
class AdaLayerNorm {
    let fcWeight: MLXArray
    let fcBias: MLXArray
    let eps: Float

    /// - Parameters:
    ///   - fcWeight: weight for the style projection [2*features, styleDim]
    ///   - fcBias: bias for the style projection [2*features]
    ///   - eps: small constant for numerical stability in layer norm
    init(fcWeight: MLXArray, fcBias: MLXArray, eps: Float = 1e-5) {
        self.fcWeight = fcWeight
        self.fcBias = fcBias
        self.eps = eps
    }

    /// - Parameters:
    ///   - x: input tensor [..., features]
    ///   - style: style vector [batch, styleDim]
    /// - Returns: normalised and modulated tensor, same shape as x
    func callAsFunction(_ x: MLXArray, style: MLXArray) -> MLXArray {
        // Project style to gamma and beta: [batch, 2*features]
        let projected = matmul(style, fcWeight.transposed()) + fcBias

        // Split into gamma and beta: each [batch, features]
        let parts = projected.split(parts: 2, axis: -1)
        let gamma = parts[0]
        let beta = parts[1]

        // Layer normalisation across the last dimension
        let m = mean(x, axis: -1, keepDims: true)
        let v = x.variance(axis: -1, keepDims: true)
        let xNorm = (x - m) * (v + eps).rsqrt()

        return (1 + gamma) * xNorm + beta
    }
}
