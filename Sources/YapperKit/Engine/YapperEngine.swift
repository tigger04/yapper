// ABOUTME: Core TTS engine. Loads Kokoro-82M model weights and orchestrates inference.
// ABOUTME: Entry point for all YapperKit synthesis operations.

import Foundation
import MLX

/// Errors that can occur during YapperKit operations.
public enum YapperError: Error, Equatable {
    case modelNotFound(path: String)
    case voicesNotFound(path: String)
    case invalidModelFile(path: String, message: String)
    case invalidVoicesFile(path: String, message: String)
}

/// Core TTS engine. Loads the Kokoro-82M model and voice embeddings,
/// then synthesises text to audio.
public class YapperEngine {
    let weights: [String: MLXArray]
    let voiceRegistry: VoiceRegistry

    /// Initialise the engine with paths to the model weights and voice directory.
    ///
    /// - Parameters:
    ///   - modelPath: Path to the kokoro-v1_0.safetensors file
    ///   - voicesPath: Path to the directory containing individual voice .safetensors files
    /// - Throws: `YapperError` if files are missing, inaccessible, or invalid
    public init(modelPath: URL, voicesPath: URL) throws {
        // Validate model file exists
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw YapperError.modelNotFound(path: modelPath.path)
        }

        // Validate voices directory exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: voicesPath.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw YapperError.voicesNotFound(path: voicesPath.path)
        }

        // Load model weights
        do {
            self.weights = try MLX.loadArrays(url: modelPath)
        } catch {
            throw YapperError.invalidModelFile(
                path: modelPath.path,
                message: error.localizedDescription
            )
        }

        // Load voice registry
        self.voiceRegistry = try VoiceRegistry(voicesPath: voicesPath)
    }
}
