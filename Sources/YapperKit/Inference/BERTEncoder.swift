// ABOUTME: ALBERT-based text encoder for the Kokoro-82M inference pipeline.
// ABOUTME: Produces contextual hidden states from phoneme token sequences.

import Foundation
import MLX
import MLXNN

// MARK: - ALBERT Model Arguments

/// Configuration for the ALBERT encoder, derived from KokoroConfig.PLBert.
struct AlbertModelArgs {
    let numHiddenLayers: Int
    let numAttentionHeads: Int
    let hiddenSize: Int
    let intermediateSize: Int
    let embeddingSize: Int
    let innerGroupNum: Int
    let numHiddenGroups: Int
    let layerNormEps: Float
    let vocabSize: Int
}

// MARK: - Self-Attention

/// Multi-head self-attention with pre-norm residual connection.
class AlbertSelfAttention {
    let numAttentionHeads: Int
    let attentionHeadSize: Int
    let allHeadSize: Int

    let query: Linear
    let key: Linear
    let value: Linear
    let dense: Linear
    let layerNorm: LayerNorm

    init(weights: [String: MLXArray], config: AlbertModelArgs, layerNum: Int, innerGroupNum: Int) {
        numAttentionHeads = config.numAttentionHeads
        attentionHeadSize = config.hiddenSize / config.numAttentionHeads
        allHeadSize = numAttentionHeads * attentionHeadSize

        let pfx = "bert.encoder.albert_layer_groups.\(layerNum).albert_layers.\(innerGroupNum)"
        query = Linear(weight: weights["\(pfx).attention.query.weight"]!, bias: weights["\(pfx).attention.query.bias"]!)
        key = Linear(weight: weights["\(pfx).attention.key.weight"]!, bias: weights["\(pfx).attention.key.bias"]!)
        value = Linear(weight: weights["\(pfx).attention.value.weight"]!, bias: weights["\(pfx).attention.value.bias"])
        dense = Linear(weight: weights["\(pfx).attention.dense.weight"]!, bias: weights["\(pfx).attention.dense.bias"]!)

        layerNorm = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        let lnW = weights["\(pfx).attention.LayerNorm.weight"]!
        let lnB = weights["\(pfx).attention.LayerNorm.bias"]!
        for i in 0 ..< config.hiddenSize {
            layerNorm.weight![i] = lnW[i]
            layerNorm.bias![i] = lnB[i]
        }
    }

    private func transposeForScores(_ x: MLXArray) -> MLXArray {
        var newShape = Array(x.shape.dropLast())
        newShape.append(numAttentionHeads)
        newShape.append(attentionHeadSize)
        return x.reshaped(newShape).transposed(0, 2, 1, 3)
    }

    func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray?) -> MLXArray {
        let q = transposeForScores(query(hiddenStates))
        let k = transposeForScores(key(hiddenStates))
        let v = transposeForScores(value(hiddenStates))

        var scores = MLX.matmul(q, k.transposed(0, 1, 3, 2))
        let scaleFactor = Float(1.0) / sqrtf(Float(attentionHeadSize))
        scores = scores * scaleFactor

        if let mask = attentionMask {
            scores = scores + mask
        }

        let probs = MLX.softmax(scores, axis: -1)
        var context = MLX.matmul(probs, v)
        context = context.transposed(0, 2, 1, 3)

        var flatShape = Array(context.shape.dropLast(2))
        flatShape.append(allHeadSize)
        context = context.reshaped(flatShape)
        context = dense(context)
        return layerNorm(context + hiddenStates)
    }
}

// MARK: - Transformer Layer

/// Single ALBERT transformer layer: self-attention + FFN + layer norm.
class AlbertLayer {
    let attention: AlbertSelfAttention
    let ffn: Linear
    let ffnOutput: Linear
    let fullLayerLayerNorm: LayerNorm

    init(weights: [String: MLXArray], config: AlbertModelArgs, layerNum: Int, innerGroupNum: Int) {
        attention = AlbertSelfAttention(weights: weights, config: config, layerNum: layerNum, innerGroupNum: innerGroupNum)

        let pfx = "bert.encoder.albert_layer_groups.\(layerNum).albert_layers.\(innerGroupNum)"
        ffn = Linear(weight: weights["\(pfx).ffn.weight"]!, bias: weights["\(pfx).ffn.bias"]!)
        ffnOutput = Linear(weight: weights["\(pfx).ffn_output.weight"]!, bias: weights["\(pfx).ffn_output.bias"]!)

        fullLayerLayerNorm = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        let lnW = weights["\(pfx).full_layer_layer_norm.weight"]!
        let lnB = weights["\(pfx).full_layer_layer_norm.bias"]!
        for i in 0 ..< config.hiddenSize {
            fullLayerLayerNorm.weight![i] = lnW[i]
            fullLayerLayerNorm.bias![i] = lnB[i]
        }
    }

    func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray?) -> MLXArray {
        let attOut = attention(hiddenStates, attentionMask: attentionMask)
        var h = ffn(attOut)
        h = MLXNN.gelu(h)
        h = ffnOutput(h)
        return fullLayerLayerNorm(h + attOut)
    }
}

// MARK: - Layer Group

/// A group of ALBERT layers that share parameters.
class AlbertLayerGroup {
    let layers: [AlbertLayer]

    init(config: AlbertModelArgs, layerNum: Int, weights: [String: MLXArray]) {
        var l: [AlbertLayer] = []
        for inner in 0 ..< config.innerGroupNum {
            l.append(AlbertLayer(weights: weights, config: config, layerNum: layerNum, innerGroupNum: inner))
        }
        layers = l
    }

    func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray?) -> MLXArray {
        var h = hiddenStates
        for layer in layers {
            h = layer(h, attentionMask: attentionMask)
        }
        return h
    }
}

// MARK: - Embeddings

/// ALBERT embeddings: word + position + token type, followed by layer norm.
class AlbertEmbeddings {
    let wordEmbeddings: Embedding
    let positionEmbeddings: Embedding
    let tokenTypeEmbeddings: Embedding
    let layerNorm: LayerNorm

    init(weights: [String: MLXArray], config: AlbertModelArgs) {
        wordEmbeddings = Embedding(weight: weights["bert.embeddings.word_embeddings.weight"]!)
        positionEmbeddings = Embedding(weight: weights["bert.embeddings.position_embeddings.weight"]!)
        tokenTypeEmbeddings = Embedding(weight: weights["bert.embeddings.token_type_embeddings.weight"]!)

        layerNorm = LayerNorm(dimensions: config.embeddingSize, eps: config.layerNormEps)
        let lnW = weights["bert.embeddings.LayerNorm.weight"]!
        let lnB = weights["bert.embeddings.LayerNorm.bias"]!
        for i in 0 ..< config.embeddingSize {
            layerNorm.weight![i] = lnW[i]
            layerNorm.bias![i] = lnB[i]
        }
    }

    func callAsFunction(_ inputIds: MLXArray) -> MLXArray {
        let seqLen = inputIds.shape[1]
        let posIds = MLX.expandedDimensions(MLXArray(0 ..< seqLen), axes: [0])
        let tokenTypeIds = MLXArray.zeros(like: inputIds)

        var emb = wordEmbeddings(inputIds)
        emb = emb + positionEmbeddings(posIds)
        emb = emb + tokenTypeEmbeddings(tokenTypeIds)
        return layerNorm(emb)
    }
}

// MARK: - ALBERT Encoder

/// Full ALBERT encoder: embeddings -> hidden mapping -> N transformer layers.
class AlbertEncoder {
    let config: AlbertModelArgs
    let embeddingHiddenMapping: Linear
    let layerGroups: [AlbertLayerGroup]

    init(weights: [String: MLXArray], config: AlbertModelArgs) {
        self.config = config
        embeddingHiddenMapping = Linear(
            weight: weights["bert.encoder.embedding_hidden_mapping_in.weight"]!,
            bias: weights["bert.encoder.embedding_hidden_mapping_in.bias"]!
        )

        var groups: [AlbertLayerGroup] = []
        for g in 0 ..< config.numHiddenGroups {
            groups.append(AlbertLayerGroup(config: config, layerNum: g, weights: weights))
        }
        layerGroups = groups
    }

    func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray?) -> MLXArray {
        var h = embeddingHiddenMapping(hiddenStates)
        for i in 0 ..< config.numHiddenLayers {
            let groupIdx = i / (config.numHiddenLayers / config.numHiddenGroups)
            h = layerGroups[groupIdx](h, attentionMask: attentionMask)
        }
        return h
    }
}

// MARK: - Custom ALBERT (BERT Encoder)

/// The complete ALBERT model used as the BERT text encoder in Kokoro.
///
/// Takes padded token IDs and an attention mask, returns sequence-level
/// hidden states used by downstream duration/prosody predictors.
class BERTModel {
    let embeddings: AlbertEmbeddings
    let encoder: AlbertEncoder
    let pooler: Linear

    init(weights: [String: MLXArray], config: AlbertModelArgs) {
        embeddings = AlbertEmbeddings(weights: weights, config: config)
        encoder = AlbertEncoder(weights: weights, config: config)
        pooler = Linear(weight: weights["bert.pooler.weight"]!, bias: weights["bert.pooler.bias"]!)
    }

    /// Run the BERT encoder.
    ///
    /// - Parameters:
    ///   - inputIds: padded token IDs [batch, seqLen]
    ///   - attentionMask: 1 for real tokens, 0 for padding [batch, seqLen]
    /// - Returns: sequence output [batch, seqLen, hiddenSize]
    func callAsFunction(_ inputIds: MLXArray, attentionMask: MLXArray) -> MLXArray {
        let embOut = embeddings(inputIds)

        // Reshape attention mask for multi-head attention broadcasting
        let shape = attentionMask.shape
        let mask4d = attentionMask.reshaped([shape[0], 1, 1, shape[1]])
        let processedMask = (1.0 - mask4d) * -10000.0

        return encoder(embOut, attentionMask: processedMask)
    }
}

/// Projects BERT output to the model's hidden dimension.
///
/// BERT produces 768-dim embeddings; downstream layers expect 512-dim (hiddenDim).
/// This linear projection bridges the gap.
class BERTProjection {
    let linear: Linear

    init(weights: [String: MLXArray]) {
        linear = Linear(
            weight: weights["bert_encoder.weight"]!,
            bias: weights["bert_encoder.bias"]!
        )
    }

    /// Project BERT output from 768-dim to 512-dim.
    ///
    /// - Parameter x: BERT hidden states [batch, seqLen, 768]
    /// - Returns: projected states [batch, seqLen, 512]
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        return linear(x)
    }
}
