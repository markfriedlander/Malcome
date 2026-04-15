import Foundation

struct GitHubTrendingParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let pattern = #"(?is)<h2[^>]*>\s*<a[^>]*href=["'](/[^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        let items = regex.matches(in: html, range: nsRange).compactMap { match -> ObservationDraft? in
            guard
                let hrefRange = Range(match.range(at: 1), in: html),
                let titleRange = Range(match.range(at: 2), in: html)
            else {
                return nil
            }

            let href = String(html[hrefRange])
            let repo = HTMLSupport.cleanText(String(html[titleRange])).replacingOccurrences(of: " / ", with: "/")
            let url = HTMLSupport.absoluteURL(href, relativeTo: "https://github.com")
            let normalized = HTMLSupport.normalizedEntityName(title: repo, author: nil, fallbackURL: url)

            return ObservationDraft(
                domain: source.domain,
                entityType: .concept,
                externalIDOrHash: HTMLSupport.hash(url),
                title: repo,
                subtitle: "GitHub Trending",
                url: url,
                authorOrArtist: nil,
                tags: ["github", "swift"],
                location: nil,
                publishedAt: nil,
                scrapedAt: fetchedAt,
                excerpt: "Trending in Swift today.",
                normalizedEntityName: normalized,
                rawPayload: "{\"href\":\"\(url)\"}"
            )
        }

        return dedupeObservationDrafts(items.prefix(15).map { $0 })
    }
}
