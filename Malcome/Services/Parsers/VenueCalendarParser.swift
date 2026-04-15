import Foundation

struct VenueCalendarParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let sourceSpecificDrafts = sourceSpecificDrafts(source: source, html: html, fetchedAt: fetchedAt)
        if !sourceSpecificDrafts.isEmpty {
            return dedupeObservationDrafts(Array(sourceSpecificDrafts.prefix(18)))
        }

        let jsonLDEvents = Self.jsonLDEventDrafts(source: source, html: html, fetchedAt: fetchedAt)
        if !jsonLDEvents.isEmpty {
            return dedupeObservationDrafts(jsonLDEvents.prefix(18).map { $0 })
        }

        let anchors = HTMLSupport.extractAnchors(from: html)
        let candidates = anchors.filter { anchor in
            let lower = anchor.text.lowercased()
            let href = anchor.href.lowercased()
            let looksLikeEventPath = href.contains("/events/") || href.contains("/shows/") || href.contains("ticketmaster.com/")
            return lower.count > 6 && looksLikeEventPath && !lower.contains("tickets") && !lower.contains("calendar")
        }

        return dedupeObservationDrafts(candidates.prefix(18).map { anchor in
            let url = HTMLSupport.absoluteURL(anchor.href, relativeTo: source.baseURL)
            let normalized = HTMLSupport.normalizedEntityName(title: anchor.text, author: nil, fallbackURL: url)

            return ObservationDraft(
                domain: source.domain,
                entityType: .event,
                externalIDOrHash: HTMLSupport.hash(url),
                title: anchor.text,
                subtitle: source.name,
                url: url,
                authorOrArtist: nil,
                tags: ["venue-calendar"],
                location: source.name,
                publishedAt: nil,
                scrapedAt: fetchedAt,
                excerpt: "Observed on the venue calendar.",
                normalizedEntityName: normalized,
                rawPayload: "{\"href\":\"\(url)\"}"
            )
        })
    }

    nonisolated private func sourceSpecificDrafts(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        if source.id == "lodge-room" || source.id == "lodge-room-home" {
            let drafts = Self.lodgeRoomDrafts(source: source, html: html, fetchedAt: fetchedAt)
            if !drafts.isEmpty {
                return drafts
            }
        }

        if source.id == "the-smell" {
            let drafts = Self.theSmellDrafts(source: source, html: html, fetchedAt: fetchedAt)
            if !drafts.isEmpty {
                return drafts
            }
        }

        if source.id == "the-bellwether-home" {
            let drafts = Self.bellwetherDrafts(source: source, html: html, fetchedAt: fetchedAt)
            if !drafts.isEmpty {
                return drafts
            }
        }

        return []
    }

    nonisolated static func jsonLDEventDrafts(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let events: [[String: Any]] = HTMLSupport.extractJSONLDBlocks(from: html)
            .flatMap { block in
                guard let data = block.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data)
                else {
                    return [[String: Any]]()
                }
                return extractEvents(from: json)
            }

        return Array(events.prefix(20)).compactMap { event in
                let title = event["name"] as? String ?? event["headline"] as? String ?? ""
                let urlValue = event["url"] as? String ?? source.baseURL
                let startDate = (event["startDate"] as? String).flatMap(ISO8601DateFormatter().date(from:))
                let locationName = extractLocation(from: event["location"])
                let excerpt = event["description"] as? String

                guard !title.isEmpty else { return nil }

                let normalized = HTMLSupport.normalizedEntityName(title: title, author: nil, fallbackURL: urlValue)

                return ObservationDraft(
                    domain: source.domain,
                    entityType: .event,
                    externalIDOrHash: HTMLSupport.hash(urlValue + title),
                    title: HTMLSupport.cleanText(title),
                    subtitle: locationName,
                    url: HTMLSupport.absoluteURL(urlValue, relativeTo: source.baseURL),
                    authorOrArtist: nil,
                    tags: ["event", "json-ld"],
                    location: locationName,
                    publishedAt: startDate,
                    scrapedAt: fetchedAt,
                    excerpt: excerpt.map(HTMLSupport.cleanText),
                    normalizedEntityName: normalized,
                    rawPayload: String(describing: event)
                )
            }
    }

    nonisolated private static func lodgeRoomDrafts(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let pattern = #"(?s)eventObjects\.push\((\{.*?\})\);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard
                let payloadRange = Range(match.range(at: 1), in: html),
                let data = String(html[payloadRange]).data(using: .utf8),
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }

            let rawID = (payload["id"] as? String) ?? String(payload["id"] as? Int ?? 0)
            let link = HTMLSupport.absoluteURL(payload["link"] as? String ?? "", relativeTo: source.baseURL)
            let mainArtists = (payload["mainArtist"] as? [String] ?? [])
                .map(HTMLSupport.cleanText)
                .filter { !$0.isEmpty && !isGenericTitle($0) }
            let supportingActs = (payload["additionalArtists"] as? [String] ?? [])
                .map(HTMLSupport.cleanText)
                .filter { !$0.isEmpty && !isGenericTitle($0) }
            let publishedAt = simpleDate(payload["eventDate"] as? String ?? "")
            let cleanedTitle = mainArtists.first ?? ""

            guard !cleanedTitle.isEmpty, !link.isEmpty else { return nil }

            let excerpt = supportingActs.isEmpty
                ? "Upcoming show from the Lodge Room calendar."
                : "With \(supportingActs.prefix(3).joined(separator: ", "))."

            return ObservationDraft(
                domain: source.domain,
                entityType: .event,
                externalIDOrHash: HTMLSupport.hash(rawID + link),
                title: cleanedTitle,
                subtitle: source.name,
                url: link,
                authorOrArtist: cleanedTitle,
                tags: ["venue-calendar", "event"],
                location: source.name,
                publishedAt: publishedAt,
                scrapedAt: fetchedAt,
                excerpt: excerpt,
                normalizedEntityName: HTMLSupport.normalizedEntityName(title: cleanedTitle, author: cleanedTitle, fallbackURL: link),
                rawPayload: "{\"title\":\"\(cleanedTitle)\",\"link\":\"\(link)\"}"
            )
        }
    }

    nonisolated private static func theSmellDrafts(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let pattern = #"(?s)<article class="eventlist-event.*?<a href="([^"]+)" class="eventlist-title-link">([^<]+)</a>.*?<time class="event-date" datetime="([^"]+)">.*?</time>.*?<div class="eventlist-excerpt">(.*?)</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard
                let linkRange = Range(match.range(at: 1), in: html),
                let dateLabelRange = Range(match.range(at: 2), in: html),
                let dateValueRange = Range(match.range(at: 3), in: html),
                let excerptRange = Range(match.range(at: 4), in: html)
            else {
                return nil
            }

            let link = HTMLSupport.absoluteURL(String(html[linkRange]), relativeTo: source.baseURL)
            let dateLabel = HTMLSupport.cleanText(String(html[dateLabelRange]))
            let publishedAt = simpleDate(String(html[dateValueRange]))
            let excerptHTML = String(html[excerptRange])
            let lines = extractParagraphLines(from: excerptHTML)
            let headline = smellHeadline(from: lines) ?? dateLabel
            let supportingActs = lines.filter { line in
                let normalized = line.lowercased()
                return normalized != headline.lowercased() && !normalized.contains("pm") && !normalized.contains("$")
            }

            guard !headline.isEmpty, !link.isEmpty else { return nil }

            let excerpt = supportingActs.prefix(4).joined(separator: " • ")

            return ObservationDraft(
                domain: source.domain,
                entityType: .event,
                externalIDOrHash: HTMLSupport.hash(link),
                title: headline,
                subtitle: dateLabel,
                url: link,
                authorOrArtist: headline,
                tags: ["venue-calendar", "diy", "event"],
                location: source.name,
                publishedAt: publishedAt,
                scrapedAt: fetchedAt,
                excerpt: excerpt.isEmpty ? "Upcoming show on The Smell calendar." : excerpt,
                normalizedEntityName: HTMLSupport.normalizedEntityName(title: headline, author: headline, fallbackURL: link),
                rawPayload: "{\"href\":\"\(link)\",\"date\":\"\(dateLabel)\"}"
            )
        }
    }

    nonisolated private static func bellwetherDrafts(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let anchors = HTMLSupport.extractAnchors(from: html).filter { anchor in
            let cleaned = HTMLSupport.cleanText(anchor.text).lowercased()
            return anchor.href.contains("/events/") && cleaned.count > 4 && !isGenericTitle(cleaned)
        }

        return anchors.prefix(18).map { anchor in
            let link = HTMLSupport.absoluteURL(anchor.href, relativeTo: source.baseURL)
            let title = HTMLSupport.cleanText(anchor.text)
            return ObservationDraft(
                domain: source.domain,
                entityType: .event,
                externalIDOrHash: HTMLSupport.hash(link),
                title: title,
                subtitle: source.name,
                url: link,
                authorOrArtist: nil,
                tags: ["venue-calendar", "event"],
                location: source.name,
                publishedAt: nil,
                scrapedAt: fetchedAt,
                excerpt: "Upcoming show spotted on The Bellwether.",
                normalizedEntityName: HTMLSupport.normalizedEntityName(title: title, author: nil, fallbackURL: link),
                rawPayload: "{\"href\":\"\(link)\"}"
            )
        }
    }

    nonisolated private static func extractEvents(from json: Any) -> [[String: Any]] {
        if let dict = json as? [String: Any] {
            if let type = dict["@type"] as? String, type.localizedCaseInsensitiveContains("Event") {
                return [dict]
            }
            if let graph = dict["@graph"] as? [Any] {
                return graph.flatMap(extractEvents(from:))
            }
            return dict.values.flatMap(extractEvents(from:))
        }

        if let array = json as? [Any] {
            return array.flatMap(extractEvents(from:))
        }

        return []
    }

    nonisolated private static func extractLocation(from rawLocation: Any?) -> String? {
        if let text = rawLocation as? String {
            return HTMLSupport.cleanText(text)
        }
        if let dict = rawLocation as? [String: Any] {
            return (dict["name"] as? String).map(HTMLSupport.cleanText)
        }
        return nil
    }

    nonisolated private static func parseJSONArrayStrings(_ raw: String) -> [String] {
        let pattern = #""((?:\\"|[^"])*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)

        return regex.matches(in: raw, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: raw) else { return nil }
            let value = raw[range]
                .replacingOccurrences(of: #"\""#, with: "\"")
                .replacingOccurrences(of: #"\\/"#, with: "/")
            let cleaned = HTMLSupport.cleanText(value)
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    nonisolated private static func simpleDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: raw)
    }

    nonisolated private static func extractParagraphLines(from html: String) -> [String] {
        let pattern = #"(?is)<p[^>]*>(.*?)</p>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else { return nil }
            let line = HTMLSupport.cleanText(String(html[range]))
            return line.isEmpty ? nil : line
        }
    }

    nonisolated private static func smellHeadline(from lines: [String]) -> String? {
        let ignoredFragments = [
            "presents",
            "pm",
            "advance tickets",
            "pre-sale",
            "tickets available",
            "$"
        ]

        let candidates = lines.filter { line in
            let lowered = line.lowercased()
            guard line.count > 2 else { return false }
            return !ignoredFragments.contains(where: { lowered.contains($0) }) && !isGenericTitle(lowered)
        }

        guard let first = candidates.first else { return nil }
        let second = candidates.dropFirst().first
        if let second, !second.lowercased().contains("(nyc)") {
            return "\(first), \(second)"
        }
        return first
    }

    nonisolated private static func isGenericTitle(_ value: String) -> Bool {
        let normalized = HTMLSupport.cleanText(value).lowercased()
        guard !normalized.isEmpty else { return true }

        let blockedTitles: Set<String> = [
            "more info",
            "buy tickets",
            "tickets",
            "ticket info",
            "learn more",
            "details",
            "show details",
            "event details",
            "rsvp"
        ]

        return blockedTitles.contains(normalized)
    }
}
