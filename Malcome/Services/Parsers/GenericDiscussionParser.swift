import Foundation

struct GenericDiscussionParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        if source.id == "aquarium-drunkard" {
            let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.first == "[" || trimmed.first == "{" {
                let apiDrafts = aquariumDrunkardAPIDrafts(source: source, payload: trimmed, fetchedAt: fetchedAt)
                if !apiDrafts.isEmpty {
                    return dedupeObservationDrafts(Array(apiDrafts.prefix(12)))
                }
            }
            let drafts = aquariumDrunkardDrafts(source: source, html: html, fetchedAt: fetchedAt)
            if !drafts.isEmpty {
                return dedupeObservationDrafts(Array(drafts.prefix(12)))
            }
        }

        if source.id == "hyperallergic" {
            let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.first == "{" {
                let apiDrafts = hyperallergicAPIDrafts(source: source, payload: trimmed, fetchedAt: fetchedAt)
                if !apiDrafts.isEmpty {
                    return dedupeObservationDrafts(Array(apiDrafts.prefix(12)))
                }
            }
            let drafts = hyperallergicDrafts(source: source, html: html, fetchedAt: fetchedAt)
            if !drafts.isEmpty {
                return dedupeObservationDrafts(Array(drafts.prefix(12)))
            }
        }

        let anchors = HTMLSupport.extractAnchors(from: html)
        let candidates = anchors.filter { anchor in
            HTMLSupport.isMeaningfulEntityName(anchor.text) && anchor.href.contains("/202")
        }

        return dedupeObservationDrafts(candidates.prefix(12).map { anchor in
            let url = HTMLSupport.absoluteURL(anchor.href, relativeTo: source.baseURL)
            let normalized = HTMLSupport.inferredEntityName(from: anchor.text, fallbackURL: url)

            return ObservationDraft(
                domain: source.domain,
                entityType: source.classification == .editorial ? .concept : .unknown,
                externalIDOrHash: HTMLSupport.hash(url),
                title: anchor.text,
                subtitle: source.name,
                url: url,
                authorOrArtist: nil,
                tags: ["discussion"],
                location: nil,
                publishedAt: nil,
                scrapedAt: fetchedAt,
                excerpt: "Mentioned in a public discussion thread.",
                normalizedEntityName: normalized,
                rawPayload: "{\"href\":\"\(url)\"}"
            )
        })
    }

    nonisolated private func aquariumDrunkardDrafts(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let pattern = #"(?is)<article[^>]*class="[^"]*post-thumb[^"]*"[^>]*>.*?<h2 class="entry-title"><a href="([^"]+)"[^>]*>(.*?)</a></h2>.*?<time class="entry-date published" datetime="([^"]+)".*?</time>(?:.*?<p>(.*?)</p>)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard
                let linkRange = Range(match.range(at: 1), in: html),
                let titleRange = Range(match.range(at: 2), in: html),
                let dateRange = Range(match.range(at: 3), in: html)
            else {
                return nil
            }

            let url = HTMLSupport.absoluteURL(String(html[linkRange]), relativeTo: source.baseURL)
            let title = HTMLSupport.cleanText(String(html[titleRange]))
            let excerpt: String? = {
                guard let excerptRange = Range(match.range(at: 4), in: html), match.range(at: 4).location != NSNotFound else {
                    return nil
                }
                let cleaned = HTMLSupport.cleanText(String(html[excerptRange]))
                return cleaned.isEmpty ? nil : cleaned
            }()
            let publishedAt = ISO8601DateFormatter().date(from: String(html[dateRange]))
            let normalized = HTMLSupport.inferredEntityName(from: title, fallbackURL: url)

            guard HTMLSupport.isMeaningfulEntityName(normalized) else { return nil }

            return ObservationDraft(
                domain: source.domain,
                entityType: .creator,
                externalIDOrHash: HTMLSupport.hash(url),
                title: title,
                subtitle: source.name,
                url: url,
                authorOrArtist: title.components(separatedBy: " :: ").first.map(HTMLSupport.cleanText),
                tags: ["discussion", "editorial"],
                location: source.city.displayName,
                publishedAt: publishedAt,
                scrapedAt: fetchedAt,
                excerpt: excerpt ?? "Surfacing on \(source.name).",
                normalizedEntityName: normalized,
                rawPayload: "{\"href\":\"\(url)\"}"
            )
        }
    }

    nonisolated private func aquariumDrunkardAPIDrafts(source: SourceRecord, payload: String, fetchedAt: Date) -> [ObservationDraft] {
        guard
            let data = payload.data(using: .utf8),
            let posts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }

        return posts.compactMap { post in
            guard
                let rawURL = post["link"] as? String,
                let titleObject = post["title"] as? [String: Any],
                let rawTitle = titleObject["rendered"] as? String
            else {
                return nil
            }

            let url = HTMLSupport.absoluteURL(rawURL, relativeTo: source.baseURL)
            let title = HTMLSupport.cleanText(rawTitle)
            let excerpt: String? = {
                guard
                    let excerptObject = post["excerpt"] as? [String: Any],
                    let rendered = excerptObject["rendered"] as? String
                else {
                    return nil
                }
                let cleaned = HTMLSupport.cleanText(rendered)
                return cleaned.isEmpty ? nil : cleaned
            }()
            let publishedAt = parseLooseISODate(post["date_gmt"] as? String) ?? parseLooseISODate(post["date"] as? String)
            let normalized = HTMLSupport.inferredEntityName(from: title, fallbackURL: url)

            guard HTMLSupport.isMeaningfulEntityName(normalized) else { return nil }

            return ObservationDraft(
                domain: source.domain,
                entityType: .creator,
                externalIDOrHash: HTMLSupport.hash(url),
                title: title,
                subtitle: source.name,
                url: url,
                authorOrArtist: title.components(separatedBy: " :: ").first.map(HTMLSupport.cleanText),
                tags: ["discussion", "editorial"],
                location: source.city.displayName,
                publishedAt: publishedAt,
                scrapedAt: fetchedAt,
                excerpt: excerpt ?? "Surfacing on \(source.name).",
                normalizedEntityName: normalized,
                rawPayload: String(describing: post)
            )
        }
    }

    nonisolated private func hyperallergicDrafts(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let articlePattern = #"(?is)<article[^>]*class="[^"]*gh-card[^"]*post[^"]*"[^>]*>(.*?)</article>"#
        guard let articleRegex = try? NSRegularExpression(pattern: articlePattern) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return articleRegex.matches(in: html, range: nsRange).compactMap { match in
            guard
                let articleRange = Range(match.range(at: 1), in: html)
            else {
                return nil
            }

            let articleHTML = String(html[articleRange])
            guard
                let url = hyperallergicMatch(in: articleHTML, pattern: #"(?is)<a[^>]*href="([^"]+)""#, capture: 1),
                let titleHTML = hyperallergicMatch(in: articleHTML, pattern: #"(?is)<h3[^>]*class="[^"]*gh-card-title[^"]*"[^>]*>(.*?)</h3>"#, capture: 1),
                let rawDate = hyperallergicMatch(in: articleHTML, pattern: #"(?is)<time[^>]*class="[^"]*gh-card-date[^"]*"[^>]*datetime="([^"]+)""#, capture: 1)
            else {
                return nil
            }

            let resolvedURL = HTMLSupport.absoluteURL(url, relativeTo: source.baseURL)
            let title = HTMLSupport.cleanText(titleHTML)
            let excerpt: String? = {
                guard let rawExcerpt = hyperallergicMatch(in: articleHTML, pattern: #"(?is)<p[^>]*class="[^"]*gh-card-excerpt[^"]*"[^>]*>(.*?)</p>"#, capture: 1) else {
                    return nil
                }
                let cleaned = HTMLSupport.cleanText(rawExcerpt)
                return cleaned.isEmpty ? nil : cleaned
            }()
            let normalized = HTMLSupport.inferredEntityName(from: title, fallbackURL: resolvedURL)
            let entityType: EntityType = title.contains("::") ? .creator : .concept
            let publishedAt = parseLooseISODate(rawDate)

            guard HTMLSupport.isMeaningfulEntityName(normalized) else { return nil }

            return ObservationDraft(
                domain: source.domain,
                entityType: entityType,
                externalIDOrHash: HTMLSupport.hash(resolvedURL),
                title: title,
                subtitle: source.name,
                url: resolvedURL,
                authorOrArtist: title.components(separatedBy: " :: ").first.map(HTMLSupport.cleanText),
                tags: ["discussion", "editorial", "art"],
                location: nil,
                publishedAt: publishedAt,
                scrapedAt: fetchedAt,
                excerpt: excerpt ?? "Surfacing on \(source.name).",
                normalizedEntityName: normalized,
                rawPayload: "{\"href\":\"\(url)\"}"
            )
        }
    }

    nonisolated private func hyperallergicAPIDrafts(source: SourceRecord, payload: String, fetchedAt: Date) -> [ObservationDraft] {
        guard
            let data = payload.data(using: .utf8),
            let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let posts = response["posts"] as? [[String: Any]]
        else {
            return []
        }

        return posts.compactMap { post in
            guard
                let rawURL = post["url"] as? String,
                let rawTitle = post["title"] as? String
            else {
                return nil
            }

            let url = HTMLSupport.absoluteURL(rawURL, relativeTo: source.baseURL)
            let title = HTMLSupport.cleanText(rawTitle)
            let excerpt: String? = {
                guard let rawExcerpt = post["excerpt"] as? String else { return nil }
                let cleaned = HTMLSupport.cleanText(rawExcerpt)
                return cleaned.isEmpty ? nil : cleaned
            }()
            let publishedAt = parseLooseISODate(post["published_at"] as? String)
            let leadingName = HTMLSupport.leadingProperNameCandidate(in: title)
            let authorOrArtist = leadingName
            let normalized = HTMLSupport.inferredEntityName(from: title, author: authorOrArtist, fallbackURL: url)
            let entityType: EntityType = leadingName == nil ? .concept : .creator

            guard HTMLSupport.isMeaningfulEntityName(normalized) else { return nil }

            return ObservationDraft(
                domain: source.domain,
                entityType: entityType,
                externalIDOrHash: HTMLSupport.hash(url),
                title: title,
                subtitle: source.name,
                url: url,
                authorOrArtist: authorOrArtist,
                tags: ["discussion", "editorial", "art"],
                location: nil,
                publishedAt: publishedAt,
                scrapedAt: fetchedAt,
                excerpt: excerpt ?? "Surfacing on \(source.name).",
                normalizedEntityName: normalized,
                rawPayload: String(describing: post)
            )
        }
    }

    nonisolated private func hyperallergicMatch(in html: String, pattern: String, capture: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard
            let match = regex.firstMatch(in: html, range: nsRange),
            let range = Range(match.range(at: capture), in: html)
        else {
            return nil
        }
        return String(html[range])
    }

    nonisolated private func parseLooseISODate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = isoFormatter.date(from: raw) {
            return parsed
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let parsed = isoFormatter.date(from: raw) {
            return parsed
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let parsed = formatter.date(from: raw) {
            return parsed
        }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}
