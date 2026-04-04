// ABOUTME: CLI entry point for the yapper TTS tool.
// ABOUTME: Dispatches to subcommands: convert, speak, voices.

import ArgumentParser
import YapperKit

@main
struct YapperCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "yapper",
        abstract: "Fast, Apple Silicon-native text-to-speech toolkit.",
        version: YapperKit.version,
        subcommands: [SpeakCommand.self, VoicesCommand.self]
    )
}
