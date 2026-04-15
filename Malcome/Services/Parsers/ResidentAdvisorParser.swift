import Foundation

struct ResidentAdvisorParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let jsonLDEvents = VenueCalendarParser.jsonLDEventDrafts(source: source, html: html, fetchedAt: fetchedAt)
        if !jsonLDEvents.isEmpty { return jsonLDEvents }

        let anchors = HTMLSupport.extractAnchors(from: html)
        let candidates = anchors.filter { $0.href.contains("/events/") || $0.text.localizedCaseInsensitiveContains("live") }

        return dedupeObservationDrafts(candidates.prefix(20).map { anchor in
            let url = HTMLSupport.absoluteURL(anchor.href, relativeTo: source.baseURL)
            let normalized = HTMLSupport.normalizedEntityName(title: anchor.text, author: nil, fallbackURL: url)
            return ObservationDraft(
                domain: source.domain, entityType: .event,
                externalIDOrHash: HTMLSupport.hash(url), title: anchor.text,
                subtitle: "Resident Advisor event listing", url: url, authorOrArtist: nil,
                tags: ["resident-advisor", "la"], location: source.city.displayName,
                publishedAt: nil, scrapedAt: fetchedAt,
                excerpt: "Listed on \(source.name).",
                normalizedEntityName: normalized, rawPayload: "{\"href\":\"\(url)\"}"
            )
        })
    }
}
