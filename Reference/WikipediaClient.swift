//
//  WikipediaClient.swift
//  MicroDoc2
//
//  Wikipedia REST API client
//  Ported from MicroDocApp.swift with WikipediaResolver integration
//

import Foundation

// ========== BLOCK 01: Enum declaration, filter helpers, Summary struct - START ==========

enum WikipediaClient {

    struct Summary: Decodable {
        let title: String
        let extract: String
    }

    struct RestSniff: Decodable {
        let extract: String?
        let type: String?
    }

    static let debugLog: Bool = true

    // ========== BLOCK 01: Enum declaration, filter helpers, Summary struct - END ==========

    // ========== BLOCK 02: Core fetch functions (plainTextForTitle, pageSummary, randomTitles) - START ==========

    // MARK: - Article Content

    /// Get full plain text of article (store as rawText, feed to summarizer)
    static func plainTextForTitle(_ title: String) async -> String? {
        do {
            let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
            let url = URL(string: "https://en.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=true&titles=\(encodedTitle)&redirects=true&format=json")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let query = obj?["query"] as? [String: Any]
            let pages = query?["pages"] as? [String: Any]
            if let first = pages?.values.first as? [String: Any],
               let extract = first["extract"] as? String,
               !extract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return extract
            }
            return nil
        } catch {
            print("[plainTextForTitle] error: \(error)")
            return nil
        }
    }

    /// Convenience: derive title from URL and delegate
    static func plainTextForURL(_ url: URL) async -> String? {
        let raw = url.lastPathComponent.replacingOccurrences(of: "_", with: " ")
        let title = raw.removingPercentEncoding ?? raw
        return await plainTextForTitle(title)
    }

    // MARK: - Random Articles

    static func randomTitle() async throws -> String {
        let url = URL(string:
          "https://en.wikipedia.org/w/api.php?action=query&list=random&rnnamespace=0&rnlimit=1&format=json"
        )!
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let query = obj?["query"] as? [String: Any]
        let random = (query?["random"] as? [[String: Any]])?.first
        if let title = random?["title"] as? String { return title }
        throw URLError(.badServerResponse)
    }

    static func randomTitles(limit: Int = 10) async throws -> [String] {
        let capped = max(1, min(limit, 50))
        let url = URL(string:
          "https://en.wikipedia.org/w/api.php?action=query&list=random&rnnamespace=0&rnlimit=\(capped)&format=json"
        )!
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let query = obj?["query"] as? [String: Any]
        let random = query?["random"] as? [[String: Any]] ?? []
        let titles = random.compactMap { $0["title"] as? String }
        if titles.isEmpty { throw URLError(.badServerResponse) }
        return titles
    }

    static func randomTitle(excluding exclude: Set<String>) async throws -> String {
        let batch = try await randomTitles(limit: 20)
        if let pick = batch.first(where: { !exclude.contains($0) }) { return pick }
        return try await randomTitle()
    }

    // MARK: - Page Summary & Validation

    static func pageSummary(title: String) async throws -> Summary {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        let rest = URL(string:
          "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)?redirect=true"
        )!
        let (data, _) = try await URLSession.shared.data(from: rest)
        struct Raw: Decodable { let title: String; let extract: String?; let type: String? }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        if let extract = raw.extract, !extract.isEmpty, raw.type != "disambiguation" {
            return Summary(title: raw.title, extract: extract)
        }
        // Fallback to action API
        let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let action = URL(string:
          "https://en.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=true&exintro=true&titles=\(q)&format=json"
        )!
        let (data2, _) = try await URLSession.shared.data(from: action)
        let obj = try JSONSerialization.jsonObject(with: data2) as? [String: Any]
        let pages = (obj?["query"] as? [String: Any])?["pages"] as? [String: Any]
        if let first = pages?.values.first as? [String: Any],
           let extract = first["extract"] as? String, !extract.isEmpty {
            return Summary(title: raw.title, extract: extract)
        }
        throw URLError(.badServerResponse)
    }

    static func summaryInfo(title: String) async throws -> RestSniff {
        let safe = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        let rest = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(safe)?redirect=true")!
        let (data, _) = try await URLSession.shared.data(from: rest)
        return try JSONDecoder().decode(RestSniff.self, from: data)
    }

    // ========== BLOCK 02: Core fetch functions (plainTextForTitle, pageSummary, randomTitles) - END ==========

    // ========== BLOCK 03: Feed functions (featuredTitles, goodTitles, mostReadTitles, vitalTitles) - START ==========

    // MARK: - Article Filtering

    static func shouldInclude(_ title: String, bucket: String = "general", minChars: Int = 500) async -> Bool {
        do {
            let info = try await summaryInfo(title: title)
            if let t = info.type, t == "disambiguation" { return false }
            let extract = info.extract ?? ""
            if extract.lowercased().contains("may refer to:") { return false }
            if title.hasPrefix("List of") { return false }
            if title.contains("(disambiguation)") { return false }
            if extract.count < minChars { return false }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Feeds

    static func mostReadTitles(limit: Int = 50) async throws -> [String] {
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let y = cal.component(.year, from: date)
        let m = String(format: "%02d", cal.component(.month, from: date))
        let d = String(format: "%02d", cal.component(.day, from: date))
        let url = URL(string:
          "https://wikimedia.org/api/rest_v1/metrics/pageviews/top/en.wikipedia/all-access/\(y)/\(m)/\(d)"
        )!
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = obj?["items"] as? [[String: Any]]
        let first = items?.first
        let articles = first?["articles"] as? [[String: Any]] ?? []
        let titles: [String] = articles.compactMap { row in
            guard let art = row["article"] as? String, art != "Main_Page" else { return nil }
            let spaced = art.replacingOccurrences(of: "_", with: " ")
            return spaced.removingPercentEncoding ?? spaced
        }
        return Array(titles.prefix(limit))
    }

    static func titlesFromCategory(_ category: String, limit: Int = 200) async throws -> [String] {
        let c = "Category:\(category)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Category:\(category)"
        let url = URL(string:
          "https://en.wikipedia.org/w/api.php?action=query&list=categorymembers&cmtitle=\(c)&cmtype=page&cmlimit=\(limit)&format=json"
        )!
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let query = obj?["query"] as? [String: Any]
        let cms = query?["categorymembers"] as? [[String: Any]] ?? []
        return cms.compactMap { $0["title"] as? String }
    }

    static func featuredTitles(limit: Int = 200) async throws -> [String] {
        try await titlesFromCategory("Featured_articles", limit: limit)
    }

    static func goodTitles(limit: Int = 200) async throws -> [String] {
        try await titlesFromCategory("Good_articles", limit: limit)
    }

    static func vitalTitles(limit: Int = 200) async throws -> [String] {
        let vaPages = [
            "Wikipedia:Vital articles/Level/4/Arts",
            "Wikipedia:Vital articles/Level/4/Geography",
            "Wikipedia:Vital articles/Level/4/History",
            "Wikipedia:Vital articles/Level/4/Science",
            "Wikipedia:Vital articles/Level/4/Society",
            "Wikipedia:Vital articles/Level/4/Technology"
        ]
        var all: [String] = []
        for page in vaPages {
            if let links = try? await fetchLinksFromVASection(page: page) {
                all.append(contentsOf: links)
            }
            if all.count >= limit { break }
        }
        return Array(Array(Set(all)).filter { !$0.isEmpty }.prefix(limit))
    }

    private static func fetchLinksFromVASection(page: String) async throws -> [String] {
        let encoded = page.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? page
        let url = URL(string: "https://en.wikipedia.org/w/api.php?action=parse&format=json&prop=links&page=\(encoded)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let parse = obj?["parse"] as? [String: Any]
        let links = parse?["links"] as? [[String: Any]] ?? []
        let bannedPrefixes = ["Wikipedia:", "Talk:", "Category:", "Template:", "Portal:", "File:", "Help:", "Draft:", "Module:", "User:"]
        var titles: [String] = []
        for l in links {
            if let ns = l["ns"] as? Int, ns == 0, let t = l["*"] as? String {
                titles.append(t)
                continue
            }
            if let t = l["*"] as? String {
                if bannedPrefixes.first(where: { t.hasPrefix($0) }) == nil {
                    titles.append(t)
                }
            }
        }
        return titles
    }

    // ========== BLOCK 03: Feed functions (featuredTitles, goodTitles, mostReadTitles, vitalTitles) - END ==========

    // ========== BLOCK 04: Search and validation functions - START ==========

    /// Search Wikipedia for articles matching a topic (for recipe validation)
    static func searchArticles(query: String, limit: Int = 10) async throws -> [String] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string:
          "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&srlimit=\(limit)&format=json"
        )!
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let query_ = obj?["query"] as? [String: Any]
        let results = query_?["search"] as? [[String: Any]] ?? []
        return results.compactMap { $0["title"] as? String }
    }

    // ========== BLOCK 04: Search and validation functions - END ==========

    // ========== BLOCK 05: URL helpers (articleURL, displayTitle, shouldInclude filter) - START ==========

    // MARK: - URL Helpers

    nonisolated static func articleURL(forTitle title: String) -> URL? {
        let path = title.replacingOccurrences(of: " ", with: "_")
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "https://en.wikipedia.org/wiki/\(encoded)")
    }

    nonisolated static func displayTitle(fromArticleURLString urlString: String) -> String {
        guard let u = URL(string: urlString) else { return urlString }
        let raw = u.lastPathComponent.replacingOccurrences(of: "_", with: " ")
        return raw.removingPercentEncoding ?? raw
    }

    // ========== BLOCK 05: URL helpers (articleURL, displayTitle, shouldInclude filter) - END ==========

    // ========== BLOCK 06: WikipediaResolver - Title-to-URL Resolution - START ==========

    // MARK: - WikipediaResolver
    // Resolves fuzzy AFM-generated titles to actual Wikipedia URLs
    // Ported from wikiurlresolverApp.swift

    struct ResolvedArticle {
        let originalTitle: String
        let resolvedTitle: String
        let url: URL
    }

    /// Main entry point: try to resolve any fuzzy title to a valid Wikipedia URL.
    /// Returns nil if all strategies fail.
    static func resolveTitle(_ title: String) async -> ResolvedArticle? {
        let strategies: [() async -> ResolvedArticle?] = [

            // Strategy 1: Direct lookup — title as-is
            {
                if await isValidArticle(title) {
                    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let url = articleURL(forTitle: t) else { return nil }
                    return ResolvedArticle(originalTitle: title, resolvedTitle: t, url: url)
                }
                return nil
            },

            // Strategy 2: Strip trailing descriptors like "movie", "film", "book"
            // e.g. "Apollo 13 movie" → "Apollo 13 (film)"
            {
                let descriptorMap: [String: String] = [
                    " movie": " (film)", " film": " (film)", " the movie": " (film)",
                    " the film": " (film)", " book": "", " novel": "",
                    " tv show": " (TV series)", " tv series": " (TV series)",
                    " song": " (song)", " album": " (album)"
                ]
                let lower = title.lowercased()
                for (suffix, replacement) in descriptorMap {
                    if lower.hasSuffix(suffix) {
                        let base = String(title.dropLast(suffix.count))
                        let candidate = base + replacement
                        if await isValidArticle(candidate) {
                            guard let url = articleURL(forTitle: candidate) else { continue }
                            return ResolvedArticle(originalTitle: title, resolvedTitle: candidate, url: url)
                        }
                    }
                }
                return nil
            },

            // Strategy 3: Strip parenthetical qualifiers
            // e.g. "Einstein (physicist)" → "Albert Einstein"
            {
                if title.contains("(") {
                    let clean = title.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "",
                                                          options: .regularExpression)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    if clean != title {
                        if await isValidArticle(clean) {
                            guard let url = articleURL(forTitle: clean) else { return nil }
                            return ResolvedArticle(originalTitle: title, resolvedTitle: clean, url: url)
                        }
                    }
                }
                return nil
            },

            // Strategy 4: Colon — try main part only
            // e.g. "Einstein: Theory of Relativity" → "Theory of relativity"
            {
                if title.contains(":") {
                    let parts = title.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                    for part in parts where !part.isEmpty {
                        if await isValidArticle(part) {
                            guard let url = articleURL(forTitle: part) else { continue }
                            return ResolvedArticle(originalTitle: title, resolvedTitle: part, url: url)
                        }
                    }
                }
                return nil
            },

            // Strategy 5: Wikipedia opensearch — the most powerful fallback
            // Handles any fuzzy or natural-language title
            {
                let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
                guard let url = URL(string:
                    "https://en.wikipedia.org/w/api.php?action=opensearch&search=\(encoded)&limit=3&format=json"
                ) else { return nil }

                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                      json.count >= 4,
                      let titles = json[1] as? [String],
                      let urls = json[3] as? [String],
                      !titles.isEmpty, !urls.isEmpty else { return nil }

                // Validate the top result
                let foundTitle = titles[0]
                let foundURLString = urls[0]
                if await isValidArticle(foundTitle), let foundURL = URL(string: foundURLString) {
                    return ResolvedArticle(originalTitle: title, resolvedTitle: foundTitle, url: foundURL)
                }
                return nil
            }
        ]

        // Try each strategy in order, return first success
        for strategy in strategies {
            if let result = await strategy() {
                print("[Resolver] '\(title)' → '\(result.resolvedTitle)'")
                return result
            }
        }

        print("[Resolver] All strategies failed for '\(title)'")
        return nil
    }

    /// Lightweight validity check: exists, not disambiguation, has content
    private static func isValidArticle(_ title: String) async -> Bool {
        return await shouldInclude(title, bucket: "resolver", minChars: 200)
    }

    // ========== BLOCK 06: WikipediaResolver - Title-to-URL Resolution - END ==========
}
