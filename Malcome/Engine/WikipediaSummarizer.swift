import Foundation
import NaturalLanguage
import FoundationModels

/// Compresses Wikipedia extracts using a two-stage pipeline:
/// Stage 1: AFM compresses the extract to a target word count
/// Stage 2: Each sentence is verified against the source using NLEmbedding similarity
/// Adapted from Hal's TextSummarizer with the same verify-against-source pattern.
enum WikipediaSummarizer {

    private static let verificationThreshold: Double = 0.72

    /// Compress a Wikipedia extract to approximately targetWords.
    /// Returns the verified summary, or a truncated fallback if AFM is unavailable.
    static func summarize(_ extract: String, targetWords: Int) async -> String {
        guard SystemLanguageModel.default.isAvailable else {
            return truncateToWords(extract, maxWords: targetWords)
        }

        // Stage 1: AFM compress
        let compressed = await afmCompress(extract, targetWords: targetWords)
        guard !compressed.isEmpty else {
            return truncateToWords(extract, maxWords: targetWords)
        }

        // Stage 2: Verify against source
        let sourceSentences = sentenceSplit(extract)
        let verified = verifyNarrative(compressed, against: sourceSentences)

        if verified.isEmpty {
            return truncateToWords(extract, maxWords: targetWords)
        }

        // Hard cap: if AFM exceeded target, truncate at sentence boundary
        let maxWords = targetWords + 25  // 25-word grace over target
        return truncateToWords(verified, maxWords: maxWords)
    }

    // MARK: - Stage 1: AFM Compression

    private static func afmCompress(_ text: String, targetWords: Int) async -> String {
        let prompt = """
        Compress this Wikipedia text to approximately \(targetWords) words. Maximum two sentences. Keep key names and dates. Do not add interpretation.

        Text: \(String(text.prefix(2000)))

        Compressed (\(targetWords) words, two sentences max):
        """

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }

    // MARK: - Stage 2: NLEmbedding Verification

    /// Verify each sentence in the summary is grounded in source text.
    /// Replaces ungrounded sentences with the nearest source sentence.
    private static func verifyNarrative(_ summary: String, against sourceSentences: [String]) -> String {
        let outputSentences = sentenceSplit(summary)
        guard !outputSentences.isEmpty, !sourceSentences.isEmpty else { return summary }

        // Try NLEmbedding sentence embeddings
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            // Fallback: return summary without verification (still better than nothing)
            return summary
        }

        // Precompute source vectors
        var sourceVecs: [[Double]] = []
        var sourceKeep: [String] = []
        for s in sourceSentences {
            if let v = embedding.vector(for: s) {
                sourceVecs.append(v)
                sourceKeep.append(s)
            }
        }
        guard !sourceVecs.isEmpty else { return summary }

        var verified: [String] = []

        for s in outputSentences {
            guard let v = embedding.vector(for: s) else {
                // Can't embed — keep the sentence (benefit of the doubt for Wikipedia content)
                verified.append(s)
                continue
            }

            var bestSim = -1.0
            var bestIdx = 0
            for (i, u) in sourceVecs.enumerated() {
                let sim = cosineSimilarity(v, u)
                if sim > bestSim {
                    bestSim = sim
                    bestIdx = i
                }
            }

            if bestSim >= verificationThreshold {
                verified.append(s)
            } else {
                // Replace with nearest grounded source sentence
                verified.append(sourceKeep[bestIdx])
            }
        }

        // Deduplicate adjacent repeats
        var dedup: [String] = []
        for s in verified {
            if dedup.last != s {
                dedup.append(s)
            }
        }

        return dedup.joined(separator: " ")
    }

    // MARK: - Helpers

    private static func sentenceSplit(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(s) }
            return true
        }
        return out
    }

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<n {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = na.squareRoot() * nb.squareRoot()
        return denom > 0 ? dot / denom : 0
    }

    private static func truncateToWords(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ")
        if words.count <= maxWords { return text }
        let truncated = words.prefix(maxWords).joined(separator: " ")
        if let lastPeriod = truncated.lastIndex(of: ".") {
            return String(truncated[...lastPeriod])
        }
        return truncated + "..."
    }
}
