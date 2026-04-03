// ABOUTME: Streams PCM audio to system speakers via AVAudioEngine.
// ABOUTME: Supports play, pause, resume, and stop controls.

import Foundation
import AVFoundation

/// Playback state for AudioPlayer.
public enum PlaybackState: Sendable {
    case idle
    case playing
    case paused
    case stopped
}

/// Streams PCM audio to system output without intermediate files.
public class AudioPlayer {
    /// Current playback state.
    public private(set) var state: PlaybackState = .idle

    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let format: AVAudioFormat

    /// Sample rate for Kokoro audio (24kHz).
    private static let sampleRate: Double = 24000

    public init() {
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )!

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    /// Schedule a buffer of PCM samples for playback.
    ///
    /// - Parameter samples: Float array of PCM samples at 24kHz.
    public func scheduleBuffer(_ samples: [Float]) throws {
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw YapperError.audioError(message: "Failed to create audio buffer")
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else {
            throw YapperError.audioError(message: "Failed to access buffer channel data")
        }
        samples.withUnsafeBufferPointer { src in
            channelData[0].update(from: src.baseAddress!, count: samples.count)
        }

        playerNode.scheduleBuffer(buffer)
    }

    /// Start playback of scheduled buffers.
    public func play() throws {
        if !engine.isRunning {
            try engine.start()
        }
        playerNode.play()
        state = .playing
    }

    /// Pause playback. Can be resumed.
    public func pause() {
        playerNode.pause()
        state = .paused
    }

    /// Resume playback after pause.
    public func resume() throws {
        if !engine.isRunning {
            try engine.start()
        }
        playerNode.play()
        state = .playing
    }

    /// Stop playback and release resources.
    public func stop() {
        playerNode.stop()
        engine.stop()
        state = .stopped
    }
}
