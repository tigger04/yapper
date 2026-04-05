// ABOUTME: Manages loading and selection of Kokoro voice embeddings.
// ABOUTME: Loads individual .safetensors voice files from a directory.

import Foundation
import MLX

/// Registry of available Kokoro voices. Loads voice embeddings from
/// individual .safetensors files in a directory.
public class VoiceRegistry {
    /// All available voices, sorted by name.
    public let voices: [Voice]

    public let voicesPath: URL
    private var cache: [String: MLXArray] = [:]

    /// Initialise the registry by scanning a directory for voice .safetensors files.
    ///
    /// - Parameter voicesPath: Directory containing voice .safetensors files
    /// - Throws: `YapperError.voicesNotFound` if no voice files are found
    public init(voicesPath: URL) throws {
        self.voicesPath = voicesPath

        let fm = FileManager.default
        let contents: [String]
        do {
            contents = try fm.contentsOfDirectory(atPath: voicesPath.path)
        } catch {
            throw YapperError.voicesNotFound(path: voicesPath.path)
        }

        let parsed = contents
            .filter { $0.hasSuffix(".safetensors") }
            .compactMap { filename -> Voice? in
                let name = String(filename.dropLast(".safetensors".count))
                return Voice(name: name)
            }
            .sorted { $0.name < $1.name }

        guard !parsed.isEmpty else {
            throw YapperError.voicesNotFound(path: voicesPath.path)
        }

        self.voices = parsed
    }

    /// Return voices matching the given filter, or all voices if filter is nil.
    public func list(filter: VoiceFilter? = nil) -> [Voice] {
        guard let filter else { return voices }
        return voices.filter { filter.matches($0) }
    }

    /// Select a deterministic random voice, optionally filtered.
    ///
    /// - Parameters:
    ///   - filter: Optional filter to constrain selection
    ///   - seed: Seed for deterministic selection. Same seed always produces same voice.
    /// - Returns: A voice from the filtered set
    public func random(filter: VoiceFilter? = nil, seed: UInt64 = 0) -> Voice? {
        let candidates = list(filter: filter)
        guard !candidates.isEmpty else { return nil }
        // Deterministic selection: use seed to pick an index
        let index = Int(seed % UInt64(candidates.count))
        return candidates[index]
    }

    /// Select a non-deterministically random voice, optionally filtered.
    ///
    /// Unlike `random(filter:seed:)`, this uses the system random number generator
    /// and produces a different result each call. Used by `yapper speak` as the
    /// default fallback when no voice has been pinned via --voice or $YAPPER_VOICE.
    ///
    /// - Parameter filter: Optional filter to constrain selection
    /// - Returns: A random voice from the filtered set, or nil if the set is empty
    public func randomSystem(filter: VoiceFilter? = nil) -> Voice? {
        list(filter: filter).randomElement()
    }

    /// Load the MLXArray embedding for a voice.
    ///
    /// - Parameter name: Voice name, e.g. "af_heart"
    /// - Returns: The voice embedding as an MLXArray
    /// - Throws: `YapperError` if the voice file cannot be loaded
    public func load(name: String) throws -> MLXArray {
        if let cached = cache[name] {
            return cached
        }

        let filePath = voicesPath.appendingPathComponent("\(name).safetensors")
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw YapperError.voicesNotFound(path: filePath.path)
        }

        let arrays: [String: MLXArray]
        do {
            arrays = try MLX.loadArrays(url: filePath)
        } catch {
            throw YapperError.invalidVoicesFile(
                path: filePath.path,
                message: error.localizedDescription
            )
        }

        // Voice safetensors contain a single array; take the first value
        guard let embedding = arrays.values.first else {
            throw YapperError.invalidVoicesFile(
                path: filePath.path,
                message: "Voice file contains no arrays"
            )
        }

        cache[name] = embedding
        return embedding
    }
}
