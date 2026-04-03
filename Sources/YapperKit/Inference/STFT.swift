// ABOUTME: Short-Time Fourier Transform and its inverse for Kokoro audio synthesis.
// ABOUTME: Converts between time-domain audio and magnitude/phase spectrograms.

import MLX
import MLXFFT

// MARK: - Window functions

/// Generate a Hanning window of the given length.
///
/// Matches numpy.hanning: w[n] = 0.5 + 0.5 * cos(pi * n / (N-1))
/// where n ranges from -(N-1) to (N-1) in steps of 2.
func hanningWindow(length: Int) -> MLXArray {
    if length == 1 {
        return MLXArray(1.0)
    }
    let n = MLXArray(Array(stride(from: Float(1 - length), to: Float(length), by: 2.0)))
    let factor: Float = .pi / Float(length - 1)
    return 0.5 + 0.5 * cos(n * factor)
}

/// Unwrap phase discontinuities across frequency bins.
///
/// Matches numpy.unwrap: ensures that phase differences between adjacent
/// bins never exceed pi, by adding 2*pi corrections as needed.
func unwrapPhase(_ p: MLXArray) -> MLXArray {
    let period: Float = 2.0 * .pi
    let discont: Float = period / 2.0
    let intervalHigh: Float = period / 2.0
    let intervalLow: Float = -intervalHigh

    let pLeft = p[0..., 0 ..< p.shape[1] - 1]
    let pRight = p[0..., 1 ..< p.shape[1]]
    let pDiff = pRight - pLeft

    var pDiffMod = pDiff - intervalLow
    pDiffMod = (((pDiffMod % period) + period) % period) + intervalLow

    let ddSign = MLX.where(pDiff .> 0, intervalHigh, pDiffMod)
    pDiffMod = MLX.where(pDiffMod .== intervalLow, ddSign, pDiffMod)

    var phCorrect = pDiffMod - pDiff
    phCorrect = MLX.where(abs(pDiff) .< discont, MLXArray(0.0), phCorrect)

    return MLX.concatenated([
        p[0..., 0 ..< 1],
        p[0..., 1...] + phCorrect.cumsum(axis: 1),
    ], axis: 1)
}

// MARK: - Forward STFT

/// Compute the forward STFT of a 1D signal.
///
/// - Parameters:
///   - x: input signal [length]
///   - nFft: FFT size
///   - hopLength: hop between frames (default: nFft/4)
///   - winLength: window length (default: nFft)
/// - Returns: complex STFT matrix [nFft/2+1, numFrames]
func mlxStft(
    x: MLXArray,
    nFft: Int = 800,
    hopLength: Int? = nil,
    winLength: Int? = nil
) -> MLXArray {
    let hopLen = hopLength ?? nFft / 4
    let winLen = winLength ?? nFft

    // Generate Hanning window (periodic: length+1, then drop last)
    var w = hanningWindow(length: winLen + 1)[0 ..< winLen]

    // Zero-pad window to FFT size if needed
    if w.shape[0] < nFft {
        w = MLX.concatenated([w, MLXArray.zeros([nFft - w.shape[0]])], axis: 0)
    }

    // Reflect-pad the input for centering
    let padSize = nFft / 2
    let prefix = x[1 ..< padSize + 1][.stride(by: -1)]
    let suffix = x[-(padSize + 1) ..< -1][.stride(by: -1)]
    let padded = MLX.concatenated([prefix, x, suffix])

    // Frame the signal
    let numFrames = 1 + (padded.shape[0] - nFft) / hopLen
    let frames = MLX.asStrided(padded, [numFrames, nFft], strides: [hopLen, 1])

    // Apply window and compute FFT
    let spec = MLXFFT.rfft(frames * w)
    return spec.transposed(1, 0)
}

// MARK: - Inverse STFT

/// Reconstruct a time-domain signal from its STFT representation.
///
/// Uses overlap-add synthesis with the Hanning window.
///
/// - Parameters:
///   - x: complex STFT matrix [nFft/2+1, numFrames]
///   - hopLength: hop between frames
///   - winLength: window length
/// - Returns: reconstructed signal [length]
func mlxIstft(
    x: MLXArray,
    hopLength: Int? = nil,
    winLength: Int? = nil
) -> MLXArray {
    let winLen = winLength ?? ((x.shape[1] - 1) * 2)
    let hopLen = hopLength ?? (winLen / 4)

    var w = hanningWindow(length: winLen + 1)[0 ..< winLen]
    if w.shape[0] < winLen {
        w = MLX.concatenated([w, MLXArray.zeros([winLen - w.shape[0]])], axis: 0)
    }

    let xT = x.transposed(1, 0)
    let t = (xT.shape[0] - 1) * hopLen + winLen
    let windowModLen = 20 / 5  // = 4, matching KokoroSwift

    let wSquared = w * w
    let totalWsquared = MLX.concatenated(Array(repeating: wSquared, count: t / winLen))

    let output = MLXFFT.irfft(xT, axis: 1) * w

    var outputs: [MLXArray] = []
    var windowSums: [MLXArray] = []

    for i in 0 ..< windowModLen {
        let stride = output[.stride(from: i, by: windowModLen), .ellipsis].reshaped([-1])
        let wSum = totalWsquared[0 ..< stride.shape[0]]

        outputs.append(MLX.concatenated([
            MLXArray.zeros([i * hopLen]),
            stride,
            MLXArray.zeros([max(0, t - i * hopLen - stride.shape[0])]),
        ]))

        windowSums.append(MLX.concatenated([
            MLXArray.zeros([i * hopLen]),
            wSum,
            MLXArray.zeros([max(0, t - i * hopLen - wSum.shape[0])]),
        ]))
    }

    var reconstructed = outputs[0]
    var windowSum = windowSums[0]
    for i in 1 ..< windowModLen {
        reconstructed = reconstructed + outputs[i]
        windowSum = windowSum + windowSums[i]
    }

    let half = winLen / 2
    reconstructed = reconstructed[half ..< (reconstructed.shape[0] - half)]
        / windowSum[half ..< (windowSum.shape[0] - half)]

    return reconstructed
}

// MARK: - STFT Wrapper Class

/// Wrapper for forward and inverse STFT used in the Kokoro decoder/generator.
///
/// Stores filter parameters and provides transform/inverse methods that
/// handle batched input.
class MLXSTFT {
    let filterLength: Int
    let hopLength: Int
    let winLength: Int

    init(filterLength: Int = 800, hopLength: Int = 200, winLength: Int = 800) {
        self.filterLength = filterLength
        self.hopLength = hopLength
        self.winLength = winLength
    }

    /// Forward STFT: audio -> (magnitude, phase).
    ///
    /// - Parameter inputData: audio signal [batch, length] or [length]
    /// - Returns: (magnitude, phase) each [batch, nFft/2+1, numFrames]
    func transform(inputData: MLXArray) -> (MLXArray, MLXArray) {
        var audio = inputData
        if audio.ndim == 1 {
            audio = audio.expandedDimensions(axis: 0)
        }

        var magnitudes: [MLXArray] = []
        var phases: [MLXArray] = []

        for b in 0 ..< audio.shape[0] {
            let stft = mlxStft(
                x: audio[b],
                nFft: filterLength,
                hopLength: hopLength,
                winLength: winLength
            )
            magnitudes.append(MLX.abs(stft))
            phases.append(MLX.atan2(stft.imaginaryPart(), stft.realPart()))
        }

        return (MLX.stacked(magnitudes, axis: 0), MLX.stacked(phases, axis: 0))
    }

    /// Inverse STFT: (magnitude, phase) -> audio.
    ///
    /// - Parameters:
    ///   - magnitude: [batch, nFft/2+1, numFrames]
    ///   - phase: [batch, nFft/2+1, numFrames]
    /// - Returns: reconstructed audio [batch, 1, length]
    func inverse(magnitude: MLXArray, phase: MLXArray) -> MLXArray {
        var results: [MLXArray] = []

        for b in 0 ..< magnitude.shape[0] {
            let phaseCont = unwrapPhase(phase[b])
            let stft = magnitude[b] * MLX.exp(MLXArray(real: 0, imaginary: 1) * phaseCont)
            let audio = mlxIstft(x: stft, hopLength: hopLength, winLength: winLength)
            results.append(audio)
        }

        return MLX.stacked(results, axis: 0).expandedDimensions(axis: 1)
    }
}
