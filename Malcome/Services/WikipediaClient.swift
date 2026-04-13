import Foundation

/// Wikipedia REST API client adapted from Microdoc's WikipediaClient.
/// Provides entity context for brief generation and chat responses.
/// Single entry point: contextSummary(for:) — never throws, returns nil on any failure.
enum WikipediaClient {

    struct Summary {
        let title: String
        let extract: String

        /// Returns the first sentence of the extract for concise brief context.
        var firstSentence: String {
            let trimmed = extract.trimmingCharacters(in: .whitespacesAndNewlines)
            // Split on ". " to find first sentence boundary
            if let range = trimmed.range(of: ". ") {
                return String(trimmed[...range.lowerBound]) + "."
            }
            // If no period-space, check for a trailing period
            if trimmed.hasSuffix(".") { return trimmed }
            return trimmed
        }
    }

    // MARK: - Cache

    private static let cache = WikiCache()

    // MARK: - Public Entry Points

    /// Fetch a Wikipedia context summary for an entity name.
    /// Returns nil on any failure — 404, network error, disambiguation, no entry.
    /// Never throws. Call sites never need try/catch.
    static func contextSummary(for entityName: String) async -> Summary? {
        let cacheKey = entityName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check cache first
        if let cached = await cache.get(cacheKey) {
            return cached
        }

        // Resolve the entity name to a valid Wikipedia title
        guard let resolved = await resolveTitle(entityName) else { return nil }

        // Fetch the summary
        guard let summary = await fetchSummary(title: resolved.resolvedTitle) else { return nil }

        // Cache and return
        await cache.set(cacheKey, summary)
        return summary
    }

    /// Returns the full Wikipedia extract for an entity. Used when the user asks for comprehensive detail.
    /// Returns the cached extract if available, otherwise fetches fresh.
    static func fullExtract(for entityName: String) async -> String? {
        if let summary = await contextSummary(for: entityName) {
            return summary.extract
        }
        return nil
    }

    // MARK: - Title Resolution (Strategies 1-4, skipping OpenSearch)

    private struct ResolvedArticle {
        let originalTitle: String
        let resolvedTitle: String
    }

    private static func resolveTitle(_ title: String) async -> ResolvedArticle? {
        // Strategy 1: Direct lookup
        if await isValidArticle(title) {
            return ResolvedArticle(originalTitle: title, resolvedTitle: title.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Strategy 2: Strip trailing descriptors
        let descriptorMap: [String: String] = [
            " movie": " (film)", " film": " (film)",
            " tv show": " (TV series)", " tv series": " (TV series)",
            " song": " (song)", " album": " (album)",
            " band": "", " artist": "",
        ]
        let lower = title.lowercased()
        for (suffix, replacement) in descriptorMap {
            if lower.hasSuffix(suffix) {
                let base = String(title.dropLast(suffix.count))
                let candidate = base + replacement
                if await isValidArticle(candidate) {
                    return ResolvedArticle(originalTitle: title, resolvedTitle: candidate)
                }
            }
        }

        // Strategy 3: Strip parenthetical qualifiers
        if title.contains("(") {
            let clean = title.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if clean != title, await isValidArticle(clean) {
                return ResolvedArticle(originalTitle: title, resolvedTitle: clean)
            }
        }

        // Strategy 4: Disambiguation — try domain-specific qualifiers
        // "Thundercat" → "Thundercat (musician)" when the base title is a disambiguation page
        let domainQualifiers = ["(musician)", "(band)", "(artist)", "(rapper)", "(singer)", "(DJ)",
                                "(filmmaker)", "(director)", "(designer)", "(collective)"]
        for qualifier in domainQualifiers {
            let candidate = "\(title) \(qualifier)"
            if await isValidArticle(candidate) {
                return ResolvedArticle(originalTitle: title, resolvedTitle: candidate)
            }
        }

        // Strategy 5: Colon — try each part
        if title.contains(":") {
            let parts = title.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            for part in parts where !part.isEmpty {
                if await isValidArticle(part) {
                    return ResolvedArticle(originalTitle: title, resolvedTitle: part)
                }
            }
        }

        // Strategy 5 (OpenSearch) intentionally skipped — for cultural entity names,
        // a clean nil is more honest than a confidently wrong result.

        return nil
    }

    // MARK: - Fetch

    private static func fetchSummary(title: String) async -> Summary? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)?redirect=true") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            struct Raw: Decodable { let title: String; let extract: String?; let type: String? }
            let raw = try JSONDecoder().decode(Raw.self, from: data)

            // Reject disambiguation pages
            if raw.type == "disambiguation" { return nil }
            guard let extract = raw.extract, !extract.isEmpty else { return nil }

            return Summary(title: raw.title, extract: extract)
        } catch {
            return nil
        }
    }

    // MARK: - Validation

    private static func isValidArticle(_ title: String) async -> Bool {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)?redirect=true") else {
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }

            struct Sniff: Decodable { let extract: String?; let type: String? }
            let sniff = try JSONDecoder().decode(Sniff.self, from: data)

            if sniff.type == "disambiguation" { return false }
            guard let extract = sniff.extract, extract.count >= 100 else { return false }
            if extract.lowercased().contains("may refer to:") { return false }

            return true
        } catch {
            return false
        }
    }
}

// MARK: - Cache Actor

private actor WikiCache {
    private var cache: [String: WikipediaClient.Summary] = [:]

    func get(_ key: String) -> WikipediaClient.Summary? {
        cache[key]
    }

    func set(_ key: String, _ value: WikipediaClient.Summary) {
        cache[key] = value
    }
}
