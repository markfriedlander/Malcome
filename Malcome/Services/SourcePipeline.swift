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
                var observations = try await fetchObservationDrafts(for: source)
                guard !observations.isEmpty else {
                    throw SourcePipelineError.emptyParse(sourceName: source.name)
                }
                // Expand roundup articles into per-entity observations
                observations = await expandRoundupDrafts(observations, source: source)
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

    /// Expands roundup-tagged drafts into per-entity observations using AFM extraction.
    /// Non-roundup drafts pass through unchanged. If extraction fails, the original draft is kept.
    private func expandRoundupDrafts(_ drafts: [ObservationDraft], source: SourceRecord) async -> [ObservationDraft] {
        var expanded: [ObservationDraft] = []

        for draft in drafts {
            if draft.tags.contains("roundup") {
                let entities = await RoundupExtractor.extractEntities(
                    title: draft.title,
                    excerpt: draft.excerpt ?? ""
                )

                if entities.isEmpty {
                    // No entities extracted — keep the original roundup observation
                    expanded.append(draft)
                } else {
                    // Store original as a roundup_source concept
                    let roundupSourceDraft = ObservationDraft(
                        domain: draft.domain,
                        entityType: .concept,
                        externalIDOrHash: draft.externalIDOrHash,
                        title: draft.title,
                        subtitle: draft.subtitle,
                        url: draft.url,
                        authorOrArtist: nil,
                        tags: draft.tags + ["roundup_source"],
                        location: draft.location,
                        publishedAt: draft.publishedAt,
                        scrapedAt: draft.scrapedAt,
                        excerpt: draft.excerpt,
                        normalizedEntityName: draft.normalizedEntityName,
                        rawPayload: draft.rawPayload
                    )
                    expanded.append(roundupSourceDraft)

                    // Add per-entity drafts
                    let entityDrafts = RoundupExtractor.draftsFromExtraction(
                        entities: entities,
                        originalTitle: draft.title,
                        originalURL: draft.url,
                        originalExcerpt: draft.excerpt ?? "",
                        source: source,
                        fetchedAt: draft.scrapedAt,
                        publishedAt: draft.publishedAt,
                        tags: draft.tags
                    )
                    expanded.append(contentsOf: entityDrafts)
                }
            } else {
                expanded.append(draft)
            }
        }

        return expanded
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
            guard existingCount < 150 else { return [] }
            return try await fetchArchivePages(
                source: source,
                parser: parser,
                fetchedAt: fetchedAt,
                archivePages: (2...12).map { pageNumber in
                    HistoricalArchivePage(
                        pageNumber: pageNumber,
                        payload: .html(url: "https://aquariumdrunkard.com/wp-json/wp/v2/posts?per_page=12&page=\(pageNumber)")
                    )
                }
            )
        case "hyperallergic":
            guard existingCount < 150 else { return [] }
            return try await fetchArchivePages(
                source: source,
                parser: parser,
                fetchedAt: fetchedAt,
                archivePages: (2...12).map { pageNumber in
                    HistoricalArchivePage(
                        pageNumber: pageNumber,
                        payload: .html(url: hyperallergicContentAPIURL(page: pageNumber))
                    )
                }
            )
        case "bandcamp-la-discover":
            guard existingCount < 150 else { return [] }
            return try await fetchBandcampHistoricalDrafts(
                source: source,
                parser: parser,
                fetchedAt: fetchedAt,
                initialRequestBody: """
                {"category_id":0,"tag_norm_names":[],"geoname_id":5368361,"slice":"top","cursor":null,"size":24,"include_result_types":["a","s"]}
                """,
                pageRange: 2...6
            )
        case _ where source.parserType == .wordPressPosts:
            guard existingCount < 150 else { return [] }
            return try await fetchArchivePages(
                source: source,
                parser: parser,
                fetchedAt: fetchedAt,
                archivePages: (2...10).map { pageNumber in
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
