// ABOUTME: Custom bidirectional LSTM for Kokoro-82M inference.
// ABOUTME: Processes sequences forward and backward, concatenating hidden states.

import MLX
import MLXNN

/// Weights for a single LSTM direction (input-hidden, hidden-hidden, and their biases).
struct LSTMDirectionWeights {
    let weightIH: MLXArray
    let weightHH: MLXArray
    let biasIH: MLXArray
    let biasHH: MLXArray
}

/// Bidirectional LSTM that processes input sequences in both directions and
/// concatenates the resulting hidden states along the feature dimension.
///
/// Input shape: [batch, seqLen, inputSize]
/// Output shape: [batch, seqLen, 2 * hiddenSize]
class BiLSTM {
    let forwardWeights: LSTMDirectionWeights
    let backwardWeights: LSTMDirectionWeights
    let hiddenSize: Int

    init(
        forwardWeights: LSTMDirectionWeights,
        backwardWeights: LSTMDirectionWeights,
        hiddenSize: Int
    ) {
        self.forwardWeights = forwardWeights
        self.backwardWeights = backwardWeights
        self.hiddenSize = hiddenSize
    }

    /// Run a single LSTM direction over a sequence of timesteps.
    ///
    /// - Parameters:
    ///   - x: input tensor [batch, seqLen, inputSize]
    ///   - weights: LSTM weights for this direction
    ///   - forward: if true, iterate t=0..N-1; if false, iterate t=N-1..0
    /// - Returns: array of hidden states [batch, seqLen, hiddenSize]
    private func runDirection(
        _ x: MLXArray,
        weights: LSTMDirectionWeights,
        forward: Bool
    ) -> MLXArray {
        let batch = x.dim(0)
        let seqLen = x.dim(1)

        var h = MLXArray.zeros([batch, hiddenSize])
        var c = MLXArray.zeros([batch, hiddenSize])

        var outputs = [MLXArray]()
        outputs.reserveCapacity(seqLen)

        let indices = forward ? Array(0 ..< seqLen) : Array((0 ..< seqLen).reversed())

        for t in indices {
            // Extract timestep: [batch, inputSize]
            let xt = x[0..., t, 0...]

            // Gate computation: gates = xt @ W_ih^T + bias_ih + h @ W_hh^T + bias_hh
            // Each weight matrix has shape [4*hiddenSize, inputSize] or [4*hiddenSize, hiddenSize]
            let gates = matmul(xt, weights.weightIH.transposed())
                + weights.biasIH
                + matmul(h, weights.weightHH.transposed())
                + weights.biasHH

            // Split into four gates: input, forget, cell gate, output
            // gates shape: [batch, 4*hiddenSize]
            let chunked = gates.split(parts: 4, axis: -1)
            let i = sigmoid(chunked[0])
            let f = sigmoid(chunked[1])
            let g = tanh(chunked[2])
            let o = sigmoid(chunked[3])

            c = f * c + i * g
            h = o * tanh(c)

            outputs.append(h)
        }

        // If backward, reverse outputs to restore original time ordering
        if !forward {
            outputs.reverse()
        }

        // Stack along sequence dimension: [batch, seqLen, hiddenSize]
        return stacked(outputs, axis: 1)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let fwd = runDirection(x, weights: forwardWeights, forward: true)
        let bwd = runDirection(x, weights: backwardWeights, forward: false)

        // Concatenate along feature dimension: [batch, seqLen, 2*hiddenSize]
        return concatenated([fwd, bwd], axis: 2)
    }
}
