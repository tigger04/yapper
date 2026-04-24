// ABOUTME: Live progress display for synthesis operations on stderr.
// ABOUTME: Shows a progress bar with percentage and current text, refreshed in place via \r.

import Foundation

/// Displays a two-line progress indicator on stderr, refreshed in place.
///
/// Line 1: `[████████░░░░░░░░░░░░] 42%`
/// Line 2: `...the Melding Plague hit and everything collapsed.`
///
/// All output goes to stderr so stdout piping is unaffected.
/// When `quiet` is true, all methods are no-ops.
struct ProgressReporter {
    let totalChunks: Int
    let quiet: Bool
    private var currentChunk = 0

    private static let barWidth = 20
    private static let textMaxLen = 60

    init(totalChunks: Int, quiet: Bool = false) {
        self.totalChunks = max(totalChunks, 1)
        self.quiet = quiet
    }

    /// Update progress after a chunk completes.
    mutating func update(chunkText: String) {
        guard !quiet else { return }
        currentChunk += 1
        let pct = (currentChunk * 100) / totalChunks
        let filled = (currentChunk * Self.barWidth) / totalChunks
        let empty = Self.barWidth - filled
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)

        // Truncate text to fit
        var displayText = chunkText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if displayText.count > Self.textMaxLen {
            displayText = String(displayText.prefix(Self.textMaxLen - 3)) + "..."
        }

        // Overwrite the two lines in place
        fputs("\r  [\(bar)] \(pct)%\n  \(displayText)\u{1B}[A\r", stderr)
    }

    /// Print the final state and move past the progress lines.
    mutating func finish(summary: String) {
        guard !quiet else { return }
        // Clear the two progress lines and print the summary
        fputs("\r\u{1B}[K\n\u{1B}[K\r\(summary)\n", stderr)
    }

    /// Print a per-file header above the progress bar.
    static func fileHeader(_ text: String, quiet: Bool) {
        guard !quiet else { return }
        fputs("\(text)\n", stderr)
    }
}
