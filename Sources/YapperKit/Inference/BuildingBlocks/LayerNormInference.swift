// ABOUTME: Simple layer normalisation for inference with pre-loaded weights.
// ABOUTME: Standard layer norm computation using gamma and beta parameters.

import MLX
import MLXNN

/// Layer normalisation for inference with pre-loaded gamma and beta weights.
///
/// Normalises the last dimension of the input:
///   output = gamma * (x - mean) / sqrt(variance + eps) + beta
class LayerNormInference {
    let gamma: MLXArray
    let beta: MLXArray
    let eps: Float

    /// - Parameters:
    ///   - gamma: scale parameter [features]
    ///   - beta: shift parameter [features]
    ///   - eps: small constant for numerical stability
    init(gamma: MLXArray, beta: MLXArray, eps: Float = 1e-5) {
        self.gamma = gamma
        self.beta = beta
        self.eps = eps
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        return MLXFast.layerNorm(x, weight: gamma, bias: beta, eps: eps)
    }
}
