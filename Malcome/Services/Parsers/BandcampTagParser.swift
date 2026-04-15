import Foundation

struct BandcampTagParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" {
            let apiDrafts = apiResponseDrafts(source: source, payload: trimmed, fetchedAt: fetchedAt)
            if !apiDrafts.isEmpty {
                return dedupeObservationDrafts(Array(apiDrafts.prefix(24)))
            }
        }

        let blobDrafts = dataBlobDrafts(source: source, html: html, fetchedAt: fetchedAt)
        if !blobDrafts.isEmpty {
            return dedupeObservationDrafts(Array(blobDrafts.prefix(24)))
        }

        let anchors = HTMLSupport.extractAnchors(from: html)
        let candidates = anchors.filter { anchor in
            anchor.href.contains("/album/") || anchor.href.contains("/track/")
        }

        return dedupeObservationDrafts(candidates.prefix(24).map { anchor in
            let url = HTMLSupport.absoluteURL(anchor.href, relativeTo: source.baseURL)
            let title = anchor.text
            let normalized = HTMLSupport.normalizedEntityName(title: title, author: nil, fallbackURL: url)

            return ObservationDraft(
                domain: source.domain,
                entityType: .creator,
                externalIDOrHash: HTMLSupport.hash(url),
                title: title,
                subtitle: "Bandcamp tag discovery",
                url: url,
                authorOrArtist: nil,
                tags: ["bandcamp", source.city.displayName.lowercased()],
                location: source.city.displayName,
                publishedAt: nil,
                scrapedAt: fetchedAt,
                excerpt: "Surfacing on \(source.name).",
                normalizedEntityName: normalized,
                rawPayload: "{\"href\":\"\(url)\"}"
            )
        })
    }

    nonisolated private func apiResponseDrafts(source: SourceRecord, payload: String, fetchedAt: Date) -> [ObservationDraft] {
        guard
            let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]]
        else { return [] }

        return results.compactMap { result -> ObservationDraft? in
            guard
                let rawURL = result["item_url"] as? String,
                let rawTitle = result["title"] as? String,
                let bandName = result["band_name"] as? String
            else { return nil }

            let url = HTMLSupport.absoluteURL(rawURL, relativeTo: source.baseURL)
            let title = HTMLSupport.cleanText(rawTitle)
            let artist = HTMLSupport.cleanText(bandName)
            let featuredTrack = ((result["featured_track"] as? [String: Any])?["title"] as? String).map(HTMLSupport.cleanText)
            let location = (result["band_location"] as? String).map(HTMLSupport.cleanText)
            let excerptParts = [featuredTrack, location].compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }

            return ObservationDraft(
                domain: source.domain, entityType: .creator,
                externalIDOrHash: HTMLSupport.hash(url), title: title, subtitle: artist,
                url: url, authorOrArtist: artist,
                tags: ["bandcamp", source.city.displayName.lowercased()],
                location: location,
                publishedAt: parseBandcampDate(result["release_date"] as? String),
                scrapedAt: fetchedAt,
                excerpt: excerptParts.isEmpty ? "Surfacing on \(source.name)." : excerptParts.joined(separator: " • "),
                normalizedEntityName: HTMLSupport.normalizedEntityName(title: artist, author: artist, fallbackURL: url),
                rawPayload: String(describing: result)
            )
        }
    }

    nonisolated private func dataBlobDrafts(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        guard let blob = HTMLSupport.extractDataBlobJSON(from: html),
              let data = blob.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return [] }

        let candidates = collectBandcampCandidates(from: json)
        return candidates.compactMap { candidate -> ObservationDraft? in
            let url = firstString(in: candidate, keys: ["itemUrl", "url", "tralbumUrl", "link"]) ?? ""
            let title = firstString(in: candidate, keys: ["title", "albumTitle", "trackTitle", "name"]) ?? ""
            let artist = firstString(in: candidate, keys: ["bandName", "artist", "artistName", "band_name"])
            let featuredTrack = firstString(in: candidate, keys: ["featuredTrack", "featured_track"])
            let resolvedURL = HTMLSupport.absoluteURL(url, relativeTo: source.baseURL)
            let resolvedTitle = HTMLSupport.cleanText(title.isEmpty ? (artist ?? resolvedURL) : title)
            let resolvedArtist = artist.map(HTMLSupport.cleanText)
            let normalized = HTMLSupport.normalizedEntityName(
                title: resolvedArtist?.isEmpty == false ? resolvedArtist! : resolvedTitle,
                author: resolvedArtist, fallbackURL: resolvedURL
            )
            guard !resolvedURL.isEmpty, !resolvedTitle.isEmpty else { return nil }
            let excerptParts = [resolvedArtist, featuredTrack].compactMap { v -> String? in
                guard let v else { return nil }
                let c = HTMLSupport.cleanText(v)
                return c.isEmpty ? nil : c
            }
            return ObservationDraft(
                domain: source.domain, entityType: .creator,
                externalIDOrHash: HTMLSupport.hash(resolvedURL), title: resolvedTitle, subtitle: resolvedArtist,
                url: resolvedURL, authorOrArtist: resolvedArtist,
                tags: ["bandcamp", source.city.displayName.lowercased()],
                location: source.city.displayName, publishedAt: nil, scrapedAt: fetchedAt,
                excerpt: excerptParts.isEmpty ? "Surfacing on \(source.name)." : excerptParts.joined(separator: " • "),
                normalizedEntityName: normalized, rawPayload: String(describing: candidate)
            )
        }
    }

    nonisolated private func collectBandcampCandidates(from json: Any) -> [[String: Any]] {
        var matches: [[String: Any]] = []
        walkBandcamp(value: json, matches: &matches)
        return matches
    }

    nonisolated private func walkBandcamp(value: Any, matches: inout [[String: Any]]) {
        if let dict = value as? [String: Any] {
            let hasURL = firstString(in: dict, keys: ["itemUrl", "url", "tralbumUrl", "link"])?.isEmpty == false
            let hasIdentity = firstString(in: dict, keys: ["bandName", "artist", "artistName", "band_name"])?.isEmpty == false
                || firstString(in: dict, keys: ["title", "albumTitle", "trackTitle", "name"])?.isEmpty == false
            if hasURL && hasIdentity { matches.append(dict) }
            for v in dict.values { walkBandcamp(value: v, matches: &matches) }
        } else if let array = value as? [Any] {
            for v in array { walkBandcamp(value: v, matches: &matches) }
        }
    }

    nonisolated private func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !HTMLSupport.cleanText(value).isEmpty { return value }
        }
        return nil
    }

    nonisolated private func parseBandcampDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
        return formatter.date(from: raw)
    }
}
