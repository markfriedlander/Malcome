import Foundation

struct WordPressPostsParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "[" || trimmed.first == "{" else { return [] }
        guard
            let data = trimmed.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return []
        }

        let posts: [[String: Any]]
        if let array = json as? [[String: Any]] {
            posts = array
        } else if let dict = json as? [String: Any], let embedded = dict["posts"] as? [[String: Any]] {
            posts = embedded
        } else {
            return []
        }

        return dedupeObservationDrafts(posts.compactMap { post in
            guard
                let rawURL = post["link"] as? String,
                let titleObject = post["title"] as? [String: Any],
                let rawTitle = titleObject["rendered"] as? String
            else {
                return nil
            }

            let url = HTMLSupport.absoluteURL(rawURL, relativeTo: source.baseURL)
            let title = HTMLSupport.cleanText(rawTitle)
            guard !title.isEmpty else { return nil }

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

            let subject = HTMLSupport.inferredEditorialEntity(
                from: title,
                sourceName: source.name,
                fallbackURL: url
            )
            let normalized = HTMLSupport.normalizedEntityName(
                title: subject.name,
                author: subject.author,
                fallbackURL: url
            )

            guard HTMLSupport.isMeaningfulEntityName(normalized) else { return nil }

            let tags = Array(Set([
                "editorial",
                source.domain.rawValue,
                source.classification.rawValue
            ] + HTMLSupport.editorialContentTags(for: title, sourceName: source.name))).sorted()

            return ObservationDraft(
                domain: source.domain,
                entityType: subject.entityType,
                externalIDOrHash: HTMLSupport.hash(url),
                title: title,
                subtitle: source.name,
                url: url,
                authorOrArtist: subject.author,
                tags: tags,
                location: source.city == .global ? nil : source.city.displayName,
                publishedAt: parseLooseISODate(post["date_gmt"] as? String) ?? parseLooseISODate(post["date"] as? String),
                scrapedAt: fetchedAt,
                excerpt: excerpt ?? "Surfacing on \(source.name).",
                normalizedEntityName: normalized,
                rawPayload: String(describing: post)
            )
        })
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
