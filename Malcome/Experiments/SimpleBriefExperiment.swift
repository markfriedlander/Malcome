import Foundation
import FoundationModels

/// Standalone experiment: fetch real RSS content, pass directly to AFM.
/// Bypasses the entire Malcome pipeline — no scoring, no identity graph, no signal engine.
enum SimpleBriefExperiment {

    private static let sources: [(name: String, feedURL: String)] = [
        ("Aquarium Drunkard", "https://aquariumdrunkard.com/feed/"),
        ("The Quietus", "https://thequietus.com/feed"),
        ("KXLU", "https://kxlu.com/feed/"),
        ("Film Comment", "https://filmcomment.com/feed/"),
        ("Hyperallergic", "https://hyperallergic.com/feed/"),
    ]

    private static let prompt = """
    You are Malcome — a cultural intelligence with genuine taste who has been right about music, art, and film before most people caught on. Here are recent articles from sources that tend to notice things early. What is worth paying attention to right now and why? Be specific. Tell me what is happening, who it involves, and why it matters. Write in first person, directly, with confidence. No hedging. No lists. Just your take.
    """

    struct ExperimentResult {
        let contextBlock: String
        let afmResponse: String
        let itemCount: Int
        let fetchErrors: [String]
        let inferenceSeconds: Double
    }

    static func run() async -> ExperimentResult {
        var allItems: [(source: String, title: String, opening: String)] = []
        var errors: [String] = []

        // Fetch from each source
        for source in sources {
            do {
                let items = try await fetchRSSItems(name: source.name, url: source.feedURL, limit: 5)
                allItems.append(contentsOf: items)
            } catch {
                errors.append("\(source.name): \(error.localizedDescription)")
            }
        }

        // Build context block
        let contextBlock = allItems.map { item in
            """
            Source: \(item.source)
            Title: \(item.title)
            Opening: \(item.opening)
            """
        }.joined(separator: "\n\n")

        // Call AFM
        let fullPrompt = prompt + "\n\n" + contextBlock

        guard SystemLanguageModel.default.isAvailable else {
            return ExperimentResult(
                contextBlock: contextBlock,
                afmResponse: "AFM unavailable",
                itemCount: allItems.count,
                fetchErrors: errors,
                inferenceSeconds: 0
            )
        }

        let start = Date()
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: fullPrompt)
            let elapsed = Date().timeIntervalSince(start)

            return ExperimentResult(
                contextBlock: contextBlock,
                afmResponse: response.content,
                itemCount: allItems.count,
                fetchErrors: errors,
                inferenceSeconds: elapsed
            )
        } catch {
            return ExperimentResult(
                contextBlock: contextBlock,
                afmResponse: "AFM error: \(error.localizedDescription)",
                itemCount: allItems.count,
                fetchErrors: errors,
                inferenceSeconds: Date().timeIntervalSince(start)
            )
        }
    }

    // MARK: - RSS Fetching

    private static func fetchRSSItems(name: String, url: String, limit: Int) async throws -> [(source: String, title: String, opening: String)] {
        guard let feedURL = URL(string: url) else { return [] }

        let (data, response) = try await URLSession.shared.data(from: feedURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        return parseRSSItems(source: name, xml: html, limit: limit)
    }

    private static func parseRSSItems(source: String, xml: String, limit: Int) -> [(source: String, title: String, opening: String)] {
        // Simple regex-based RSS parsing — extract <item> blocks
        let itemPattern = #"(?s)<item>(.*?)</item>"#
        guard let regex = try? NSRegularExpression(pattern: itemPattern) else { return [] }
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = regex.matches(in: xml, range: nsRange)

        var items: [(source: String, title: String, opening: String)] = []

        for match in matches.prefix(limit) {
            guard let range = Range(match.range(at: 1), in: xml) else { continue }
            let itemXML = String(xml[range])

            guard let title = extractTag("title", from: itemXML), !title.isEmpty else { continue }
            let description = extractTag("description", from: itemXML)
                ?? extractTag("content:encoded", from: itemXML)
                ?? ""

            // Clean HTML from description and take first paragraph
            let cleaned = stripHTML(description)
            let opening = firstParagraph(cleaned, maxChars: 300)

            items.append((source: source, title: title, opening: opening))
        }

        return items
    }

    private static func extractTag(_ tag: String, from xml: String) -> String? {
        // Handle both <tag>content</tag> and <tag><![CDATA[content]]></tag>
        let patterns = [
            "(?s)<\(tag)><!\\[CDATA\\[(.*?)\\]\\]></\(tag)>",
            "(?s)<\(tag)>(.*?)</\(tag)>"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..<xml.endIndex, in: xml)),
               let range = Range(match.range(at: 1), in: xml) {
                return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func stripHTML(_ html: String) -> String {
        var result = html
        // Remove HTML tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result), withTemplate: "")
        }
        // Decode common entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#8217;", with: "'")
        result = result.replacingOccurrences(of: "&#8216;", with: "'")
        result = result.replacingOccurrences(of: "&#8220;", with: "\u{201C}")
        result = result.replacingOccurrences(of: "&#8221;", with: "\u{201D}")
        result = result.replacingOccurrences(of: "&hellip;", with: "...")
        result = result.replacingOccurrences(of: "&#8230;", with: "...")
        result = result.replacingOccurrences(of: "&ndash;", with: "–")
        result = result.replacingOccurrences(of: "&mdash;", with: "—")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstParagraph(_ text: String, maxChars: Int) -> String {
        // Split on double newline or take first chunk
        let paragraphs = text.components(separatedBy: "\n\n")
        let first = paragraphs.first ?? text
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        // Truncate at sentence boundary
        let truncated = String(trimmed.prefix(maxChars))
        if let lastPeriod = truncated.lastIndex(of: ".") {
            return String(truncated[...lastPeriod])
        }
        return truncated + "..."
    }
}
