import Foundation

/// Fetches plain-text summaries from the Wikipedia REST API for entity context.
enum WikipediaContext {

    /// Fetch a plain-text extract for an entity name. Returns nil if not found or on error.
    static func fetchSummary(for entityName: String) async -> String? {
        let encoded = entityName
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entityName
        let urlString = "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let extract = json["extract"] as? String,
                  !extract.isEmpty else {
                return nil
            }

            // Cap to ~200 words to keep chat context lean
            return truncateToWords(extract, maxWords: 200)
        } catch {
            return nil
        }
    }

    /// Detects if a user message is asking for background/context about an entity.
    static func isBackgroundQuestion(_ message: String) -> Bool {
        let lower = message.lowercased()
        let patterns = [
            "who is",
            "who are",
            "what is",
            "tell me about",
            "tell me more about",
            "what do you know about",
            "give me background",
            "background on",
            "what should i know about",
            "fill me in on",
        ]
        return patterns.contains { lower.contains($0) }
    }

    private static func truncateToWords(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ")
        if words.count <= maxWords { return text }
        let truncated = words.prefix(maxWords).joined(separator: " ")
        // End at sentence boundary if possible
        if let lastPeriod = truncated.lastIndex(of: ".") {
            return String(truncated[...lastPeriod])
        }
        return truncated + "..."
    }
}
