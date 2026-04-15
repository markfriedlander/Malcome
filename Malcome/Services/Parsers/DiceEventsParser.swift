import Foundation

struct DiceEventsParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        guard
            let data = html.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let events = json["data"] as? [[String: Any]]
        else { return [] }

        return dedupeObservationDrafts(events.compactMap { event in
            guard
                let id = event["id"] as? String,
                let name = event["name"] as? String,
                let url = event["url"] as? String
            else { return nil }

            let title = HTMLSupport.cleanText(name)
            let venueName = HTMLSupport.cleanText(event["venue"] as? String ?? source.name)
            let publishedAt = ISO8601DateFormatter().date(from: event["date"] as? String ?? "")
            let genreTags = (event["genre_tags"] as? [String] ?? []).map(HTMLSupport.cleanText)
            let lineup = (event["lineup"] as? [[String: Any]] ?? []).compactMap { ($0["details"] as? String).map(HTMLSupport.cleanText) }
            let ageLimit = (event["age_limit"] as? String).map(HTMLSupport.cleanText)
            let noteParts = [lineup.first, ageLimit].compactMap { part -> String? in
                guard let part, !part.isEmpty else { return nil }
                return part
            }

            return ObservationDraft(
                domain: source.domain, entityType: .event,
                externalIDOrHash: HTMLSupport.hash(id + url), title: title, subtitle: venueName,
                url: url, authorOrArtist: title,
                tags: ["dice-event", "venue-calendar"] + genreTags, location: venueName,
                publishedAt: publishedAt, scrapedAt: fetchedAt,
                excerpt: noteParts.isEmpty ? "Upcoming show spotted on \(source.name)." : noteParts.joined(separator: " • "),
                normalizedEntityName: HTMLSupport.inferredEntityName(from: title, author: title, fallbackURL: url),
                rawPayload: String(describing: event)
            )
        })
    }
}
