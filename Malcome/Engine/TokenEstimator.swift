import Foundation

enum MalcomeTokenEstimator {
    static let charsPerToken: Double = 3.5
    static let contextCeiling = 4096

    static func estimateTokens(from text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / charsPerToken)))
    }

    static func estimateChars(from tokens: Int) -> Int {
        Int(Double(tokens) * charsPerToken)
    }

    static func truncateAtSentenceBoundary(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let truncated = String(text.prefix(maxChars))
        // Only truncate at a real sentence boundary — never mid-sentence
        if let lastPeriod = truncated.lastIndex(of: ".") {
            return String(truncated[...lastPeriod])
        }
        // No sentence boundary found — return the full text rather than breaking mid-sentence
        return text
    }
}
