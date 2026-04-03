// ABOUTME: StyleTTS2 decoder and HiFi-GAN generator for Kokoro-82M audio synthesis.
// ABOUTME: Converts aligned features + prosody into raw PCM waveform via iSTFT.

import Foundation
import MLX
import MLXNN
import MLXRandom

// MARK: - Conv helpers

/// Apply a ConvWeighted as a transposed convolution.
///
/// Our ConvWeighted building block only supports forward conv1d.
/// The HiFi-GAN generator needs transposed conv for upsampling.
/// This helper computes the weight-normalised kernel and calls convTransposed1d.
///
/// Input: [batch, channels, seqLen] (channels-first)
/// Output: [batch, outChannels, seqLen'] (channels-first)
func applyConvTransposed(_ x: MLXArray, conv: ConvWeighted) -> MLXArray {
    let vNorm = MLXLinalg.norm(conv.weightV, axes: [1, 2], keepDims: true)
    var w = (conv.weightV / vNorm) * conv.weightG
    // After WeightLoader sanitisation, regular weights are [inCh, kernel, outCh]
    // MLX needs [outCh, kernel, inCh] = transposed(2, 1, 0)
    // For depthwise (groups>1), already correct after sanitisation
    if conv.groups <= 1 {
        w = w.transposed(2, 1, 0)
    }
    let xCL = x.transposed(0, 2, 1)
    var y = convTransposed1d(xCL, w, stride: conv.stride, padding: conv.padding, dilation: conv.dilation, groups: conv.groups)
    if let bias = conv.bias {
        y = y + bias
    }
    return y.transposed(0, 2, 1)
}

// MARK: - Interpolation helper

/// 1D linear or nearest interpolation for upsampling/downsampling tensors.
///
/// Input shape: [batch, channels, width].
/// Supports "nearest" and "linear" modes.
func interpolate1d(
    _ input: MLXArray,
    scaleFactor: Float,
    mode: String = "nearest"
) -> MLXArray {
    let inWidth = input.shape[2]
    let outWidth = max(1, Int(Foundation.ceil(Double(inWidth) * Double(scaleFactor))))

    if mode == "nearest" {
        let scale = Float(inWidth) / Float(outWidth)
        let indices = MLX.floor(MLXArray(0 ..< outWidth).asType(.float32) * scale).asType(.int32)
        let clipped = MLX.clip(indices, min: 0, max: inWidth - 1)
        return input[0..., 0..., clipped]
    }

    // Linear interpolation
    var x = MLXArray(0 ..< outWidth).asType(.float32) * (Float(inWidth) / Float(outWidth))
    x = x + 0.5 * (Float(inWidth) / Float(outWidth)) - 0.5

    if inWidth == 1 {
        return MLX.broadcast(input, to: [input.shape[0], input.shape[1], outWidth])
    }

    let xLow = MLX.floor(x).asType(.int32)
    let xHigh = MLX.minimum(xLow + 1, MLXArray(inWidth - 1, dtype: .int32))
    let xFrac = x - xLow.asType(.float32)

    let yLow = input[0..., 0..., xLow]
    let yHigh = input[0..., 0..., xHigh]

    let fracExp = xFrac.expandedDimensions(axis: 0).expandedDimensions(axis: 0)
    let oneMinusFrac = MLXArray(1.0) - fracExp
    return yLow * oneMinusFrac + yHigh * fracExp
}

// MARK: - Sine Generator

/// Generates harmonic sine waveforms from F0 (fundamental frequency) values.
///
/// Used by the neural source filter (NSF) module to create excitation signals
/// that drive the HiFi-GAN generator.
class SineGen {
    let sineAmp: Float
    let noiseStd: Float
    let harmonicNum: Int
    let samplingRate: Int
    let voicedThreshold: Float
    let upsampleScale: Float

    init(
        samplingRate: Int,
        upsampleScale: Float,
        harmonicNum: Int = 0,
        sineAmp: Float = 0.1,
        noiseStd: Float = 0.003,
        voicedThreshold: Float = 0
    ) {
        self.sineAmp = sineAmp
        self.noiseStd = noiseStd
        self.harmonicNum = harmonicNum
        self.samplingRate = samplingRate
        self.voicedThreshold = voicedThreshold
        self.upsampleScale = upsampleScale
    }

    /// Convert F0 values to voiced/unvoiced mask.
    private func f02uv(_ f0: MLXArray) -> MLXArray {
        return (f0 .> voicedThreshold).asType(.float32)
    }

    /// Convert F0 values to sine waveforms via phase accumulation.
    private func f02sine(_ f0Values: MLXArray) -> MLXArray {
        let origLen = f0Values.shape[1]

        // Normalise frequency: f0 / samplingRate, modulo 1
        var radValues = (f0Values / Float(samplingRate)) % 1

        // Random phase initialisation
        let randInit = MLXRandom.normal([f0Values.shape[0], f0Values.shape[2]])
        randInit[0..., 0] = MLXArray(0.0)
        radValues[0 ..< radValues.shape[0], 0, 0 ..< radValues.shape[2]] =
            radValues[0 ..< radValues.shape[0], 0, 0 ..< radValues.shape[2]] + randInit

        // Interpolate down then accumulate phase then interpolate back up
        radValues = interpolate1d(
            radValues.transposed(0, 2, 1),
            scaleFactor: 1 / upsampleScale,
            mode: "linear"
        ).transposed(0, 2, 1)

        var phase = MLX.cumsum(radValues, axis: 1) * 2 * Float.pi
        phase = interpolate1d(
            phase.transposed(0, 2, 1) * upsampleScale,
            scaleFactor: upsampleScale,
            mode: "linear"
        ).transposed(0, 2, 1)

        // Truncate to original length (interpolation can round up)
        if phase.shape[1] > origLen {
            phase = phase[0..., 0 ..< origLen, 0...]
        }

        return MLX.sin(phase)
    }

    /// Generate sine excitation signal.
    ///
    /// - Parameter f0: fundamental frequency [batch, frames, 1]
    /// - Returns: (merged sine, noise, voiced/unvoiced mask)
    func callAsFunction(_ f0: MLXArray) -> (MLXArray, MLXArray, MLXArray) {
        let range = MLXArray(1 ... harmonicNum + 1).asType(.float32)
        let fn = f0 * range.reshaped([1, 1, range.shape[0]])
        let sineWaves = f02sine(fn) * sineAmp
        let uv = f02uv(f0)

        let noiseAmp = uv * noiseStd + (1 - uv) * sineAmp / 3
        let noise = noiseAmp * MLXRandom.normal(sineWaves.shape)
        let result = sineWaves * uv + noise
        return (result, uv, noise)
    }
}

// MARK: - Source Module (Neural Source Filter)

/// Harmonic-plus-noise source module that generates excitation signals.
///
/// Produces sine-based excitation from F0, merges harmonics via a linear layer.
class SourceModuleHnNSF {
    let sineAmp: Float
    let sineGen: SineGen
    let linear: Linear

    init(weights: [String: MLXArray], samplingRate: Int, upsampleScale: Float) {
        sineAmp = 0.1
        sineGen = SineGen(
            samplingRate: samplingRate,
            upsampleScale: upsampleScale,
            harmonicNum: 8,
            sineAmp: 0.1,
            noiseStd: 0.003,
            voicedThreshold: 10
        )
        linear = Linear(
            weight: weights["decoder.generator.m_source.l_linear.weight"]!,
            bias: weights["decoder.generator.m_source.l_linear.bias"]!
        )
    }

    func callAsFunction(_ x: MLXArray) -> (MLXArray, MLXArray, MLXArray) {
        let (sineWavs, uv, _) = sineGen(x)
        let sineMerge = tanh(linear(sineWavs))
        let noise = MLXRandom.normal(uv.shape) * (sineAmp / 3)
        return (sineMerge, noise, uv)
    }
}

// MARK: - HiFi-GAN Generator

/// HiFi-GAN generator with neural source filtering and AdaIN conditioning.
///
/// Takes encoded features from the decoder, generates harmonic excitation from F0,
/// upsamples through transposed convolutions with AdaINResBlock1 refinement,
/// and produces magnitude/phase via the final convolution that feeds into iSTFT.
class Generator {
    let numKernels: Int
    let numUpsamples: Int
    let mSource: SourceModuleHnNSF
    let f0Upsample: Upsample
    let postNFft: Int
    let noiseConvs: [Conv1dInference]
    let noiseRes: [AdaINResBlock1]
    let ups: [ConvWeighted]
    let resBlocks: [AdaINResBlock1]
    let convPost: ConvWeighted
    let stft: MLXSTFT

    init(
        weights: [String: MLXArray],
        styleDim: Int,
        resblockKernelSizes: [Int],
        upsampleRates: [Int],
        upsampleInitialChannel: Int,
        resblockDilationSizes: [[Int]],
        upsampleKernelSizes: [Int],
        genIstftNFft: Int,
        genIstftHopSize: Int
    ) {
        numKernels = resblockKernelSizes.count
        numUpsamples = upsampleRates.count

        let upsampleScaleProduct = upsampleRates.reduce(1, *)
        let totalUpsampleScale = upsampleScaleProduct * genIstftHopSize

        mSource = SourceModuleHnNSF(
            weights: weights,
            samplingRate: 24000,
            upsampleScale: Float(totalUpsampleScale)
        )

        f0Upsample = Upsample(scaleFactor: .float(Float(totalUpsampleScale)))
        postNFft = genIstftNFft

        // Build upsample convolutions
        var upsArr: [ConvWeighted] = []
        for (i, (u, k)) in zip(upsampleRates, upsampleKernelSizes).enumerated() {
            upsArr.append(ConvWeighted(
                weightG: weights["decoder.generator.ups.\(i).weight_g"]!,
                weightV: weights["decoder.generator.ups.\(i).weight_v"]!,
                bias: weights["decoder.generator.ups.\(i).bias"]!,
                stride: u,
                padding: (k - u) / 2
            ))
        }
        ups = upsArr

        // Build residual blocks and noise convolutions
        var resArr: [AdaINResBlock1] = []
        var ncArr: [Conv1dInference] = []
        var nrArr: [AdaINResBlock1] = []

        for i in 0 ..< upsArr.count {
            let ch = upsampleInitialChannel / (1 << (i + 1))

            for (j, (k, d)) in zip(resblockKernelSizes, resblockDilationSizes).enumerated() {
                let idx = i * resblockKernelSizes.count + j
                resArr.append(Self.buildAdaINResBlock1(
                    weights: weights,
                    prefix: "decoder.generator.resblocks.\(idx)",
                    channels: ch,
                    kernelSize: k,
                    dilations: d,
                    styleDim: styleDim
                ))
            }

            // Noise convolution and residual
            if i + 1 < upsampleRates.count {
                let strideF0 = upsampleRates[(i + 1)...].reduce(1, *)
                ncArr.append(Conv1dInference(
                    weight: weights["decoder.generator.noise_convs.\(i).weight"]!,
                    bias: weights["decoder.generator.noise_convs.\(i).bias"]!,
                    stride: strideF0,
                    padding: (strideF0 + 1) / 2
                ))
                nrArr.append(Self.buildAdaINResBlock1(
                    weights: weights,
                    prefix: "decoder.generator.noise_res.\(i)",
                    channels: ch,
                    kernelSize: 7,
                    dilations: [1, 3, 5],
                    styleDim: styleDim
                ))
            } else {
                ncArr.append(Conv1dInference(
                    weight: weights["decoder.generator.noise_convs.\(i).weight"]!,
                    bias: weights["decoder.generator.noise_convs.\(i).bias"]!
                ))
                nrArr.append(Self.buildAdaINResBlock1(
                    weights: weights,
                    prefix: "decoder.generator.noise_res.\(i)",
                    channels: ch,
                    kernelSize: 11,
                    dilations: [1, 3, 5],
                    styleDim: styleDim
                ))
            }
        }

        resBlocks = resArr
        noiseConvs = ncArr
        noiseRes = nrArr

        convPost = ConvWeighted(
            weightG: weights["decoder.generator.conv_post.weight_g"]!,
            weightV: weights["decoder.generator.conv_post.weight_v"]!,
            bias: weights["decoder.generator.conv_post.bias"]!,
            padding: 3
        )

        stft = MLXSTFT(filterLength: genIstftNFft, hopLength: genIstftHopSize, winLength: genIstftNFft)
    }

    /// Build an AdaINResBlock1 from weights.
    private static func buildAdaINResBlock1(
        weights: [String: MLXArray],
        prefix: String,
        channels: Int,
        kernelSize: Int,
        dilations: [Int],
        styleDim: Int
    ) -> AdaINResBlock1 {
        var convs1: [ConvWeighted] = []
        var convs2: [ConvWeighted] = []
        var adain1: [AdaIN1d] = []
        var adain2: [AdaIN1d] = []
        var alpha1: [MLXArray] = []
        var alpha2: [MLXArray] = []

        let padding = (kernelSize - 1) / 2
        for (i, d) in dilations.enumerated() {
            convs1.append(ConvWeighted(
                weightG: weights["\(prefix).convs1.\(i).weight_g"]!,
                weightV: weights["\(prefix).convs1.\(i).weight_v"]!,
                bias: weights["\(prefix).convs1.\(i).bias"]!,
                padding: d * padding,
                dilation: d
            ))
            convs2.append(ConvWeighted(
                weightG: weights["\(prefix).convs2.\(i).weight_g"]!,
                weightV: weights["\(prefix).convs2.\(i).weight_v"]!,
                bias: weights["\(prefix).convs2.\(i).bias"]!,
                padding: padding
            ))
            adain1.append(AdaIN1d(
                fcWeight: weights["\(prefix).adain1.\(i).fc.weight"]!,
                fcBias: weights["\(prefix).adain1.\(i).fc.bias"]!,
                numFeatures: channels
            ))
            adain2.append(AdaIN1d(
                fcWeight: weights["\(prefix).adain2.\(i).fc.weight"]!,
                fcBias: weights["\(prefix).adain2.\(i).fc.bias"]!,
                numFeatures: channels
            ))
            alpha1.append(weights["\(prefix).alpha1.\(i)"]!)
            alpha2.append(weights["\(prefix).alpha2.\(i)"]!)
        }

        return AdaINResBlock1(
            convs1: convs1, convs2: convs2,
            adain1: adain1, adain2: adain2,
            alpha1: alpha1, alpha2: alpha2
        )
    }

    /// Generate audio from encoded features and F0 curve.
    ///
    /// - Parameters:
    ///   - x: decoder output [batch, channels, seqLen]
    ///   - s: acoustic style [batch, styleDim]
    ///   - f0Curve: predicted F0 [batch, timeSteps]
    /// - Returns: PCM audio [batch, 1, length]
    func callAsFunction(_ x: MLXArray, _ s: MLXArray, _ f0Curve: MLXArray) -> MLXArray {
        // Upsample F0 and generate harmonic source
        var f0New = f0Curve[.newAxis, 0..., 0...].transposed(0, 2, 1)
        f0New = f0Upsample(f0New)

        var (harSource, _, _) = mSource(f0New)
        harSource = MLX.squeezed(harSource.transposed(0, 2, 1), axis: 1)
        let (harSpec, harPhase) = stft.transform(inputData: harSource)

        let har = MLX.concatenated([harSpec, harPhase], axis: 1)

        var h = x
        for i in 0 ..< numUpsamples {
            h = leakyRelu(h, negativeSlope: 0.1)

            // Process noise/harmonic source
            var xSource = noiseConvs[i](har)
            xSource = noiseRes[i](xSource, style: s)

            // Upsample via transposed convolution (using ups[i] weight-normalised kernel)
            h = applyConvTransposed(h, conv: ups[i])

            // Reflection pad before last upsample
            if i == numUpsamples - 1 {
                h = MLX.padded(h, widths: [IntOrPair([0, 0]), IntOrPair([0, 0]), IntOrPair([1, 0])])
            }

            h = h + xSource

            // Multi-kernel residual
            var xs: MLXArray? = nil
            for j in 0 ..< numKernels {
                let block = resBlocks[i * numKernels + j]
                if xs == nil {
                    xs = block(h, style: s)
                } else {
                    xs = xs! + block(h, style: s)
                }
            }
            h = xs! / Float(numKernels)
        }

        h = leakyRelu(h, negativeSlope: 0.01)

        // Final convolution (ConvWeighted handles channels-first internally)
        h = convPost(h)

        // Split into magnitude and phase, apply exp/sin, and run iSTFT
        let spec = MLX.exp(h[0..., 0 ..< (postNFft / 2 + 1), 0...])
        let phase = MLX.sin(h[0..., (postNFft / 2 + 1)..., 0...])

        return stft.inverse(magnitude: spec, phase: phase)
    }
}

// MARK: - Upsample helper for AdainResBlk1d in decoder context

/// Nearest-neighbour 1D upsampling by factor of 2.
///
/// Used by the decoder's AdainResBlk1d blocks for shortcut upsampling.
func upsample2x(_ x: MLXArray) -> MLXArray {
    return interpolate1d(x, scaleFactor: 2.0, mode: "nearest")
}

// MARK: - Main Decoder

/// The Kokoro decoder: takes ASR features, F0, N, and style embedding,
/// produces raw audio via the HiFi-GAN generator.
///
/// Architecture:
/// 1. Downsample F0 and N curves via strided convolutions
/// 2. Concatenate with ASR features
/// 3. Encode through an AdainResBlk1d
/// 4. Decode through 4 AdainResBlk1d blocks (last one upsamples)
/// 5. Generate audio via HiFi-GAN generator with iSTFT
class KokoroDecoder {
    let encode: AdainResBlk1d
    let decode: [AdainResBlk1d]
    let f0Conv: ConvWeighted
    let nConv: ConvWeighted
    let asrRes: ConvWeighted
    let generator: Generator

    /// Whether each decode block has upsampling (last block does).
    let decodeHasUpsample: [Bool]

    init(
        weights: [String: MLXArray],
        dimIn: Int,
        styleDim: Int,
        resblockKernelSizes: [Int],
        upsampleRates: [Int],
        upsampleInitialChannel: Int,
        resblockDilationSizes: [[Int]],
        upsampleKernelSizes: [Int],
        genIstftNFft: Int,
        genIstftHopSize: Int
    ) {
        encode = Self.buildAdainResBlk1d(
            weights: weights,
            prefix: "decoder.encode",
            dimIn: dimIn + 2,
            dimOut: 1024,
            styleDim: styleDim
        )

        var decBlocks: [AdainResBlk1d] = []
        var hasUpsample: [Bool] = []
        // Blocks 0-2: no upsample; block 3: upsample
        for i in 0 ..< 4 {
            let isLast = (i == 3)
            let outDim = isLast ? 512 : 1024
            let inDim = 1024 + 2 + 64
            decBlocks.append(Self.buildAdainResBlk1d(
                weights: weights,
                prefix: "decoder.decode.\(i)",
                dimIn: inDim,
                dimOut: outDim,
                styleDim: styleDim,
                upsample: isLast
            ))
            hasUpsample.append(isLast)
        }
        decode = decBlocks
        decodeHasUpsample = hasUpsample

        f0Conv = ConvWeighted(
            weightG: weights["decoder.F0_conv.weight_g"]!,
            weightV: weights["decoder.F0_conv.weight_v"]!,
            bias: weights["decoder.F0_conv.bias"]!,
            stride: 2,
            padding: 1
        )

        nConv = ConvWeighted(
            weightG: weights["decoder.N_conv.weight_g"]!,
            weightV: weights["decoder.N_conv.weight_v"]!,
            bias: weights["decoder.N_conv.bias"]!,
            stride: 2,
            padding: 1
        )

        asrRes = ConvWeighted(
            weightG: weights["decoder.asr_res.0.weight_g"]!,
            weightV: weights["decoder.asr_res.0.weight_v"]!,
            bias: weights["decoder.asr_res.0.bias"]!
        )

        generator = Generator(
            weights: weights,
            styleDim: styleDim,
            resblockKernelSizes: resblockKernelSizes,
            upsampleRates: upsampleRates,
            upsampleInitialChannel: upsampleInitialChannel,
            resblockDilationSizes: resblockDilationSizes,
            upsampleKernelSizes: upsampleKernelSizes,
            genIstftNFft: genIstftNFft,
            genIstftHopSize: genIstftHopSize
        )
    }

    /// Build an AdainResBlk1d for the decoder.
    private static func buildAdainResBlk1d(
        weights: [String: MLXArray],
        prefix: String,
        dimIn: Int,
        dimOut: Int,
        styleDim: Int,
        upsample: Bool = false
    ) -> AdainResBlk1d {
        let pool: ConvTransposedWeighted? = upsample
            ? ConvTransposedWeighted(
                weightG: weights["\(prefix).pool.weight_g"]!,
                weightV: weights["\(prefix).pool.weight_v"]!,
                bias: weights["\(prefix).pool.bias"]!,
                stride: 2,
                padding: 1,
                groups: dimIn
            )
            : nil

        let conv1x1: ConvWeighted? = (dimIn != dimOut)
            ? ConvWeighted(
                weightG: weights["\(prefix).conv1x1.weight_g"]!,
                weightV: weights["\(prefix).conv1x1.weight_v"]!
            )
            : nil

        return AdainResBlk1d(
            conv1: ConvWeighted(
                weightG: weights["\(prefix).conv1.weight_g"]!,
                weightV: weights["\(prefix).conv1.weight_v"]!,
                bias: weights["\(prefix).conv1.bias"]!,
                padding: 1
            ),
            conv2: ConvWeighted(
                weightG: weights["\(prefix).conv2.weight_g"]!,
                weightV: weights["\(prefix).conv2.weight_v"]!,
                bias: weights["\(prefix).conv2.bias"]!,
                padding: 1
            ),
            norm1: AdaIN1d(
                fcWeight: weights["\(prefix).norm1.fc.weight"]!,
                fcBias: weights["\(prefix).norm1.fc.bias"]!,
                numFeatures: dimIn
            ),
            norm2: AdaIN1d(
                fcWeight: weights["\(prefix).norm2.fc.weight"]!,
                fcBias: weights["\(prefix).norm2.fc.bias"]!,
                numFeatures: dimIn
            ),
            pool: pool,
            conv1x1: conv1x1
        )
    }

    /// Run the decoder.
    ///
    /// - Parameters:
    ///   - asr: text-encoded features [batch, channels, seqLen]
    ///   - f0Curve: predicted F0 [batch, timeSteps]
    ///   - n: predicted voicing [batch, timeSteps]
    ///   - style: acoustic style embedding [batch, styleDim]
    /// - Returns: PCM audio [batch, 1, length]
    func callAsFunction(asr: MLXArray, f0Curve: MLXArray, n: MLXArray, style: MLXArray) -> MLXArray {
        // Downsample F0 and N via strided conv (ConvWeighted handles channels-first internally)
        let f0Reshaped = f0Curve.reshaped([f0Curve.shape[0], 1, f0Curve.shape[1]])
        let f0Down = f0Conv(f0Reshaped)

        let nReshaped = n.reshaped([n.shape[0], 1, n.shape[1]])
        let nDown = nConv(nReshaped)

        // Concatenate ASR features with F0 and N
        var x = MLX.concatenated([asr, f0Down, nDown], axis: 1)

        // Encode
        x = encode(x, style: style)

        // ASR residual for skip connections (ConvWeighted handles channels-first internally)
        let asrResidual = asrRes(asr)

        // Decode with skip connections (until first upsample block)
        var addResidual = true
        for (i, block) in decode.enumerated() {
            if addResidual {
                x = MLX.concatenated([x, asrResidual, f0Down, nDown], axis: 1)
            }
            x = block(x, style: style)
            if decodeHasUpsample[i] {
                addResidual = false
            }
        }

        // Generate audio
        return generator(x, style, f0Curve)
    }
}
