import Foundation

protocol SourceParsing: Sendable {
    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft]
}

struct SourceParserFactory: Sendable {
    nonisolated func parser(for type: ParserType) -> any SourceParsing {
        switch type {
        case .bandcampTag:
            BandcampTagParser()
        case .diceEvents:
            DiceEventsParser()
        case .residentAdvisor:
            ResidentAdvisorParser()
        case .venueCalendar:
            VenueCalendarParser()
        case .wordPressPosts:
            WordPressPostsParser()
        case .rssFeed:
            RSSFeedParser()
        case .gitHubTrending:
            GitHubTrendingParser()
        case .genericDiscussion:
            GenericDiscussionParser()
        case .stub:
            StubParser()
        }
    }
}

struct SourcePipeline: Sendable {
    let repository: AppRepository
    let parserFactory: SourceParserFactory

    /// Dev mode: compress non-rate-limited cadence to this floor (in seconds).
    /// Set via MalcomeAPIServer SET_POLITENESS_MODE:dev command. Non-persistent.
    nonisolated(unsafe) static var devCadenceFloorSeconds: TimeInterval?

    func refreshEnabledSources() async throws -> RefreshReport {
        let startedAt = Date()
        let sources = try await repository.fetchSources().filter(\.enabled)
        var completedSnapshots: [SnapshotRecord] = []

        for source in sources {
            let now = Date()

            if let skipReason = politenessSkipReason(for: source, now: now) {
                let snapshot = try await repository.beginSnapshot(sourceID: source.id, startedAt: now)
                let skipped = try await repository.completeSnapshot(
                    snapshotID: snapshot.id,
                    completedAt: now,
                    status: .skipped,
                    itemCount: 0,
                    errorMessage: skipReason
                )
                completedSnapshots.append(skipped)
                continue
            }

            try await repository.updateSourceAttempt(sourceID: source.id, attemptedAt: now)
            let snapshot = try await repository.beginSnapshot(sourceID: source.id, startedAt: now)

            do {
                if source.parserType == .stub {
                    throw SourcePipelineError.parserTODO(sourceName: source.name)
                }
                let observations = try await fetchObservationDrafts(for: source)
                guard !observations.isEmpty else {
                    throw SourcePipelineError.emptyParse(sourceName: source.name)
                }
                let insertedCount = try await repository.storeObservations(snapshotID: snapshot.id, sourceID: source.id, drafts: observations)
                let completed = try await repository.completeSnapshot(
                    snapshotID: snapshot.id,
                    completedAt: Date(),
                    status: .success,
                    itemCount: insertedCount,
                    errorMessage: nil
                )
                completedSnapshots.append(completed)
            } catch {
                let nextBackoff = backoffUntil(for: error, source: source, now: now)
                let failureCount = nextBackoff == nil ? source.consecutiveFailures : source.consecutiveFailures + 1
                try await repository.updateSourceBackoff(
                    sourceID: source.id,
                    backoffUntil: nextBackoff,
                    consecutiveFailures: failureCount
                )
                let failed = try await repository.completeSnapshot(
                    snapshotID: snapshot.id,
                    completedAt: Date(),
                    status: .failed,
                    itemCount: 0,
                    errorMessage: error.localizedDescription
                )
                completedSnapshots.append(failed)
            }
        }

        return RefreshReport(startedAt: startedAt, completedAt: Date(), snapshots: completedSnapshots)
    }

    private func politenessSkipReason(for source: SourceRecord, now: Date) -> String? {
        // 429 backoffs are always respected — these are real rate limits
        if let backoffUntil = source.backoffUntil, backoffUntil > now {
            return "\(source.name) is cooling off until \(Self.displayFormatter.string(from: backoffUntil)) after earlier pushback from the source."
        }

        if let lastAttemptAt = source.lastAttemptAt {
            // In dev mode, use compressed cadence floor (but never below 2 minutes)
            let cadenceSeconds: TimeInterval
            if let devFloor = Self.devCadenceFloorSeconds {
                cadenceSeconds = max(120, devFloor)
            } else {
                cadenceSeconds = TimeInterval(source.refreshCadenceMinutes * 60)
            }
            let minimumRefreshDate = lastAttemptAt.addingTimeInterval(cadenceSeconds)
            if minimumRefreshDate > now {
                return "\(source.name) is waiting for its next polite refresh window at \(Self.displayFormatter.string(from: minimumRefreshDate))."
            }
        }

        return nil
    }

    private func backoffUntil(for error: Error, source: SourceRecord, now: Date) -> Date? {
        let multiplier: Int
        switch error {
        case let pipelineError as SourcePipelineError:
            switch pipelineError {
            case let .httpStatus(code, _) where code == 429:
                multiplier = max(1, source.consecutiveFailures + 1)
            default:
                return nil
            }
        default:
            return nil
        }

        let minutes = source.failureBackoffMinutes * multiplier
        return now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func fetchObservationDrafts(for source: SourceRecord) async throws -> [ObservationDraft] {
        let parser = parserFactory.parser(for: source.parserType)
        let fetchedAt = Date()
        let payload = try await fetchPayload(for: source)
        var observations = parser.parse(source: source, html: payload, fetchedAt: fetchedAt)

        let existingCount = try await repository.observationCount(forSourceID: source.id)
        observations += try await historicalBackfillDrafts(
            for: source,
            parser: parser,
            fetchedAt: fetchedAt,
            existingCount: existingCount
        )

        return dedupeDraftsAcrossPages(observations)
    }

    private func fetchPayload(for source: SourceRecord) async throws -> String {
        switch source.id {
        case "bandcamp-la-discover":
            return try await fetchBandcampAPIResponse(
                source: source,
                requestBody: """
                {"category_id":0,"tag_norm_names":[],"geoname_id":5368361,"slice":"top","cursor":null,"size":24,"include_result_types":["a","s"]}
                """
            )
        case "bandcamp-la-tag":
            return try await fetchBandcampAPIResponse(
                source: source,
                requestBody: """
                {"category_id":0,"tag_norm_names":["los-angeles"],"slice":"top","cursor":null,"size":24,"include_result_types":["a","s"]}
                """
            )
        case "zebulon":
            return try await fetchDiceEventsResponse(
                apiKey: "Z9798C68BR4guDOGqSyFn1oHZfXtL0gW3rU1YZUv",
                venueNames: ["Zebulon"],
                promoterNames: ["Ipsilon, LLC dba Zebulon", "Sid The Cat"],
                itemCount: 24
            )
        case "hyperallergic":
            return try await fetchHTML(from: hyperallergicContentAPIURL(page: 1))
        default:
            if source.parserType == .wordPressPosts {
                return try await fetchHTML(from: wordPressPostsAPIURL(baseURL: source.baseURL, page: 1))
            }
            return try await fetchHTML(from: source.baseURL)
        }
    }

    private func historicalBackfillDrafts(
        for source: SourceRecord,
        parser: any SourceParsing,
        fetchedAt: Date,
        existingCount: Int
    ) async throws -> [ObservationDraft] {
        switch source.id {
        case "aquarium-drunkard":
            guard existingCount < 48 else { return [] }
            return try await fetchArchivePages(
                source: source,
                parser: parser,
                fetchedAt: fetchedAt,
                archivePages: (2...5).map { pageNumber in
                    HistoricalArchivePage(
                        pageNumber: pageNumber,
                        payload: .html(url: "https://aquariumdrunkard.com/wp-json/wp/v2/posts?per_page=12&page=\(pageNumber)")
                    )
                }
            )
        case "hyperallergic":
            guard existingCount < 48 else { return [] }
            return try await fetchArchivePages(
                source: source,
                parser: parser,
                fetchedAt: fetchedAt,
                archivePages: (2...5).map { pageNumber in
                    HistoricalArchivePage(
                        pageNumber: pageNumber,
                        payload: .html(url: hyperallergicContentAPIURL(page: pageNumber))
                    )
                }
            )
        case "bandcamp-la-discover":
            guard existingCount < 48 else { return [] }
            return try await fetchBandcampHistoricalDrafts(
                source: source,
                parser: parser,
                fetchedAt: fetchedAt,
                initialRequestBody: """
                {"category_id":0,"tag_norm_names":[],"geoname_id":5368361,"slice":"top","cursor":null,"size":24,"include_result_types":["a","s"]}
                """,
                pageRange: 2...4
            )
        case _ where source.parserType == .wordPressPosts:
            guard existingCount < 48 else { return [] }
            return try await fetchArchivePages(
                source: source,
                parser: parser,
                fetchedAt: fetchedAt,
                archivePages: (2...5).map { pageNumber in
                    HistoricalArchivePage(
                        pageNumber: pageNumber,
                        payload: .html(url: wordPressPostsAPIURL(baseURL: source.baseURL, page: pageNumber))
                    )
                }
            )
        default:
            return []
        }
    }

    private func fetchArchivePages(
        source: SourceRecord,
        parser: any SourceParsing,
        fetchedAt: Date,
        archivePages: [HistoricalArchivePage]
    ) async throws -> [ObservationDraft] {
        var observations: [ObservationDraft] = []

        for page in archivePages {
            let payload: String
            switch page.payload {
            case let .html(url):
                payload = try await fetchHTML(from: url)
            case let .bandcamp(requestBody):
                payload = try await fetchBandcampAPIResponse(source: source, requestBody: requestBody)
            }

            let drafts = parser.parse(source: source, html: payload, fetchedAt: fetchedAt)
            observations += tagHistoricalBackfillDrafts(
                drafts,
                pageNumber: page.pageNumber,
                source: source
            )
        }

        return observations
    }

    private func fetchBandcampHistoricalDrafts(
        source: SourceRecord,
        parser: any SourceParsing,
        fetchedAt: Date,
        initialRequestBody: String,
        pageRange: ClosedRange<Int>
    ) async throws -> [ObservationDraft] {
        var observations: [ObservationDraft] = []
        var payload = try await fetchBandcampAPIResponse(source: source, requestBody: initialRequestBody)

        for pageNumber in pageRange {
            guard let cursor = bandcampCursor(from: payload) else { break }
            let requestBody = bandcampRequestBody(for: source.id, cursor: cursor, pageSize: 24)
            payload = try await fetchBandcampAPIResponse(source: source, requestBody: requestBody)
            let drafts = parser.parse(source: source, html: payload, fetchedAt: fetchedAt)
            observations += tagHistoricalBackfillDrafts(
                drafts,
                pageNumber: pageNumber,
                source: source
            )
        }

        return observations
    }

    private func hyperallergicContentAPIURL(page: Int, limit: Int = 12) -> String {
        "https://hyperallergic.ghost.io/ghost/api/content/posts/?key=0960c3763f2386b8ea2a9677ee&limit=\(limit)&page=\(page)&fields=title,url,excerpt,published_at"
    }

    private func wordPressPostsAPIURL(baseURL: String, page: Int, limit: Int = 12) -> String {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return "\(trimmed)/wp-json/wp/v2/posts?per_page=\(limit)&page=\(page)"
    }

    private func tagHistoricalBackfillDrafts(
        _ drafts: [ObservationDraft],
        pageNumber: Int,
        source: SourceRecord
    ) -> [ObservationDraft] {
        drafts.map { draft in
            let timelineDate = draft.publishedAt ?? draft.scrapedAt
            let tags = Array(
                Set(draft.tags + ["historical_backfill", "archive_page_\(pageNumber)"])
            ).sorted()
            let metadata = """
            {"backfill":true,"archivePage":\(pageNumber),"timelineDate":"\(ISO8601DateFormatter().string(from: timelineDate))","source":"\(source.id)"}
            """

            return ObservationDraft(
                domain: draft.domain,
                entityType: draft.entityType,
                externalIDOrHash: draft.externalIDOrHash,
                title: draft.title,
                subtitle: draft.subtitle,
                url: draft.url,
                authorOrArtist: draft.authorOrArtist,
                tags: tags,
                location: draft.location,
                publishedAt: draft.publishedAt,
                scrapedAt: timelineDate,
                excerpt: draft.excerpt,
                normalizedEntityName: draft.normalizedEntityName,
                rawPayload: draft.rawPayload + metadata
            )
        }
    }

    private func dedupeDraftsAcrossPages(_ drafts: [ObservationDraft]) -> [ObservationDraft] {
        var seen: Set<String> = []
        var deduped: [ObservationDraft] = []

        for draft in drafts {
            if seen.insert(draft.externalIDOrHash).inserted {
                deduped.append(draft)
            }
        }

        return deduped
    }

    private func bandcampCursor(from payload: String) -> String? {
        guard
            let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cursor = json["cursor"] as? String,
            !cursor.isEmpty
        else {
            return nil
        }
        return cursor
    }

    private func bandcampRequestBody(for sourceID: String, cursor: String, pageSize: Int) -> String {
        switch sourceID {
        case "bandcamp-la-discover":
            return """
            {"category_id":0,"tag_norm_names":[],"geoname_id":5368361,"slice":"top","cursor":"\(cursor)","size":\(pageSize),"include_result_types":["a","s"]}
            """
        case "bandcamp-la-tag":
            return """
            {"category_id":0,"tag_norm_names":["los-angeles"],"slice":"top","cursor":"\(cursor)","size":\(pageSize),"include_result_types":["a","s"]}
            """
        default:
            return """
            {"category_id":0,"tag_norm_names":[],"cursor":"\(cursor)","size":\(pageSize),"include_result_types":["a","s"]}
            """
        }
    }

    private func fetchHTML(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw SourcePipelineError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Malcome/1.0 (iOS cool-hunting prototype)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw SourcePipelineError.httpStatus(code: httpResponse.statusCode, url: urlString)
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw SourcePipelineError.decodeFailure(url: urlString)
        }
        return html
    }

    private func fetchBandcampAPIResponse(source: SourceRecord, requestBody: String) async throws -> String {
        guard let url = URL(string: "https://bandcamp.com/api/discover/1/discover_web") else {
            throw SourcePipelineError.invalidURL("https://bandcamp.com/api/discover/1/discover_web")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = Data(requestBody.utf8)
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://bandcamp.com", forHTTPHeaderField: "Origin")
        request.setValue(source.baseURL, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw SourcePipelineError.httpStatus(code: httpResponse.statusCode, url: url.absoluteString)
        }

        guard let body = String(data: data, encoding: .utf8) else {
            throw SourcePipelineError.decodeFailure(url: url.absoluteString)
        }

        if body.contains(#""__api_special__":"exception""#) {
            throw SourcePipelineError.bandcampAPIFailure(sourceName: source.name)
        }

        return body
    }

    private func fetchDiceEventsResponse(
        apiKey: String,
        venueNames: [String],
        promoterNames: [String],
        itemCount: Int
    ) async throws -> String {
        guard var components = URLComponents(string: "https://partners-endpoint.dice.fm/api/v2/events") else {
            throw SourcePipelineError.invalidURL("https://partners-endpoint.dice.fm/api/v2/events")
        }

        var items = [
            URLQueryItem(name: "page[size]", value: String(itemCount)),
            URLQueryItem(name: "types", value: "linkout,event"),
            URLQueryItem(name: "filter[flags][]", value: "going_ahead"),
            URLQueryItem(name: "filter[flags][]", value: "rescheduled"),
            URLQueryItem(name: "filter[flags][]", value: "postponed"),
        ]
        items += venueNames.map { URLQueryItem(name: "filter[venues][]", value: $0) }
        items += promoterNames.map { URLQueryItem(name: "filter[promoters][]", value: $0) }
        components.queryItems = items

        guard let url = components.url else {
            throw SourcePipelineError.invalidURL("https://partners-endpoint.dice.fm/api/v2/events")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw SourcePipelineError.httpStatus(code: httpResponse.statusCode, url: url.absoluteString)
        }

        guard let body = String(data: data, encoding: .utf8) else {
            throw SourcePipelineError.decodeFailure(url: url.absoluteString)
        }

        return body
    }
}

extension SourcePipeline {
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct HistoricalArchivePage: Sendable {
    let pageNumber: Int
    let payload: HistoricalArchivePayload
}

private enum HistoricalArchivePayload: Sendable {
    case html(url: String)
    case bandcamp(requestBody: String)
}

struct BandcampTagParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" {
            let apiDrafts = apiResponseDrafts(source: source, payload: trimmed, fetchedAt: fetchedAt)
            if !apiDrafts.isEmpty {
                return dedupe(Array(apiDrafts.prefix(24)))
            }
        }

        let blobDrafts = dataBlobDrafts(source: source, html: html, fetchedAt: fetchedAt)
        if !blobDrafts.isEmpty {
            return dedupe(Array(blobDrafts.prefix(24)))
        }

        let anchors = HTMLSupport.extractAnchors(from: html)
        let candidates = anchors.filter { anchor in
            anchor.href.contains("/album/") || anchor.href.contains("/track/")
        }

        return dedupe(candidates.prefix(24).map { anchor in
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
        else {
            return []
        }

        return results.compactMap { result -> ObservationDraft? in
            guard
                let rawURL = result["item_url"] as? String,
                let rawTitle = result["title"] as? String,
                let bandName = result["band_name"] as? String
            else {
                return nil
            }

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
                domain: source.domain,
                entityType: .creator,
                externalIDOrHash: HTMLSupport.hash(url),
                title: title,
                subtitle: artist,
                url: url,
                authorOrArtist: artist,
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
        guard
            let blob = HTMLSupport.extractDataBlobJSON(from: html),
            let data = blob.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return []
        }

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
                author: resolvedArtist,
                fallbackURL: resolvedURL
            )

            guard !resolvedURL.isEmpty, !resolvedTitle.isEmpty else { return nil }

            let excerptParts = [resolvedArtist, featuredTrack].compactMap { value -> String? in
                guard let value else { return nil }
                let cleaned = HTMLSupport.cleanText(value)
                return cleaned.isEmpty ? nil : cleaned
            }

            return ObservationDraft(
                domain: source.domain,
                entityType: .creator,
                externalIDOrHash: HTMLSupport.hash(resolvedURL),
                title: resolvedTitle,
                subtitle: resolvedArtist,
                url: resolvedURL,
                authorOrArtist: resolvedArtist,
                tags: ["bandcamp", source.city.displayName.lowercased()],
                location: source.city.displayName,
                publishedAt: nil,
                scrapedAt: fetchedAt,
                excerpt: excerptParts.isEmpty ? "Surfacing on \(source.name)." : excerptParts.joined(separator: " • "),
                normalizedEntityName: normalized,
                rawPayload: String(describing: candidate)
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

            if hasURL && hasIdentity {
                matches.append(dict)
            }

            for value in dict.values {
                walkBandcamp(value: value, matches: &matches)
            }
        } else if let array = value as? [Any] {
            for value in array {
                walkBandcamp(value: value, matches: &matches)
            }
        }
    }

    nonisolated private func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !HTMLSupport.cleanText(value).isEmpty {
                return value
            }
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

struct ResidentAdvisorParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let jsonLDEvents = VenueCalendarParser.jsonLDEventDrafts(source: source, html: html, fetchedAt: fetchedAt)
        if !jsonLDEvents.isEmpty {
            return jsonLDEvents
        }

        let anchors = HTMLSupport.extractAnchors(from: html)
        let candidates = anchors.filter { anchor in
            anchor.href.contains("/events/") || anchor.text.localizedCaseInsensitiveContains("live")
        }

        return dedupe(candidates.prefix(20).map { anchor in
            let url = HTMLSupport.absoluteURL(anchor.href, relativeTo: source.baseURL)
            let normalized = HTMLSupport.normalizedEntityName(title: anchor.text, author: nil, fallbackURL: url)

            return ObservationDraft(
                domain: source.domain,
                entityType: .event,
                externalIDOrHash: HTMLSupport.hash(url),
                title: anchor.text,
                subtitle: "Resident Advisor event listing",
                url: url,
                authorOrArtist: nil,
                tags: ["resident-advisor", "la"],
                location: source.city.displayName,
                publishedAt: nil,
                scrapedAt: fetchedAt,
                excerpt: "Listed on \(source.name).",
                normalizedEntityName: normalized,
                rawPayload: "{\"href\":\"\(url)\"}"
            )
        })
    }
}

struct DiceEventsParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        guard
            let data = html.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let events = json["data"] as? [[String: Any]]
        else {
            return []
        }

        return dedupe(events.compactMap { event in
            guard
                let id = event["id"] as? String,
                let name = event["name"] as? String,
                let url = event["url"] as? String
            else {
                return nil
            }

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
                domain: source.domain,
                entityType: .event,
                externalIDOrHash: HTMLSupport.hash(id + url),
                title: title,
                subtitle: venueName,
                url: url,
                authorOrArtist: title,
                tags: ["dice-event", "venue-calendar"] + genreTags,
                location: venueName,
                publishedAt: publishedAt,
                scrapedAt: fetchedAt,
                excerpt: noteParts.isEmpty ? "Upcoming show spotted on \(source.name)." : noteParts.joined(separator: " • "),
                normalizedEntityName: HTMLSupport.inferredEntityName(from: title, author: title, fallbackURL: url),
                rawPayload: String(describing: event)
            )
        })
    }
}

struct VenueCalendarParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        let sourceSpecificDrafts = sourceSpecificDrafts(source: source, html: html, fetchedAt: fetchedAt)
        if !sourceSpecificDrafts.isEmpty {
            return dedupe(Array(sourceSpecificDrafts.prefix(18)))
        }

        let jsonLDEvents = Self.jsonLDEventDrafts(source: source, html: html, fetchedAt: fetchedAt)
        if !jsonLDEvents.isEmpty {
            return dedupe(jsonLDEvents.prefix(18).map { $0 })
        }

        let anchors = HTMLSupport.extractAnchors(from: html)
        let candidates = anchors.filter { anchor in
            let lower = anchor.text.lowercased()
            let href = anchor.href.lowercased()
            let looksLikeEventPath = href.contains("/events/") || href.contains("/shows/") || href.contains("ticketmaster.com/")
            return lower.count > 6 && looksLikeEventPath && !lower.contains("tickets") && !lower.contains("calendar")
        }

        return dedupe(candidates.prefix(18).map { anchor in
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

        return dedupe(items.prefix(15).map { $0 })
    }
}

struct GenericDiscussionParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        if source.id == "aquarium-drunkard" {
            let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.first == "[" || trimmed.first == "{" {
                let apiDrafts = aquariumDrunkardAPIDrafts(source: source, payload: trimmed, fetchedAt: fetchedAt)
                if !apiDrafts.isEmpty {
                    return dedupe(Array(apiDrafts.prefix(12)))
                }
            }
            let drafts = aquariumDrunkardDrafts(source: source, html: html, fetchedAt: fetchedAt)
            if !drafts.isEmpty {
                return dedupe(Array(drafts.prefix(12)))
            }
        }

        if source.id == "hyperallergic" {
            let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.first == "{" {
                let apiDrafts = hyperallergicAPIDrafts(source: source, payload: trimmed, fetchedAt: fetchedAt)
                if !apiDrafts.isEmpty {
                    return dedupe(Array(apiDrafts.prefix(12)))
                }
            }
            let drafts = hyperallergicDrafts(source: source, html: html, fetchedAt: fetchedAt)
            if !drafts.isEmpty {
                return dedupe(Array(drafts.prefix(12)))
            }
        }

        let anchors = HTMLSupport.extractAnchors(from: html)
        let candidates = anchors.filter { anchor in
            HTMLSupport.isMeaningfulEntityName(anchor.text) && anchor.href.contains("/202")
        }

        return dedupe(candidates.prefix(12).map { anchor in
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

        return dedupe(posts.compactMap { post in
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

struct RSSFeedParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        guard let data = html.data(using: .utf8) else { return [] }
        let items = RSSFeedDocument.parse(data: data)

        return dedupe(items.compactMap { item in
            let title = HTMLSupport.cleanText(item.displayTitle)
            let rawURL = HTMLSupport.cleanText(item.link)
            let url = HTMLSupport.absoluteURL(rawURL, relativeTo: source.baseURL)

            guard !title.isEmpty, !url.isEmpty else { return nil }

            let excerpt = HTMLSupport.cleanText(item.description)
            let creator = item.creator.map(HTMLSupport.cleanText) ?? ""

            // When dc:creator provides a clean artist name, use it for entity resolution
            // instead of trying to extract an entity from the full title (which may be a
            // credit string like "Artist, Artist, 'Release Title'").
            let subject: (name: String, entityType: EntityType, author: String?)
            let normalized: String

            let isStaffByline = HTMLSupport.isStaffByline(creator, sourceName: source.name)
            // For editorial sources, the dc:creator is a journalist/editor byline, not a cultural entity.
            // The subject lives in the headline. Only use dc:creator for non-editorial sources
            // (discovery, community, venue) where the author IS the artist.
            let isEditorialSource = source.classification == .editorial

            if !creator.isEmpty, !isStaffByline, !isEditorialSource,
               !HTMLSupport.isLikelyCreditString(creator),
               HTMLSupport.isMeaningfulEntityName(HTMLSupport.normalizedAlias(creator)) {
                let cleanCreator = HTMLSupport.cleanText(creator)
                subject = (name: cleanCreator, entityType: .creator, author: cleanCreator)
                normalized = HTMLSupport.normalizedEntityName(
                    title: cleanCreator,
                    author: cleanCreator,
                    fallbackURL: url
                )
            } else {
                subject = HTMLSupport.inferredEditorialEntity(
                    from: title,
                    sourceName: source.name,
                    fallbackURL: url
                )
                normalized = HTMLSupport.normalizedEntityName(
                    title: subject.name,
                    author: subject.author,
                    fallbackURL: url
                )
            }

            guard HTMLSupport.isMeaningfulEntityName(normalized) else { return nil }

            let categoryTags = item.categories
                .map(HTMLSupport.cleanText)
                .filter { !$0.isEmpty }
                .map(HTMLSupport.normalizedAlias)

            let tags = Array(Set([
                "editorial",
                source.domain.rawValue,
                source.classification.rawValue
            ] + HTMLSupport.editorialContentTags(for: title, sourceName: source.name) + categoryTags)).sorted()

            return ObservationDraft(
                domain: source.domain,
                entityType: subject.entityType,
                externalIDOrHash: HTMLSupport.hash(url),
                title: title,
                subtitle: source.name,
                url: url,
                authorOrArtist: subject.author ?? (creator.isEmpty ? nil : creator),
                tags: tags,
                location: source.city == .global ? nil : source.city.displayName,
                publishedAt: item.publishedAt,
                scrapedAt: fetchedAt,
                excerpt: excerpt.isEmpty ? "Surfacing on \(source.name)." : excerpt,
                normalizedEntityName: normalized,
                rawPayload: item.rawPayload
            )
        })
    }
}

private struct RSSFeedItem: Sendable {
    let title: String
    let plainTitle: String?
    let link: String
    let description: String
    let creator: String?
    let publishedAt: Date?
    let categories: [String]
    let rawPayload: String

    nonisolated var displayTitle: String {
        let preferred = HTMLSupport.cleanText(plainTitle ?? "")
        return preferred.isEmpty ? title : preferred
    }
}

private enum RSSFeedDocument {
    nonisolated static func parse(data: Data) -> [RSSFeedItem] {
        let delegate = RSSFeedParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }
}

private final class RSSFeedParserDelegate: NSObject, XMLParserDelegate {
    private var currentItem: RSSFeedDraft?
    private var currentElement = ""
    private var currentText = ""

    nonisolated(unsafe) fileprivate private(set) var items: [RSSFeedItem] = []

    nonisolated override init() {
        super.init()
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        let name = qName ?? elementName
        if name == "item" {
            currentItem = RSSFeedDraft()
        }
        currentElement = name
        currentText = ""
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = qName ?? elementName
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if var item = currentItem {
            switch name {
            case "title":
                item.title = text
            case "plainTitle":
                if !text.isEmpty {
                    item.plainTitle = text
                }
            case "link":
                item.link = text
            case "description", "content:encoded":
                if !text.isEmpty, item.description.isEmpty {
                    item.description = text
                }
            case "dc:creator", "author", "media:credit":
                if !text.isEmpty {
                    item.creator = text
                }
            case "pubDate":
                item.pubDate = text
            case "dc:date":
                item.isoDate = text
            case "category":
                if !text.isEmpty {
                    item.categories.append(text)
                }
            case "item":
                if let built = item.build() {
                    items.append(built)
                }
                currentItem = nil
            default:
                break
            }
            currentItem = item
        }

        currentElement = ""
        currentText = ""
    }
}

private struct RSSFeedDraft {
    var title = ""
    var plainTitle: String?
    var link = ""
    var description = ""
    var creator: String?
    var pubDate = ""
    var isoDate = ""
    var categories: [String] = []

    func build() -> RSSFeedItem? {
        guard !title.isEmpty, !link.isEmpty else { return nil }

        return RSSFeedItem(
            title: title,
            plainTitle: plainTitle,
            link: link,
            description: description,
            creator: creator,
            publishedAt: RSSFeedDraft.parseDate(pubDate) ?? RSSFeedDraft.parseISODate(isoDate),
            categories: categories,
            rawPayload: "{\"title\":\"\(title)\",\"link\":\"\(link)\"}"
        )
    }

    private static func parseDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: raw)
    }

    private static func parseISODate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: raw) {
            return parsed
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

struct StubParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        []
    }
}

enum SourcePipelineError: LocalizedError {
    case invalidURL(String)
    case httpStatus(code: Int, url: String)
    case decodeFailure(url: String)
    case emptyParse(sourceName: String)
    case parserTODO(sourceName: String)
    case bandcampAPIFailure(sourceName: String)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return "Invalid source URL: \(url)"
        case let .httpStatus(code, url):
            return "Request failed with HTTP \(code) for \(url)."
        case let .decodeFailure(url):
            return "Fetched data from \(url) but could not decode the page."
        case let .emptyParse(sourceName):
            return "\(sourceName) came through, but Malcome could not pull usable observations from it this pass."
        case let .parserTODO(sourceName):
            return "\(sourceName) is on Malcome's watchlist, but that ingestion path is not live yet."
        case let .bandcampAPIFailure(sourceName):
            return "\(sourceName) reached Bandcamp, but the discover endpoint rejected the request."
        }
    }
}

nonisolated private func dedupe(_ drafts: [ObservationDraft]) -> [ObservationDraft] {
    var seen = Set<String>()
    var unique: [ObservationDraft] = []

    for draft in drafts where seen.insert(draft.externalIDOrHash).inserted {
        unique.append(draft)
    }
    return unique
}
