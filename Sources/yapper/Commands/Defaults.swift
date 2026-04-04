// ABOUTME: Shared default paths and utilities for CLI commands.
// ABOUTME: Resolves model and voice locations across Homebrew and source-build installs.

import Foundation

/// Candidate roots for the yapper data directory, checked in order.
///
/// 1. `$HOMEBREW_PREFIX/share/yapper` — set by Homebrew at runtime
/// 2. `/opt/homebrew/share/yapper` — Apple Silicon Homebrew default
/// 3. `/usr/local/share/yapper` — Intel Homebrew default
/// 4. `~/.local/share/yapper` — source-build convention
private func candidateDataRoots() -> [URL] {
    var roots: [URL] = []

    if let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
        roots.append(URL(fileURLWithPath: prefix).appendingPathComponent("share/yapper"))
    }
    roots.append(URL(fileURLWithPath: "/opt/homebrew/share/yapper"))
    roots.append(URL(fileURLWithPath: "/usr/local/share/yapper"))
    roots.append(
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/yapper")
    )
    return roots
}

/// Resolve the first candidate root that contains both the model file and voices directory.
/// Returns the home-directory fallback if none are found, so callers surface a consistent
/// "not found" error pointing at the expected source-build location.
private func resolveDataRoot() -> URL {
    let fm = FileManager.default
    let roots = candidateDataRoots()
    for root in roots {
        let model = root.appendingPathComponent("models/kokoro-v1_0.safetensors")
        var isDir: ObjCBool = false
        let voices = root.appendingPathComponent("voices")
        if fm.fileExists(atPath: model.path),
           fm.fileExists(atPath: voices.path, isDirectory: &isDir),
           isDir.boolValue {
            return root
        }
    }
    return roots.last!
}

/// Default path to the Kokoro model weights.
func defaultModelPath() -> URL {
    resolveDataRoot().appendingPathComponent("models/kokoro-v1_0.safetensors")
}

/// Default path to the voice embeddings directory.
func defaultVoicesPath() -> URL {
    resolveDataRoot().appendingPathComponent("voices")
}
