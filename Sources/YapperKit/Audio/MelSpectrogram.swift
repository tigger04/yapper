// ABOUTME: Mel-spectrogram computation for audio quality comparison.
// ABOUTME: Uses Accelerate/vDSP for FFT — no external dependency.

import Foundation
import Accelerate

/// Mel-spectrogram computation and comparison utilities.
public struct MelSpectrogram {

    /// Compute a mel-spectrogram from PCM audio samples.
    ///
    /// - Parameters:
    ///   - samples: PCM float samples
    ///   - sampleRate: sample rate in Hz
    ///   - nFFT: FFT size (default 1024)
    ///   - hopLength: hop between frames (default 256)
    ///   - nMels: number of mel bands (default 80)
    /// - Returns: 2D array [nMels][nFrames] of mel-scale power values
    public static func compute(
        samples: [Float],
        sampleRate: Int,
        nFFT: Int = 1024,
        hopLength: Int = 256,
        nMels: Int = 80
    ) -> [[Float]] {
        let nFrames = max(1, (samples.count - nFFT) / hopLength + 1)

        // Create Hann window
        var window = [Float](repeating: 0, count: nFFT)
        vDSP_hann_window(&window, vDSP_Length(nFFT), Int32(vDSP_HANN_NORM))

        // FFT setup
        let log2n = vDSP_Length(log2(Float(nFFT)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let nBins = nFFT / 2 + 1

        // Compute STFT magnitude
        var magnitudes = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nBins)

        for frame in 0..<nFrames {
            let start = frame * hopLength
            let end = min(start + nFFT, samples.count)
            var windowed = [Float](repeating: 0, count: nFFT)
            let available = end - start
            for i in 0..<available {
                windowed[i] = samples[start + i] * window[i]
            }

            // Split into real/imaginary for vDSP
            var realPart = [Float](repeating: 0, count: nFFT / 2)
            var imagPart = [Float](repeating: 0, count: nFFT / 2)
            windowed.withUnsafeBufferPointer { ptr in
                realPart.withUnsafeMutableBufferPointer { realBuf in
                    imagPart.withUnsafeMutableBufferPointer { imagBuf in
                        var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                        ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: nFFT / 2) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(nFFT / 2))
                        }
                    }
                }
            }

            // Forward FFT
            realPart.withUnsafeMutableBufferPointer { realBuf in
                imagPart.withUnsafeMutableBufferPointer { imagBuf in
                    var splitResult = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    vDSP_fft_zrip(fftSetup, &splitResult, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }

            // Compute magnitude
            for bin in 0..<nBins {
                let r: Float
                let im: Float
                if bin == 0 {
                    r = realPart[0]
                    im = 0
                } else if bin == nFFT / 2 {
                    r = imagPart[0]
                    im = 0
                } else {
                    r = realPart[bin]
                    im = imagPart[bin]
                }
                magnitudes[bin][frame] = sqrt(r * r + im * im)
            }
        }

        // Create mel filterbank
        let melFilters = createMelFilterbank(
            nMels: nMels, nFFT: nFFT, sampleRate: sampleRate
        )

        // Apply mel filterbank: [nMels][nFrames]
        var melSpec = [[Float]](repeating: [Float](repeating: 0, count: nFrames), count: nMels)
        for mel in 0..<nMels {
            for frame in 0..<nFrames {
                var sum: Float = 0
                for bin in 0..<nBins {
                    sum += melFilters[mel][bin] * magnitudes[bin][frame]
                }
                // Log scale with floor to avoid log(0)
                melSpec[mel][frame] = log(max(sum, 1e-10))
            }
        }

        return melSpec
    }

    /// Spectral convergence: ratio of L2 norm of difference to L2 norm of reference.
    ///
    /// Lower is better. 0.0 = identical. Values > 1.0 indicate large divergence.
    public static func spectralConvergence(reference: [[Float]], test: [[Float]]) -> Float {
        // Align frame counts to the shorter
        let nMels = min(reference.count, test.count)
        let nFrames = min(
            reference.first?.count ?? 0,
            test.first?.count ?? 0
        )

        guard nMels > 0, nFrames > 0 else { return Float.infinity }

        var diffNormSq: Float = 0
        var refNormSq: Float = 0

        for mel in 0..<nMels {
            for frame in 0..<nFrames {
                let r = reference[mel][frame]
                let t = test[mel][frame]
                let d = t - r
                diffNormSq += d * d
                refNormSq += r * r
            }
        }

        guard refNormSq > 0 else { return Float.infinity }
        return sqrt(diffNormSq) / sqrt(refNormSq)
    }

    /// L2 distance between two mel-spectrograms (normalised by number of elements).
    public static func l2Distance(reference: [[Float]], test: [[Float]]) -> Float {
        let nMels = min(reference.count, test.count)
        let nFrames = min(
            reference.first?.count ?? 0,
            test.first?.count ?? 0
        )

        guard nMels > 0, nFrames > 0 else { return Float.infinity }

        var sumSq: Float = 0
        for mel in 0..<nMels {
            for frame in 0..<nFrames {
                let d = test[mel][frame] - reference[mel][frame]
                sumSq += d * d
            }
        }

        return sqrt(sumSq / Float(nMels * nFrames))
    }

    // MARK: - Mel filterbank

    private static func createMelFilterbank(nMels: Int, nFFT: Int, sampleRate: Int) -> [[Float]] {
        let nBins = nFFT / 2 + 1
        let fMax = Float(sampleRate) / 2.0

        // Mel scale conversion
        func hzToMel(_ hz: Float) -> Float { 2595.0 * log10(1.0 + hz / 700.0) }
        func melToHz(_ mel: Float) -> Float { 700.0 * (pow(10.0, mel / 2595.0) - 1.0) }

        let melMin = hzToMel(0)
        let melMax = hzToMel(fMax)

        // Equally spaced mel points
        var melPoints = [Float](repeating: 0, count: nMels + 2)
        for i in 0..<(nMels + 2) {
            melPoints[i] = melMin + Float(i) * (melMax - melMin) / Float(nMels + 1)
        }

        // Convert back to Hz and then to FFT bin indices
        let binPoints = melPoints.map { mel -> Int in
            let hz = melToHz(mel)
            return Int((hz / fMax) * Float(nBins - 1))
        }

        // Create triangular filters
        var filters = [[Float]](repeating: [Float](repeating: 0, count: nBins), count: nMels)
        for m in 0..<nMels {
            let left = binPoints[m]
            let center = binPoints[m + 1]
            let right = binPoints[m + 2]

            for bin in left..<center {
                if center > left {
                    filters[m][bin] = Float(bin - left) / Float(center - left)
                }
            }
            for bin in center..<right {
                if right > center {
                    filters[m][bin] = Float(right - bin) / Float(right - center)
                }
            }
        }

        return filters
    }
}
