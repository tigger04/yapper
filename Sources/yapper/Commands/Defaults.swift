// ABOUTME: Shared default paths and utilities for CLI commands.
// ABOUTME: Provides model and voice directory locations.

import Foundation

/// Default path to the Kokoro model weights.
func defaultModelPath() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/models/kokoro-v1_0.safetensors")
}

/// Default path to the voice embeddings directory.
func defaultVoicesPath() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/voices")
}
