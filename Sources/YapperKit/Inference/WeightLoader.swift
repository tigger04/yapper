// ABOUTME: Loads and sanitises Kokoro-82M model weights from safetensors.
// ABOUTME: Transposes weight_v tensors and projection weights to match MLX conventions.

import Foundation
import MLX

/// Loads raw safetensors weights and applies the transpositions needed for
/// correct inference. This mirrors KokoroSwift's WeightLoader logic.
///
/// The Kokoro model stores some weights in PyTorch layout [out, in, kernel].
/// MLX conv1d expects [out, kernel, in]. Weight normalisation `weight_v` tensors
/// and certain projection weights need conditional transposition.
struct WeightLoader {

    private init() {}

    /// Load weights from a safetensors file and sanitise them for inference.
    ///
    /// - Parameter url: Path to the `.safetensors` model file
    /// - Returns: Dictionary of sanitised weight tensors
    /// - Throws: If the file cannot be read
    static func load(from url: URL) throws -> [String: MLXArray] {
        let raw = try MLX.loadArrays(url: url)
        var sanitised: [String: MLXArray] = [:]

        for (key, value) in raw {
            // Skip position_ids — not needed for inference
            if key.contains("position_ids") {
                continue
            }

            let processed = processWeight(key: key, value: value)
            sanitised[key] = processed
        }

        return sanitised
    }

    /// Apply per-key transposition rules.
    private static func processWeight(key: String, value: MLXArray) -> MLXArray {
        // Predictor F0/N projection weights need transposition
        if key.hasPrefix("predictor") {
            if key.contains("F0_proj.weight") || key.contains("N_proj.weight") {
                return value.transposed(0, 2, 1)
            }
            if key.contains("weight_v") {
                return transposeIfNeeded(value)
            }
            return value
        }

        // Text encoder weight_v needs conditional transposition
        if key.hasPrefix("text_encoder") {
            if key.contains("weight_v") {
                return transposeIfNeeded(value)
            }
            return value
        }

        // Decoder noise conv weights and weight_v need transposition
        if key.hasPrefix("decoder") {
            if key.contains("noise_convs"), key.hasSuffix(".weight") {
                return value.transposed(0, 2, 1)
            }
            if key.contains("weight_v") {
                return transposeIfNeeded(value)
            }
            return value
        }

        // BERT weights pass through unchanged (position_ids already filtered)
        return value
    }

    /// Transpose a 3D weight_v tensor if it is not already in MLX conv layout.
    ///
    /// MLX conv1d expects [outChannels, kernelSize, inChannels].
    /// If the tensor looks like [outChannels, inChannels, kernelSize] (PyTorch layout),
    /// transpose axes 1 and 2.
    ///
    /// Heuristic: the tensor is already correct if outChannels >= both other dims
    /// and dims 1 and 2 are equal (square kernel is a special case).
    private static func transposeIfNeeded(_ arr: MLXArray) -> MLXArray {
        guard arr.shape.count == 3 else { return arr }

        let outChannels = arr.shape[0]
        let dim1 = arr.shape[1]
        let dim2 = arr.shape[2]

        // Already in correct layout: [out, kernel, in] where out >= kernel and out >= in
        // and kernel == in (happens for 1x1 convolutions and some square cases)
        if outChannels >= dim1, outChannels >= dim2, dim1 == dim2 {
            return arr
        }

        return arr.transposed(0, 2, 1)
    }
}
