import Foundation
import SQLite3

actor AppRepository {
    private let database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let dateFormatter = ISO8601DateFormatter()

    init(databaseURL: URL? = nil) {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        do {
            let resolvedURL = try Self.databaseURL(override: databaseURL)
            var db: OpaquePointer?
            if sqlite3_open(resolvedURL.path, &db) != SQLITE_OK {
                throw RepositoryError.message("Unable to open database at \(resolvedURL.path)")
            }
            self.database = db
            try Self.configure(database: db)
            try Self.migrate(database: db)
        } catch {
            preconditionFailure("Database setup failed: \(error.localizedDescription)")
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func seedSourcesIfNeeded(_ seeds: [SourceSeed]) throws {
        for seed in seeds {
            try execute(
                """
                INSERT INTO source (
                    id, name, module_id, module_name, source_family_id, source_family_name, domain, classification, tier, base_url, city, parser_type, enabled, justification,
                    refresh_cadence_minutes, failure_backoff_minutes, last_attempt_at, backoff_until, consecutive_failures, last_success_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, 0, NULL)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    module_id = excluded.module_id,
                    module_name = excluded.module_name,
                    source_family_id = excluded.source_family_id,
                    source_family_name = excluded.source_family_name,
                    domain = excluded.domain,
                    classification = excluded.classification,
                    tier = excluded.tier,
                    base_url = excluded.base_url,
                    city = excluded.city,
                    parser_type = excluded.parser_type,
                    justification = excluded.justification,
                    refresh_cadence_minutes = excluded.refresh_cadence_minutes,
                    failure_backoff_minutes = excluded.failure_backoff_minutes
                """,
                values: [
                    .text(seed.id),
                    .text(seed.name),
                    .text(seed.moduleID),
                    .text(seed.moduleName),
                    .text(seed.sourceFamilyID),
                    .text(seed.sourceFamilyName),
                    .text(seed.domain.rawValue),
                    .text(seed.classification.rawValue),
                    .text(seed.tier.rawValue),
                    .text(seed.baseURL),
                    .text(seed.city.rawValue),
                    .text(seed.parserType.rawValue),
                    .int(seed.enabled ? 1 : 0),
                    .text(seed.justification),
                    .int(seed.refreshCadenceMinutes),
                    .int(seed.failureBackoffMinutes),
                ]
            )
        }

        if !seeds.isEmpty {
            let placeholders = Array(repeating: "?", count: seeds.count).joined(separator: ", ")
            try execute(
                "UPDATE source SET enabled = 0 WHERE id NOT IN (\(placeholders))",
                values: seeds.map { .text($0.id) }
            )
        }
    }

    func fetchSources() throws -> [SourceRecord] {
        try query(
            """
            SELECT id, name, module_id, module_name, source_family_id, source_family_name, domain, classification, tier, base_url, city, parser_type, enabled, justification,
                   refresh_cadence_minutes, failure_backoff_minutes, last_attempt_at, backoff_until, consecutive_failures, last_success_at
            FROM source
            ORDER BY module_name ASC, name ASC
            """
        ) { statement in
            SourceRecord(
                id: text(statement, 0),
                name: text(statement, 1),
                moduleID: text(statement, 2),
                moduleName: text(statement, 3),
                sourceFamilyID: text(statement, 4),
                sourceFamilyName: text(statement, 5),
                domain: CulturalDomain(rawValue: text(statement, 6)) ?? .generalCulture,
                classification: SourceClassification(rawValue: text(statement, 7)) ?? .editorial,
                tier: SourceTier(rawValue: text(statement, 8)) ?? .c,
                baseURL: text(statement, 9),
                city: SourceCity(rawValue: text(statement, 10)) ?? .losAngeles,
                parserType: ParserType(rawValue: text(statement, 11)) ?? .stub,
                enabled: int(statement, 12) == 1,
                justification: text(statement, 13),
                refreshCadenceMinutes: int(statement, 14),
                failureBackoffMinutes: int(statement, 15),
                lastAttemptAt: date(statement, 16),
                backoffUntil: date(statement, 17),
                consecutiveFailures: int(statement, 18),
                lastSuccessAt: date(statement, 19)
            )
        }
    }

    func setSourceEnabled(sourceID: String, isEnabled: Bool) throws {
        try execute(
            "UPDATE source SET enabled = ? WHERE id = ?",
            values: [.int(isEnabled ? 1 : 0), .text(sourceID)]
        )
    }

    func setModuleEnabled(moduleID: String, isEnabled: Bool) throws {
        try execute(
            "UPDATE source SET enabled = ? WHERE module_id = ?",
            values: [.int(isEnabled ? 1 : 0), .text(moduleID)]
        )
    }

    func updateSourceAttempt(sourceID: String, attemptedAt: Date) throws {
        try execute(
            "UPDATE source SET last_attempt_at = ? WHERE id = ?",
            values: [.text(string(from: attemptedAt)), .text(sourceID)]
        )
    }

    func updateSourceBackoff(sourceID: String, backoffUntil: Date?, consecutiveFailures: Int) throws {
        let backoffString = backoffUntil.map { string(from: $0) }
        try execute(
            "UPDATE source SET backoff_until = ?, consecutive_failures = ? WHERE id = ?",
            values: [.nullOrText(backoffString), .int(consecutiveFailures), .text(sourceID)]
        )
    }

    func sourceStatuses() throws -> [SourceStatusRecord] {
        let sources = try fetchSources()
        var statuses: [SourceStatusRecord] = []

        for source in sources {
            let latestSnapshot = try querySingle(
                """
                SELECT id, source_id, started_at, completed_at, status, item_count, error_message
                FROM snapshot
                WHERE source_id = ?
                ORDER BY started_at DESC
                LIMIT 1
                """,
                values: [.text(source.id)]
            ) { statement in
                SnapshotRecord(
                    id: text(statement, 0),
                    sourceID: text(statement, 1),
                    startedAt: requiredDate(statement, 2),
                    completedAt: date(statement, 3),
                    status: SnapshotStatus(rawValue: text(statement, 4)) ?? .failed,
                    itemCount: int(statement, 5),
                    errorMessage: nullableText(statement, 6)
                )
            }

            statuses.append(SourceStatusRecord(id: source.id, source: source, latestSnapshot: latestSnapshot))
        }

        return statuses
    }

    func beginSnapshot(sourceID: String, startedAt: Date) throws -> SnapshotRecord {
        let snapshot = SnapshotRecord(
            id: UUID().uuidString,
            sourceID: sourceID,
            startedAt: startedAt,
            completedAt: nil,
            status: .running,
            itemCount: 0,
            errorMessage: nil
        )

        try execute(
            """
            INSERT INTO snapshot (id, source_id, started_at, completed_at, status, item_count, error_message)
            VALUES (?, ?, ?, NULL, ?, ?, NULL)
            """,
            values: [
                .text(snapshot.id),
                .text(snapshot.sourceID),
                .text(string(from: snapshot.startedAt)),
                .text(snapshot.status.rawValue),
                .int(snapshot.itemCount),
            ]
        )

        return snapshot
    }

    func completeSnapshot(
        snapshotID: String,
        completedAt: Date,
        status: SnapshotStatus,
        itemCount: Int,
        errorMessage: String?
    ) throws -> SnapshotRecord {
        try execute(
            """
            UPDATE snapshot
            SET completed_at = ?, status = ?, item_count = ?, error_message = ?
            WHERE id = ?
            """,
            values: [
                .text(string(from: completedAt)),
                .text(status.rawValue),
                .int(itemCount),
                .nullOrText(errorMessage),
                .text(snapshotID),
            ]
        )

        if status == .success {
            let sourceID = try queryValue(
                "SELECT source_id FROM snapshot WHERE id = ?",
                values: [.text(snapshotID)]
            )
            try execute(
                "UPDATE source SET last_success_at = ?, backoff_until = NULL, consecutive_failures = 0 WHERE id = ?",
                values: [.text(string(from: completedAt)), .text(sourceID)]
            )
        }

        guard let snapshot = try snapshot(id: snapshotID) else {
            throw RepositoryError.message("Updated snapshot \(snapshotID) was not found")
        }
        return snapshot
    }

    func storeObservations(snapshotID: String, sourceID: String, drafts: [ObservationDraft]) throws -> Int {
        var insertedCount = 0
        for draft in drafts {
            if try observationExists(sourceID: sourceID, draft: draft) {
                continue
            }
            let observation = ObservationRecord(
                id: UUID().uuidString,
                sourceID: sourceID,
                snapshotID: snapshotID,
                canonicalEntityID: "",
                domain: draft.domain,
                entityType: draft.entityType,
                externalIDOrHash: draft.externalIDOrHash,
                title: draft.title,
                subtitle: draft.subtitle,
                url: draft.url,
                authorOrArtist: draft.authorOrArtist,
                tags: draft.tags,
                location: draft.location,
                publishedAt: draft.publishedAt,
                scrapedAt: draft.scrapedAt,
                excerpt: draft.excerpt,
                distilledExcerpt: nil,
                normalizedEntityName: draft.normalizedEntityName,
                rawPayload: draft.rawPayload
            )
            try insert(observation: observation)
            insertedCount += 1
        }
        return insertedCount
    }

    func observationCount(forSourceID sourceID: String) throws -> Int {
        try queryCount(
            "SELECT COUNT(*) FROM observation WHERE source_id = ?",
            values: [.text(sourceID)]
        )
    }

    func fetchObservations(since: Date? = nil, limit: Int? = nil) throws -> [ObservationRecord] {
        var sql = """
        SELECT id, source_id, snapshot_id, canonical_entity_id, external_id_or_hash, title, subtitle, url,
               author_or_artist, tags_json, location, published_at, scraped_at,
               excerpt, normalized_entity_name, raw_payload, domain, entity_type, distilled_excerpt
        FROM observation
        """
        var values: [SQLValue] = []

        if let since {
            sql += " WHERE scraped_at >= ?"
            values.append(.text(string(from: since)))
        }

        sql += " ORDER BY scraped_at DESC"
        if let limit {
            sql += " LIMIT \(limit)"
        }

        return try query(sql, values: values) { statement in
            ObservationRecord(
                id: text(statement, 0),
                sourceID: text(statement, 1),
                snapshotID: text(statement, 2),
                canonicalEntityID: text(statement, 3),
                domain: CulturalDomain(rawValue: text(statement, 16)) ?? .generalCulture,
                entityType: EntityType(rawValue: text(statement, 17)) ?? .unknown,
                externalIDOrHash: text(statement, 4),
                title: text(statement, 5),
                subtitle: nullableText(statement, 6),
                url: text(statement, 7),
                authorOrArtist: nullableText(statement, 8),
                tags: decodeStringArray(from: nullableText(statement, 9)),
                location: nullableText(statement, 10),
                publishedAt: date(statement, 11),
                scrapedAt: requiredDate(statement, 12),
                excerpt: nullableText(statement, 13),
                distilledExcerpt: nullableText(statement, 18),
                normalizedEntityName: text(statement, 14),
                rawPayload: text(statement, 15)
            )
        }
    }

    func replaceSignalCandidates(_ signals: [SignalCandidateRecord]) throws {
        try execute("DELETE FROM signal_candidate", values: [])
        for signal in signals {
            try execute(
                """
                INSERT INTO signal_candidate (
                    id, canonical_entity_id, domain, canonical_name, entity_type, first_seen_at, latest_seen_at, source_count,
                    observation_count, current_source_count, current_source_family_count, current_observation_count, historical_source_count, historical_observation_count, growth_score, diversity_score, repeat_appearance_score, progression_score,
                    saturation_score, emergence_score, confidence, movement, maturity, lifecycle_state, conversion_state, outcome_tiers_json, supporting_sources_json,
                    progression_stages_json, progression_pattern, movement_summary, maturity_summary, lifecycle_summary, conversion_summary, pathway_summary, source_influence_summary, progression_summary, evidence_summary
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                values: [
                    .text(signal.id),
                    .text(signal.canonicalEntityID),
                    .text(signal.domain.rawValue),
                    .text(signal.canonicalName),
                    .text(signal.entityType.rawValue),
                    .text(string(from: signal.firstSeenAt)),
                    .text(string(from: signal.latestSeenAt)),
                    .int(signal.sourceCount),
                    .int(signal.observationCount),
                    .int(signal.currentSourceCount),
                    .int(signal.currentSourceFamilyCount),
                    .int(signal.currentObservationCount),
                    .int(signal.historicalSourceCount),
                    .int(signal.historicalObservationCount),
                    .double(signal.growthScore),
                    .double(signal.diversityScore),
                    .double(signal.repeatAppearanceScore),
                    .double(signal.progressionScore),
                    .double(signal.saturationScore),
                    .double(signal.emergenceScore),
                    .double(signal.confidence),
                    .text(signal.movement.rawValue),
                    .text(signal.maturity.rawValue),
                    .text(signal.lifecycleState.rawValue),
                    .text(signal.conversionState.rawValue),
                    .text(encode(signal.outcomeTiers.map(\.rawValue))),
                    .text(encode(signal.supportingSourceIDs)),
                    .text(encode(signal.progressionStages.map(\.rawValue))),
                    .text(signal.progressionPattern),
                    .text(signal.movementSummary),
                    .text(signal.maturitySummary),
                    .text(signal.lifecycleSummary),
                    .text(signal.conversionSummary),
                    .text(signal.pathwaySummary),
                    .text(signal.sourceInfluenceSummary),
                    .text(signal.progressionSummary),
                    .text(signal.evidenceSummary),
                ]
            )
        }
    }

    func fetchTopSignals(limit: Int = 10, includeInactive: Bool = false) throws -> [SignalCandidateRecord] {
        let activeFilter = includeInactive
            ? ""
            : "WHERE source_count > 0 AND observation_count > 0 AND lifecycle_state NOT IN ('failed', 'disappeared')"
        return try query(
            """
            SELECT id, canonical_entity_id, domain, canonical_name, entity_type, first_seen_at, latest_seen_at, source_count, observation_count,
                   current_source_count, current_source_family_count, current_observation_count, historical_source_count, historical_observation_count,
                   growth_score, diversity_score, repeat_appearance_score, progression_score, saturation_score,
                   emergence_score, confidence, movement, maturity, lifecycle_state, conversion_state, outcome_tiers_json, supporting_sources_json, progression_stages_json,
                   progression_pattern, movement_summary, maturity_summary, lifecycle_summary, conversion_summary, pathway_summary, source_influence_summary, progression_summary, evidence_summary
            FROM signal_candidate
            \(activeFilter)
            ORDER BY emergence_score DESC, latest_seen_at DESC
            LIMIT \(limit)
            """
        ) { statement in
            SignalCandidateRecord(
                id: text(statement, 0),
                canonicalEntityID: text(statement, 1),
                domain: CulturalDomain(rawValue: text(statement, 2)) ?? .generalCulture,
                canonicalName: text(statement, 3),
                entityType: EntityType(rawValue: text(statement, 4)) ?? .unknown,
                firstSeenAt: requiredDate(statement, 5),
                latestSeenAt: requiredDate(statement, 6),
                sourceCount: int(statement, 7),
                observationCount: int(statement, 8),
                currentSourceCount: int(statement, 9),
                currentSourceFamilyCount: int(statement, 10),
                currentObservationCount: int(statement, 11),
                historicalSourceCount: int(statement, 12),
                historicalObservationCount: int(statement, 13),
                growthScore: double(statement, 14),
                diversityScore: double(statement, 15),
                repeatAppearanceScore: double(statement, 16),
                progressionScore: double(statement, 17),
                saturationScore: double(statement, 18),
                emergenceScore: double(statement, 19),
                confidence: double(statement, 20),
                movement: SignalMovement(rawValue: text(statement, 21)) ?? .new,
                maturity: SignalMaturity(rawValue: text(statement, 22)) ?? .earlyEmergence,
                lifecycleState: SignalLifecycleState(rawValue: text(statement, 23)) ?? .emerging,
                conversionState: ConversionState(rawValue: text(statement, 24)) ?? .pending,
                outcomeTiers: decodeOutcomeTiers(from: nullableText(statement, 25)),
                supportingSourceIDs: decodeStringArray(from: nullableText(statement, 26)),
                progressionStages: decodeSourceClassifications(from: nullableText(statement, 27)),
                progressionPattern: text(statement, 28),
                movementSummary: text(statement, 29),
                maturitySummary: text(statement, 30),
                lifecycleSummary: text(statement, 31),
                conversionSummary: text(statement, 32),
                pathwaySummary: text(statement, 33),
                sourceInfluenceSummary: text(statement, 34),
                progressionSummary: text(statement, 35),
                evidenceSummary: text(statement, 36)
            )
        }
    }

    func fetchCanonicalEntities(limit: Int = 50) throws -> [CanonicalEntityRecord] {
        try query(
            """
            SELECT id, display_name, domain, entity_type, aliases_json, merge_confidence, merge_summary
            FROM canonical_entity
            ORDER BY merge_confidence ASC, display_name ASC
            LIMIT \(limit)
            """
        ) { statement in
            CanonicalEntityRecord(
                id: text(statement, 0),
                displayName: text(statement, 1),
                domain: CulturalDomain(rawValue: text(statement, 2)) ?? .generalCulture,
                entityType: EntityType(rawValue: text(statement, 3)) ?? .unknown,
                aliases: decodeStringArray(from: nullableText(statement, 4)),
                mergeConfidence: double(statement, 5),
                mergeSummary: text(statement, 6)
            )
        }
    }

    func fetchAmbiguousCanonicalEntities(limit: Int = 20, confidenceThreshold: Double = 0.9) throws -> [CanonicalEntityRecord] {
        try query(
            """
            SELECT id, display_name, domain, entity_type, aliases_json, merge_confidence, merge_summary
            FROM canonical_entity
            WHERE merge_confidence < ?
            ORDER BY merge_confidence ASC, display_name ASC
            LIMIT \(limit)
            """,
            values: [.double(confidenceThreshold)]
        ) { statement in
            CanonicalEntityRecord(
                id: text(statement, 0),
                displayName: text(statement, 1),
                domain: CulturalDomain(rawValue: text(statement, 2)) ?? .generalCulture,
                entityType: EntityType(rawValue: text(statement, 3)) ?? .unknown,
                aliases: decodeStringArray(from: nullableText(statement, 4)),
                mergeConfidence: double(statement, 5),
                mergeSummary: text(statement, 6)
            )
        }
    }

    func canonicalEntity(id: String) throws -> CanonicalEntityRecord? {
        try querySingle(
            """
            SELECT id, display_name, domain, entity_type, aliases_json, merge_confidence, merge_summary
            FROM canonical_entity
            WHERE id = ?
            LIMIT 1
            """,
            values: [.text(id)]
        ) { statement in
            CanonicalEntityRecord(
                id: text(statement, 0),
                displayName: text(statement, 1),
                domain: CulturalDomain(rawValue: text(statement, 2)) ?? .generalCulture,
                entityType: EntityType(rawValue: text(statement, 3)) ?? .unknown,
                aliases: decodeStringArray(from: nullableText(statement, 4)),
                mergeConfidence: double(statement, 5),
                mergeSummary: text(statement, 6)
            )
        }
    }

    func entityAliases(forCanonicalEntityID canonicalEntityID: String) throws -> [EntityAliasRecord] {
        try query(
            """
            SELECT id, canonical_entity_id, alias_text, normalized_alias, source_id
            FROM entity_alias
            WHERE canonical_entity_id = ?
            ORDER BY normalized_alias ASC, alias_text ASC
            """,
            values: [.text(canonicalEntityID)]
        ) { statement in
            EntityAliasRecord(
                id: text(statement, 0),
                canonicalEntityID: text(statement, 1),
                aliasText: text(statement, 2),
                normalizedAlias: text(statement, 3),
                sourceID: nullableText(statement, 4)
            )
        }
    }

    func entitySourceRoles(forCanonicalEntityID canonicalEntityID: String) throws -> [EntitySourceRoleRecord] {
        try query(
            """
            SELECT id, canonical_entity_id, source_id, source_classification, first_seen_at, last_seen_at, appearance_count
            FROM entity_source_role
            WHERE canonical_entity_id = ?
            ORDER BY first_seen_at ASC, source_id ASC
            """,
            values: [.text(canonicalEntityID)]
        ) { statement in
            EntitySourceRoleRecord(
                id: text(statement, 0),
                canonicalEntityID: text(statement, 1),
                sourceID: text(statement, 2),
                sourceClassification: SourceClassification(rawValue: text(statement, 3)) ?? .editorial,
                firstSeenAt: requiredDate(statement, 4),
                lastSeenAt: requiredDate(statement, 5),
                appearanceCount: int(statement, 6)
            )
        }
    }

    func replaceCanonicalIdentityGraph(
        entities: [CanonicalEntityRecord],
        aliases: [EntityAliasRecord],
        sourceRoles: [EntitySourceRoleRecord],
        observationMappings: [String: String]
    ) throws {
        try execute("DELETE FROM entity_stage_snapshot", values: [])
        try execute("DELETE FROM entity_source_role", values: [])
        try execute("DELETE FROM entity_alias", values: [])
        try execute("DELETE FROM canonical_entity", values: [])

        for entity in entities {
            try execute(
                """
                INSERT INTO canonical_entity (id, display_name, domain, entity_type, aliases_json, merge_confidence, merge_summary)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                values: [
                    .text(entity.id),
                    .text(entity.displayName),
                    .text(entity.domain.rawValue),
                    .text(entity.entityType.rawValue),
                    .text(encode(entity.aliases)),
                    .double(entity.mergeConfidence),
                    .text(entity.mergeSummary),
                ]
            )
        }

        for alias in aliases {
            try execute(
                """
                INSERT INTO entity_alias (id, canonical_entity_id, alias_text, normalized_alias, source_id)
                VALUES (?, ?, ?, ?, ?)
                """,
                values: [
                    .text(alias.id),
                    .text(alias.canonicalEntityID),
                    .text(alias.aliasText),
                    .text(alias.normalizedAlias),
                    .nullOrText(alias.sourceID),
                ]
            )
        }

        for role in sourceRoles {
            try execute(
                """
                INSERT INTO entity_source_role (
                    id, canonical_entity_id, source_id, source_classification, first_seen_at, last_seen_at, appearance_count
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                values: [
                    .text(role.id),
                    .text(role.canonicalEntityID),
                    .text(role.sourceID),
                    .text(role.sourceClassification.rawValue),
                    .text(string(from: role.firstSeenAt)),
                    .text(string(from: role.lastSeenAt)),
                    .int(role.appearanceCount),
                ]
            )
        }

        for (observationID, canonicalEntityID) in observationMappings {
            try execute(
                "UPDATE observation SET canonical_entity_id = ? WHERE id = ?",
                values: [.text(canonicalEntityID), .text(observationID)]
            )
        }
    }

    // MARK: - Chat Messages

    func storeChatMessage(id: String, briefID: String, role: String, content: String, timestamp: Date, turnNumber: Int) throws {
        try execute(
            """
            INSERT INTO chat_message (id, brief_id, role, content, timestamp, turn_number)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            values: [
                .text(id),
                .text(briefID),
                .text(role),
                .text(content),
                .int(Int(timestamp.timeIntervalSince1970)),
                .int(turnNumber),
            ]
        )
    }

    func fetchChatMessages(briefID: String) throws -> [ChatMessageRecord] {
        try query(
            "SELECT id, brief_id, role, content, timestamp, turn_number FROM chat_message WHERE brief_id = ? ORDER BY turn_number ASC",
            values: [.text(briefID)]
        ) { statement in
            ChatMessageRecord(
                id: text(statement, 0),
                briefID: text(statement, 1),
                role: text(statement, 2),
                content: text(statement, 3),
                timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 4))),
                turnNumber: Int(sqlite3_column_int(statement, 5))
            )
        }
    }

    func clearChatMessages(excludingBriefID currentBriefID: String) throws {
        try execute(
            "DELETE FROM chat_message WHERE brief_id != ?",
            values: [.text(currentBriefID)]
        )
    }

    func chatMessageCount(briefID: String) throws -> Int {
        try queryCount(
            "SELECT COUNT(*) FROM chat_message WHERE brief_id = ?",
            values: [.text(briefID)]
        )
    }

    // MARK: - Identity Graph

    func renormalizeObservations() throws -> Int {
        let observations = try fetchObservations()
        let sources = try fetchSources()
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

        var updatedCount = 0
        for obs in observations {
            guard let source = sourcesByID[obs.sourceID] else { continue }

            let newNormalized = HTMLSupport.renormalizedEntityName(
                title: obs.title,
                authorOrArtist: obs.authorOrArtist,
                url: obs.url,
                parserType: source.parserType,
                sourceName: source.name,
                sourceClassification: source.classification
            )

            // Also fix authorOrArtist if it's a credit string, staff byline, or editorial byline
            let newAuthor: String?
            if let author = obs.authorOrArtist {
                if HTMLSupport.isStaffByline(author, sourceName: source.name) {
                    newAuthor = nil
                } else if source.classification == .editorial && source.parserType == .rssFeed {
                    // Editorial RSS bylines are journalist names, not cultural entities
                    newAuthor = nil
                } else if HTMLSupport.isLikelyCreditString(author) {
                    let lead = HTMLSupport.extractLeadArtist(from: author)
                    newAuthor = lead.isEmpty ? obs.authorOrArtist : lead
                } else {
                    newAuthor = obs.authorOrArtist
                }
            } else {
                newAuthor = nil
            }

            let nameChanged = newNormalized != obs.normalizedEntityName
            let authorChanged = newAuthor != obs.authorOrArtist

            if nameChanged || authorChanged {
                try execute(
                    "UPDATE observation SET normalized_entity_name = ?, author_or_artist = ? WHERE id = ?",
                    values: [.text(newNormalized), .nullOrText(newAuthor), .text(obs.id)]
                )
                updatedCount += 1
            }
        }

        try resetIdentityGraph()
        return updatedCount
    }

    func resetIdentityGraph() throws {
        // Surgical delete of the identity resolution layer only.
        // Order matters due to foreign key constraints.
        try execute("DELETE FROM entity_stage_snapshot", values: [])
        try execute("DELETE FROM entity_source_role", values: [])
        try execute("DELETE FROM entity_alias", values: [])
        try execute("DELETE FROM canonical_entity", values: [])
        try execute("DELETE FROM entity_history", values: [])
        try execute("UPDATE observation SET canonical_entity_id = ''", values: [])
    }

    func replaceEntityStageSnapshots(_ snapshots: [EntityStageSnapshotRecord]) throws {
        try execute("DELETE FROM entity_stage_snapshot", values: [])
        for snapshot in snapshots {
            try execute(
                """
                INSERT INTO entity_stage_snapshot (
                    id, canonical_entity_id, date, stage, source_count, signal_score
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                values: [
                    .text(snapshot.id),
                    .text(snapshot.canonicalEntityID),
                    .text(dayString(from: snapshot.date)),
                    .text(snapshot.stage.rawValue),
                    .int(snapshot.sourceCount),
                    .double(snapshot.signalScore),
                ]
            )
        }
    }

    func stageSnapshots(for canonicalEntityID: String, limit: Int = 90) throws -> [EntityStageSnapshotRecord] {
        try query(
            """
            SELECT id, canonical_entity_id, date, stage, source_count, signal_score
            FROM entity_stage_snapshot
            WHERE canonical_entity_id = ?
            ORDER BY date DESC
            LIMIT \(limit)
            """,
            values: [.text(canonicalEntityID)]
        ) { statement in
            EntityStageSnapshotRecord(
                id: text(statement, 0),
                canonicalEntityID: text(statement, 1),
                date: requiredDay(statement, 2),
                stage: SourceClassification(rawValue: text(statement, 3)) ?? .editorial,
                sourceCount: int(statement, 4),
                signalScore: double(statement, 5)
            )
        }
    }

    func replaceEntityHistories(_ histories: [EntityHistoryRecord]) throws {
        try execute("DELETE FROM entity_history", values: [])
        for history in histories {
            try execute(
                """
                INSERT INTO entity_history (
                    id, canonical_entity_id, canonical_name, domain, entity_type, first_seen_at, last_seen_at,
                    appearance_count, source_diversity, lifecycle_state, lifecycle_summary, conversion_state, conversion_summary
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                values: [
                    .text(history.id),
                    .text(history.canonicalEntityID),
                    .text(history.canonicalName),
                    .text(history.domain.rawValue),
                    .text(history.entityType.rawValue),
                    .text(string(from: history.firstSeenAt)),
                    .text(string(from: history.lastSeenAt)),
                    .int(history.appearanceCount),
                    .int(history.sourceDiversity),
                    .text(history.lifecycleState.rawValue),
                    .text(history.lifecycleSummary),
                    .text(history.conversionState.rawValue),
                    .text(history.conversionSummary),
                ]
            )
        }
    }

    func entityHistory(forCanonicalName canonicalName: String) throws -> EntityHistoryRecord? {
        try querySingle(
            """
            SELECT id, canonical_entity_id, canonical_name, domain, entity_type, first_seen_at, last_seen_at,
                   appearance_count, source_diversity, lifecycle_state, lifecycle_summary, conversion_state, conversion_summary
            FROM entity_history
            WHERE canonical_name = ? OR canonical_entity_id = ?
            LIMIT 1
            """,
            values: [.text(canonicalName), .text(canonicalName)]
        ) { statement in
            EntityHistoryRecord(
                id: text(statement, 0),
                canonicalEntityID: text(statement, 1),
                canonicalName: text(statement, 2),
                domain: CulturalDomain(rawValue: text(statement, 3)) ?? .generalCulture,
                entityType: EntityType(rawValue: text(statement, 4)) ?? .unknown,
                firstSeenAt: requiredDate(statement, 5),
                lastSeenAt: requiredDate(statement, 6),
                appearanceCount: int(statement, 7),
                sourceDiversity: int(statement, 8),
                lifecycleState: SignalLifecycleState(rawValue: text(statement, 9)) ?? .emerging,
                lifecycleSummary: text(statement, 10),
                conversionState: ConversionState(rawValue: text(statement, 11)) ?? .pending,
                conversionSummary: text(statement, 12)
            )
        }
    }

    func entityHistories(forCanonicalEntityIDs canonicalEntityIDs: [String]) throws -> [String: EntityHistoryRecord] {
        let ids = Array(Set(canonicalEntityIDs.filter { !$0.isEmpty }))
        guard !ids.isEmpty else { return [:] }

        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        let rows = try query(
            """
            SELECT id, canonical_entity_id, canonical_name, domain, entity_type, first_seen_at, last_seen_at,
                   appearance_count, source_diversity, lifecycle_state, lifecycle_summary, conversion_state, conversion_summary
            FROM entity_history
            WHERE canonical_entity_id IN (\(placeholders))
            """,
            values: ids.map(SQLValue.text)
        ) { statement in
            EntityHistoryRecord(
                id: text(statement, 0),
                canonicalEntityID: text(statement, 1),
                canonicalName: text(statement, 2),
                domain: CulturalDomain(rawValue: text(statement, 3)) ?? .generalCulture,
                entityType: EntityType(rawValue: text(statement, 4)) ?? .unknown,
                firstSeenAt: requiredDate(statement, 5),
                lastSeenAt: requiredDate(statement, 6),
                appearanceCount: int(statement, 7),
                sourceDiversity: int(statement, 8),
                lifecycleState: SignalLifecycleState(rawValue: text(statement, 9)) ?? .emerging,
                lifecycleSummary: text(statement, 10),
                conversionState: ConversionState(rawValue: text(statement, 11)) ?? .pending,
                conversionSummary: text(statement, 12)
            )
        }

        return Dictionary(uniqueKeysWithValues: rows.map { ($0.canonicalEntityID, $0) })
    }

    func storeSignalRuns(_ runs: [SignalRunRecord]) throws {
        for run in runs {
            try execute(
                """
                INSERT INTO signal_run (
                    id, run_at, canonical_entity_id, canonical_name, domain, entity_type, rank, score,
                    supporting_sources_json, observation_count, source_count, current_source_count, current_source_family_count, current_observation_count, historical_source_count, historical_observation_count, movement, maturity, lifecycle_state, conversion_state, outcome_tiers_json, progression_pattern, explanation, lifecycle_summary, conversion_summary
                    , source_influence_summary
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                values: [
                    .text(run.id),
                    .text(string(from: run.runAt)),
                    .text(run.canonicalEntityID),
                    .text(run.canonicalName),
                    .text(run.domain.rawValue),
                    .text(run.entityType.rawValue),
                    .int(run.rank),
                    .double(run.score),
                    .text(encode(run.supportingSourceIDs)),
                    .int(run.observationCount),
                    .int(run.sourceCount),
                    .int(run.currentSourceCount),
                    .int(run.currentSourceFamilyCount),
                    .int(run.currentObservationCount),
                    .int(run.historicalSourceCount),
                    .int(run.historicalObservationCount),
                    .text(run.movement.rawValue),
                    .text(run.maturity.rawValue),
                    .text(run.lifecycleState.rawValue),
                    .text(run.conversionState.rawValue),
                    .text(encode(run.outcomeTiers.map(\.rawValue))),
                    .text(run.progressionPattern),
                    .text(run.explanation),
                    .text(run.lifecycleSummary),
                    .text(run.conversionSummary),
                    .text(run.sourceInfluenceSummary),
                ]
            )
        }
    }

    func latestSignalRunsByCanonicalName() throws -> [String: SignalRunRecord] {
        let runs = try query(
            """
            SELECT id, run_at, canonical_entity_id, canonical_name, domain, entity_type, rank, score,
                   supporting_sources_json, observation_count, source_count, current_source_count, current_source_family_count, current_observation_count, historical_source_count, historical_observation_count, movement, maturity, lifecycle_state, conversion_state, outcome_tiers_json, progression_pattern, explanation, lifecycle_summary, conversion_summary, source_influence_summary
            FROM signal_run
            ORDER BY run_at DESC
            """
        ) { statement in
            SignalRunRecord(
                id: text(statement, 0),
                runAt: requiredDate(statement, 1),
                canonicalEntityID: text(statement, 2),
                canonicalName: text(statement, 3),
                domain: CulturalDomain(rawValue: text(statement, 4)) ?? .generalCulture,
                entityType: EntityType(rawValue: text(statement, 5)) ?? .unknown,
                rank: int(statement, 6),
                score: double(statement, 7),
                supportingSourceIDs: decodeStringArray(from: nullableText(statement, 8)),
                observationCount: int(statement, 9),
                sourceCount: int(statement, 10),
                currentSourceCount: int(statement, 11),
                currentSourceFamilyCount: int(statement, 12),
                currentObservationCount: int(statement, 13),
                historicalSourceCount: int(statement, 14),
                historicalObservationCount: int(statement, 15),
                movement: SignalMovement(rawValue: text(statement, 16)) ?? .new,
                maturity: SignalMaturity(rawValue: text(statement, 17)) ?? .earlyEmergence,
                lifecycleState: SignalLifecycleState(rawValue: text(statement, 18)) ?? .emerging,
                conversionState: ConversionState(rawValue: text(statement, 19)) ?? .pending,
                outcomeTiers: decodeOutcomeTiers(from: nullableText(statement, 20)),
                progressionPattern: text(statement, 21),
                explanation: text(statement, 22),
                lifecycleSummary: text(statement, 23),
                conversionSummary: text(statement, 24),
                sourceInfluenceSummary: text(statement, 25)
            )
        }

        var latestByName: [String: SignalRunRecord] = [:]
        for run in runs {
            let key = run.canonicalEntityID.isEmpty ? run.canonicalName : run.canonicalEntityID
            if latestByName[key] == nil {
                latestByName[key] = run
            }
        }
        return latestByName
    }

    func signalRuns(forCanonicalName canonicalName: String, limit: Int = 10) throws -> [SignalRunRecord] {
        try query(
            """
            SELECT id, run_at, canonical_entity_id, canonical_name, domain, entity_type, rank, score,
                   supporting_sources_json, observation_count, source_count, current_source_count, current_source_family_count, current_observation_count, historical_source_count, historical_observation_count, movement, maturity, lifecycle_state, conversion_state, outcome_tiers_json, progression_pattern, explanation, lifecycle_summary, conversion_summary, source_influence_summary
            FROM signal_run
            WHERE canonical_name = ? OR canonical_entity_id = ?
            ORDER BY run_at DESC
            LIMIT \(limit)
            """,
            values: [.text(canonicalName), .text(canonicalName)]
        ) { statement in
            SignalRunRecord(
                id: text(statement, 0),
                runAt: requiredDate(statement, 1),
                canonicalEntityID: text(statement, 2),
                canonicalName: text(statement, 3),
                domain: CulturalDomain(rawValue: text(statement, 4)) ?? .generalCulture,
                entityType: EntityType(rawValue: text(statement, 5)) ?? .unknown,
                rank: int(statement, 6),
                score: double(statement, 7),
                supportingSourceIDs: decodeStringArray(from: nullableText(statement, 8)),
                observationCount: int(statement, 9),
                sourceCount: int(statement, 10),
                currentSourceCount: int(statement, 11),
                currentSourceFamilyCount: int(statement, 12),
                currentObservationCount: int(statement, 13),
                historicalSourceCount: int(statement, 14),
                historicalObservationCount: int(statement, 15),
                movement: SignalMovement(rawValue: text(statement, 16)) ?? .new,
                maturity: SignalMaturity(rawValue: text(statement, 17)) ?? .earlyEmergence,
                lifecycleState: SignalLifecycleState(rawValue: text(statement, 18)) ?? .emerging,
                conversionState: ConversionState(rawValue: text(statement, 19)) ?? .pending,
                outcomeTiers: decodeOutcomeTiers(from: nullableText(statement, 20)),
                progressionPattern: text(statement, 21),
                explanation: text(statement, 22),
                lifecycleSummary: text(statement, 23),
                conversionSummary: text(statement, 24),
                sourceInfluenceSummary: text(statement, 25)
            )
        }
    }

    func recentSignalRuns(limit: Int = 400) throws -> [SignalRunRecord] {
        try query(
            """
            SELECT id, run_at, canonical_entity_id, canonical_name, domain, entity_type, rank, score,
                   supporting_sources_json, observation_count, source_count, current_source_count, current_source_family_count, current_observation_count, historical_source_count, historical_observation_count, movement, maturity, lifecycle_state, conversion_state, outcome_tiers_json, progression_pattern, explanation, lifecycle_summary, conversion_summary, source_influence_summary
            FROM signal_run
            ORDER BY run_at DESC
            LIMIT \(limit)
            """
        ) { statement in
            SignalRunRecord(
                id: text(statement, 0),
                runAt: requiredDate(statement, 1),
                canonicalEntityID: text(statement, 2),
                canonicalName: text(statement, 3),
                domain: CulturalDomain(rawValue: text(statement, 4)) ?? .generalCulture,
                entityType: EntityType(rawValue: text(statement, 5)) ?? .unknown,
                rank: int(statement, 6),
                score: double(statement, 7),
                supportingSourceIDs: decodeStringArray(from: nullableText(statement, 8)),
                observationCount: int(statement, 9),
                sourceCount: int(statement, 10),
                currentSourceCount: int(statement, 11),
                currentSourceFamilyCount: int(statement, 12),
                currentObservationCount: int(statement, 13),
                historicalSourceCount: int(statement, 14),
                historicalObservationCount: int(statement, 15),
                movement: SignalMovement(rawValue: text(statement, 16)) ?? .new,
                maturity: SignalMaturity(rawValue: text(statement, 17)) ?? .earlyEmergence,
                lifecycleState: SignalLifecycleState(rawValue: text(statement, 18)) ?? .emerging,
                conversionState: ConversionState(rawValue: text(statement, 19)) ?? .pending,
                outcomeTiers: decodeOutcomeTiers(from: nullableText(statement, 20)),
                progressionPattern: text(statement, 21),
                explanation: text(statement, 22),
                lifecycleSummary: text(statement, 23),
                conversionSummary: text(statement, 24),
                sourceInfluenceSummary: text(statement, 25)
            )
        }
    }

    func appendPathwayHistory(_ histories: [PathwayHistoryRecord]) throws {
        for history in histories {
            try execute(
                """
                INSERT INTO pathway_history (
                    id, run_at, canonical_entity_id, pathway_pattern, domain, lifecycle_state, conversion_state, signal_score
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                values: [
                    .text(history.id),
                    .text(string(from: history.runAt)),
                    .text(history.canonicalEntityID),
                    .text(history.pathwayPattern),
                    .text(history.domain.rawValue),
                    .text(history.lifecycleState.rawValue),
                    .text(history.conversionState.rawValue),
                    .double(history.signalScore),
                ]
            )
        }
    }

    func replacePathwayStats(_ stats: [PathwayStatRecord]) throws {
        try execute("DELETE FROM pathway_stat", values: [])
        for stat in stats {
            try execute(
                """
                INSERT INTO pathway_stat (
                    id, pathway_pattern, domain, sample_count, advancing_count, peaked_count,
                    cooling_count, failed_count, disappeared_count, success_weight, failure_weight,
                    conversion_count, stalled_conversion_count, never_converted_count, conversion_weight,
                    predictive_score, summary
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                values: [
                    .text(stat.id),
                    .text(stat.pathwayPattern),
                    .text(stat.domain.rawValue),
                    .int(stat.sampleCount),
                    .int(stat.advancingCount),
                    .int(stat.peakedCount),
                    .int(stat.coolingCount),
                    .int(stat.failedCount),
                    .int(stat.disappearedCount),
                    .double(stat.successWeight),
                    .double(stat.failureWeight),
                    .int(stat.conversionCount),
                    .int(stat.stalledConversionCount),
                    .int(stat.neverConvertedCount),
                    .double(stat.conversionWeight),
                    .double(stat.predictiveScore),
                    .text(stat.summary),
                ]
            )
        }
    }

    func fetchPathwayStats(limit: Int = 200) throws -> [PathwayStatRecord] {
        try query(
            """
            SELECT id, pathway_pattern, domain, sample_count, advancing_count, peaked_count,
                   cooling_count, failed_count, disappeared_count, success_weight, failure_weight,
                   conversion_count, stalled_conversion_count, never_converted_count, conversion_weight,
                   predictive_score, summary
            FROM pathway_stat
            ORDER BY predictive_score DESC, sample_count DESC
            LIMIT \(limit)
            """
        ) { statement in
            PathwayStatRecord(
                id: text(statement, 0),
                pathwayPattern: text(statement, 1),
                domain: CulturalDomain(rawValue: text(statement, 2)) ?? .generalCulture,
                sampleCount: int(statement, 3),
                advancingCount: int(statement, 4),
                peakedCount: int(statement, 5),
                coolingCount: int(statement, 6),
                failedCount: int(statement, 7),
                disappearedCount: int(statement, 8),
                successWeight: double(statement, 9),
                failureWeight: double(statement, 10),
                conversionCount: int(statement, 11),
                stalledConversionCount: int(statement, 12),
                neverConvertedCount: int(statement, 13),
                conversionWeight: double(statement, 14),
                predictiveScore: double(statement, 15),
                summary: text(statement, 16)
            )
        }
    }

    func replaceSourceInfluenceStats(_ stats: [SourceInfluenceStatRecord]) throws {
        try execute("DELETE FROM source_influence_stat", values: [])
        for stat in stats {
            try execute(
                """
                INSERT INTO source_influence_stat (
                    id, scope, scope_key, display_name, domain, sample_count, advancing_count, peaked_count,
                    failed_count, disappeared_count, conversion_count, stalled_conversion_count,
                    never_converted_count, average_signal_score, predictive_score, summary
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                values: [
                    .text(stat.id),
                    .text(stat.scope.rawValue),
                    .text(stat.scopeKey),
                    .text(stat.displayName),
                    .text(stat.domain.rawValue),
                    .int(stat.sampleCount),
                    .int(stat.advancingCount),
                    .int(stat.peakedCount),
                    .int(stat.failedCount),
                    .int(stat.disappearedCount),
                    .int(stat.conversionCount),
                    .int(stat.stalledConversionCount),
                    .int(stat.neverConvertedCount),
                    .double(stat.averageSignalScore),
                    .double(stat.predictiveScore),
                    .text(stat.summary),
                ]
            )
        }
    }

    func fetchSourceInfluenceStats(limit: Int = 200) throws -> [SourceInfluenceStatRecord] {
        try query(
            """
            SELECT id, scope, scope_key, display_name, domain, sample_count, advancing_count, peaked_count,
                   failed_count, disappeared_count, conversion_count, stalled_conversion_count,
                   never_converted_count, average_signal_score, predictive_score, summary
            FROM source_influence_stat
            ORDER BY predictive_score DESC, sample_count DESC
            LIMIT \(limit)
            """
        ) { statement in
            SourceInfluenceStatRecord(
                id: text(statement, 0),
                scope: SourceInfluenceScope(rawValue: text(statement, 1)) ?? .source,
                scopeKey: text(statement, 2),
                displayName: text(statement, 3),
                domain: CulturalDomain(rawValue: text(statement, 4)) ?? .generalCulture,
                sampleCount: int(statement, 5),
                advancingCount: int(statement, 6),
                peakedCount: int(statement, 7),
                failedCount: int(statement, 8),
                disappearedCount: int(statement, 9),
                conversionCount: int(statement, 10),
                stalledConversionCount: int(statement, 11),
                neverConvertedCount: int(statement, 12),
                averageSignalScore: double(statement, 13),
                predictiveScore: double(statement, 14),
                summary: text(statement, 15)
            )
        }
    }

    func replaceOutcomeConfirmations(_ confirmations: [OutcomeConfirmationRecord]) throws {
        try execute("DELETE FROM outcome_confirmation", values: [])
        for confirmation in confirmations {
            try execute(
                """
                INSERT INTO outcome_confirmation (
                    id, canonical_entity_id, outcome_tier, confirmed_at, source_ids_json, summary
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                values: [
                    .text(confirmation.id),
                    .text(confirmation.canonicalEntityID),
                    .text(confirmation.outcomeTier.rawValue),
                    .text(string(from: confirmation.confirmedAt)),
                    .text(encode(confirmation.sourceIDs)),
                    .text(confirmation.summary),
                ]
            )
        }
    }

    func outcomeConfirmations(for canonicalEntityID: String) throws -> [OutcomeConfirmationRecord] {
        try query(
            """
            SELECT id, canonical_entity_id, outcome_tier, confirmed_at, source_ids_json, summary
            FROM outcome_confirmation
            WHERE canonical_entity_id = ?
            ORDER BY confirmed_at DESC
            """,
            values: [.text(canonicalEntityID)]
        ) { statement in
            OutcomeConfirmationRecord(
                id: text(statement, 0),
                canonicalEntityID: text(statement, 1),
                outcomeTier: DownstreamOutcomeTier(rawValue: text(statement, 2)) ?? .majorEditorialCoverage,
                confirmedAt: requiredDate(statement, 3),
                sourceIDs: decodeStringArray(from: nullableText(statement, 4)),
                summary: text(statement, 5)
            )
        }
    }

    func observations(forCanonicalEntityID canonicalEntityID: String, limit: Int = 12) throws -> [ObservationRecord] {
        try query(
            """
            SELECT id, source_id, snapshot_id, canonical_entity_id, external_id_or_hash, title, subtitle, url,
                   author_or_artist, tags_json, location, published_at, scraped_at,
                   excerpt, normalized_entity_name, raw_payload, domain, entity_type, distilled_excerpt
            FROM observation
            WHERE canonical_entity_id = ?
            ORDER BY scraped_at DESC
            LIMIT \(limit)
            """,
            values: [.text(canonicalEntityID)]
        ) { statement in
            ObservationRecord(
                id: text(statement, 0),
                sourceID: text(statement, 1),
                snapshotID: text(statement, 2),
                canonicalEntityID: text(statement, 3),
                domain: CulturalDomain(rawValue: text(statement, 16)) ?? .generalCulture,
                entityType: EntityType(rawValue: text(statement, 17)) ?? .unknown,
                externalIDOrHash: text(statement, 4),
                title: text(statement, 5),
                subtitle: nullableText(statement, 6),
                url: text(statement, 7),
                authorOrArtist: nullableText(statement, 8),
                tags: decodeStringArray(from: nullableText(statement, 9)),
                location: nullableText(statement, 10),
                publishedAt: date(statement, 11),
                scrapedAt: requiredDate(statement, 12),
                excerpt: nullableText(statement, 13),
                distilledExcerpt: nullableText(statement, 18),
                normalizedEntityName: text(statement, 14),
                rawPayload: text(statement, 15)
            )
        }
    }

    func storeBrief(_ brief: BriefRecord) throws {
        try execute("DELETE FROM brief", values: [])
        try execute(
            """
            INSERT INTO brief (id, generated_at, title, body, citations_payload, period_type)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            values: [
                .text(brief.id),
                .text(string(from: brief.generatedAt)),
                .text(brief.title),
                .text(brief.body),
                .text(encode(brief.citationsPayload)),
                .text(brief.periodType.rawValue),
            ]
        )
    }

    func fetchLatestBrief() throws -> BriefRecord? {
        try querySingle(
            """
            SELECT id, generated_at, title, body, citations_payload, period_type
            FROM brief
            ORDER BY generated_at DESC
            LIMIT 1
            """
        ) { statement in
            BriefRecord(
                id: text(statement, 0),
                generatedAt: requiredDate(statement, 1),
                title: text(statement, 2),
                body: text(statement, 3),
                citationsPayload: decodeCitations(from: text(statement, 4)),
                periodType: BriefPeriodType(rawValue: text(statement, 5)) ?? .daily
            )
        }
    }

    func latestSuccessfulRefreshDate() throws -> Date? {
        try querySingle(
            """
            SELECT completed_at
            FROM snapshot
            WHERE status = 'success'
            ORDER BY completed_at DESC
            LIMIT 1
            """
        ) { statement in
            date(statement, 0)
        } ?? nil
    }

    func snapshot(id: String) throws -> SnapshotRecord? {
        try querySingle(
            """
            SELECT id, source_id, started_at, completed_at, status, item_count, error_message
            FROM snapshot
            WHERE id = ?
            LIMIT 1
            """,
            values: [.text(id)]
        ) { statement in
            SnapshotRecord(
                id: text(statement, 0),
                sourceID: text(statement, 1),
                startedAt: requiredDate(statement, 2),
                completedAt: date(statement, 3),
                status: SnapshotStatus(rawValue: text(statement, 4)) ?? .failed,
                itemCount: int(statement, 5),
                errorMessage: nullableText(statement, 6)
            )
        }
    }

    private func insert(observation: ObservationRecord) throws {
        try execute(
            """
            INSERT INTO observation (
                id, source_id, snapshot_id, canonical_entity_id, external_id_or_hash, title, subtitle, url,
                author_or_artist, tags_json, location, published_at, scraped_at, excerpt,
                normalized_entity_name, raw_payload, domain, entity_type, distilled_excerpt
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            values: [
                .text(observation.id),
                .text(observation.sourceID),
                .text(observation.snapshotID),
                .text(observation.canonicalEntityID),
                .text(observation.externalIDOrHash),
                .text(observation.title),
                .nullOrText(observation.subtitle),
                .text(observation.url),
                .nullOrText(observation.authorOrArtist),
                .text(encode(observation.tags)),
                .nullOrText(observation.location),
                .nullOrText(observation.publishedAt.map(string(from:))),
                .text(string(from: observation.scrapedAt)),
                .nullOrText(observation.excerpt),
                .text(observation.normalizedEntityName),
                .text(observation.rawPayload),
                .text(observation.domain.rawValue),
                .text(observation.entityType.rawValue),
                .nullOrText(observation.distilledExcerpt),
            ]
        )
    }

    func updateDistilledExcerpt(observationID: String, distilledExcerpt: String) throws {
        try execute(
            "UPDATE observation SET distilled_excerpt = ? WHERE id = ?",
            values: [.text(distilledExcerpt), .text(observationID)]
        )
    }

    private func observationExists(sourceID: String, draft: ObservationDraft) throws -> Bool {
        let eventDuplicateCount: Int
        if draft.eventInstanceKey != nil {
            eventDuplicateCount = try queryCount(
                """
                SELECT COUNT(*)
                FROM observation
                WHERE source_id = ?
                  AND normalized_entity_name = ?
                  AND COALESCE(location, '') = COALESCE(?, '')
                  AND COALESCE(published_at, '') = COALESCE(?, '')
                  AND entity_type IN ('event', 'event_series')
                """,
                values: [
                    .text(sourceID),
                    .text(draft.normalizedEntityName),
                    .text(draft.location ?? ""),
                    .text(draft.publishedAt.map(string(from:)) ?? "")
                ]
            )
        } else {
            eventDuplicateCount = 0
        }

        if eventDuplicateCount > 0 {
            return true
        }

        return try queryCount(
            """
            SELECT COUNT(*)
            FROM observation
            WHERE source_id = ?
              AND (
                external_id_or_hash = ?
                OR (
                    url = ?
                    AND COALESCE(published_at, '') = COALESCE(?, '')
                )
              )
            """,
            values: [
                .text(sourceID),
                .text(draft.externalIDOrHash),
                .text(draft.url),
                .text(draft.publishedAt.map(string(from:)) ?? "")
            ]
        ) > 0
    }

    private static func configure(database: OpaquePointer?) throws {
        try execute(database: database, sql: "PRAGMA journal_mode = WAL", values: [])
        try execute(database: database, sql: "PRAGMA foreign_keys = ON", values: [])
    }

    private static func migrate(database: OpaquePointer?) throws {
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS source (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                module_id TEXT NOT NULL DEFAULT 'core',
                module_name TEXT NOT NULL DEFAULT 'Core',
                source_family_id TEXT NOT NULL DEFAULT 'independent',
                source_family_name TEXT NOT NULL DEFAULT 'Independent',
                domain TEXT NOT NULL DEFAULT 'general_culture',
                classification TEXT NOT NULL DEFAULT 'editorial',
                tier TEXT NOT NULL DEFAULT 'C',
                base_url TEXT NOT NULL,
                city TEXT NOT NULL,
                parser_type TEXT NOT NULL,
                enabled INTEGER NOT NULL,
                justification TEXT NOT NULL DEFAULT '',
                refresh_cadence_minutes INTEGER NOT NULL DEFAULT 360,
                failure_backoff_minutes INTEGER NOT NULL DEFAULT 240,
                last_attempt_at TEXT,
                backoff_until TEXT,
                consecutive_failures INTEGER NOT NULL DEFAULT 0,
                last_success_at TEXT
            )
            """,
            values: []
        )
        try addColumnIfNeeded(database: database, table: "source", column: "module_id", definition: "TEXT NOT NULL DEFAULT 'core'")
        try addColumnIfNeeded(database: database, table: "source", column: "module_name", definition: "TEXT NOT NULL DEFAULT 'Core'")
        try addColumnIfNeeded(database: database, table: "source", column: "source_family_id", definition: "TEXT NOT NULL DEFAULT 'independent'")
        try addColumnIfNeeded(database: database, table: "source", column: "source_family_name", definition: "TEXT NOT NULL DEFAULT 'Independent'")
        try addColumnIfNeeded(database: database, table: "source", column: "domain", definition: "TEXT NOT NULL DEFAULT 'general_culture'")
        try addColumnIfNeeded(database: database, table: "source", column: "classification", definition: "TEXT NOT NULL DEFAULT 'editorial'")
        try addColumnIfNeeded(database: database, table: "source", column: "tier", definition: "TEXT NOT NULL DEFAULT 'C'")
        try addColumnIfNeeded(database: database, table: "source", column: "justification", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "source", column: "refresh_cadence_minutes", definition: "INTEGER NOT NULL DEFAULT 360")
        try addColumnIfNeeded(database: database, table: "source", column: "failure_backoff_minutes", definition: "INTEGER NOT NULL DEFAULT 240")
        try addColumnIfNeeded(database: database, table: "source", column: "last_attempt_at", definition: "TEXT")
        try addColumnIfNeeded(database: database, table: "source", column: "backoff_until", definition: "TEXT")
        try addColumnIfNeeded(database: database, table: "source", column: "consecutive_failures", definition: "INTEGER NOT NULL DEFAULT 0")
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS snapshot (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                started_at TEXT NOT NULL,
                completed_at TEXT,
                status TEXT NOT NULL,
                item_count INTEGER NOT NULL,
                error_message TEXT,
                FOREIGN KEY(source_id) REFERENCES source(id)
            )
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS observation (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                snapshot_id TEXT NOT NULL,
                canonical_entity_id TEXT NOT NULL DEFAULT '',
                external_id_or_hash TEXT NOT NULL,
                title TEXT NOT NULL,
                subtitle TEXT,
                url TEXT NOT NULL,
                author_or_artist TEXT,
                tags_json TEXT NOT NULL,
                location TEXT,
                published_at TEXT,
                scraped_at TEXT NOT NULL,
                excerpt TEXT,
                normalized_entity_name TEXT NOT NULL,
                raw_payload TEXT NOT NULL,
                domain TEXT NOT NULL DEFAULT 'general_culture',
                entity_type TEXT NOT NULL DEFAULT 'unknown',
                FOREIGN KEY(source_id) REFERENCES source(id),
                FOREIGN KEY(snapshot_id) REFERENCES snapshot(id)
            )
            """,
            values: []
        )
        try addColumnIfNeeded(database: database, table: "observation", column: "distilled_excerpt", definition: "TEXT")
        try addColumnIfNeeded(database: database, table: "observation", column: "canonical_entity_id", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "observation", column: "domain", definition: "TEXT NOT NULL DEFAULT 'general_culture'")
        try addColumnIfNeeded(database: database, table: "observation", column: "entity_type", definition: "TEXT NOT NULL DEFAULT 'unknown'")
        try execute(
            database: database,
            sql:
            """
            CREATE INDEX IF NOT EXISTS observation_signal_index
            ON observation(normalized_entity_name, scraped_at DESC)
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE INDEX IF NOT EXISTS observation_source_external_index
            ON observation(source_id, external_id_or_hash)
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS signal_candidate (
                id TEXT PRIMARY KEY,
                canonical_entity_id TEXT NOT NULL DEFAULT '',
                domain TEXT NOT NULL DEFAULT 'general_culture',
                canonical_name TEXT NOT NULL,
                entity_type TEXT NOT NULL DEFAULT 'unknown',
                first_seen_at TEXT NOT NULL,
                latest_seen_at TEXT NOT NULL,
                source_count INTEGER NOT NULL,
                observation_count INTEGER NOT NULL,
                current_source_count INTEGER NOT NULL DEFAULT 0,
                current_source_family_count INTEGER NOT NULL DEFAULT 0,
                current_observation_count INTEGER NOT NULL DEFAULT 0,
                historical_source_count INTEGER NOT NULL DEFAULT 0,
                historical_observation_count INTEGER NOT NULL DEFAULT 0,
                growth_score REAL NOT NULL,
                diversity_score REAL NOT NULL,
                repeat_appearance_score REAL NOT NULL,
                progression_score REAL NOT NULL DEFAULT 0,
                saturation_score REAL NOT NULL,
                emergence_score REAL NOT NULL,
                confidence REAL NOT NULL,
                movement TEXT NOT NULL DEFAULT 'new',
                maturity TEXT NOT NULL DEFAULT 'early_emergence',
                lifecycle_state TEXT NOT NULL DEFAULT 'emerging',
                conversion_state TEXT NOT NULL DEFAULT 'pending',
                outcome_tiers_json TEXT NOT NULL DEFAULT '[]',
                supporting_sources_json TEXT NOT NULL DEFAULT '[]',
                progression_stages_json TEXT NOT NULL DEFAULT '[]',
                progression_pattern TEXT NOT NULL DEFAULT '',
                movement_summary TEXT NOT NULL DEFAULT '',
                maturity_summary TEXT NOT NULL DEFAULT '',
                lifecycle_summary TEXT NOT NULL DEFAULT '',
                conversion_summary TEXT NOT NULL DEFAULT '',
                pathway_summary TEXT NOT NULL DEFAULT '',
                source_influence_summary TEXT NOT NULL DEFAULT '',
                progression_summary TEXT NOT NULL DEFAULT '',
                evidence_summary TEXT NOT NULL
            )
            """,
            values: []
        )
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "canonical_entity_id", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "domain", definition: "TEXT NOT NULL DEFAULT 'general_culture'")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "entity_type", definition: "TEXT NOT NULL DEFAULT 'unknown'")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "current_source_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "current_source_family_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "current_observation_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "historical_source_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "historical_observation_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "progression_score", definition: "REAL NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "movement", definition: "TEXT NOT NULL DEFAULT 'new'")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "maturity", definition: "TEXT NOT NULL DEFAULT 'early_emergence'")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "lifecycle_state", definition: "TEXT NOT NULL DEFAULT 'emerging'")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "conversion_state", definition: "TEXT NOT NULL DEFAULT 'pending'")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "outcome_tiers_json", definition: "TEXT NOT NULL DEFAULT '[]'")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "supporting_sources_json", definition: "TEXT NOT NULL DEFAULT '[]'")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "progression_stages_json", definition: "TEXT NOT NULL DEFAULT '[]'")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "progression_pattern", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "movement_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "maturity_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "lifecycle_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "conversion_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "pathway_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "source_influence_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_candidate", column: "progression_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS canonical_entity (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                domain TEXT NOT NULL,
                entity_type TEXT NOT NULL,
                aliases_json TEXT NOT NULL,
                merge_confidence REAL NOT NULL DEFAULT 0.0,
                merge_summary TEXT NOT NULL DEFAULT ''
            )
            """,
            values: []
        )
        try addColumnIfNeeded(database: database, table: "canonical_entity", column: "merge_confidence", definition: "REAL NOT NULL DEFAULT 0.0")
        try addColumnIfNeeded(database: database, table: "canonical_entity", column: "merge_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS entity_alias (
                id TEXT PRIMARY KEY,
                canonical_entity_id TEXT NOT NULL,
                alias_text TEXT NOT NULL,
                normalized_alias TEXT NOT NULL,
                source_id TEXT,
                FOREIGN KEY(canonical_entity_id) REFERENCES canonical_entity(id)
            )
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE INDEX IF NOT EXISTS entity_alias_lookup_index
            ON entity_alias(normalized_alias)
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS entity_source_role (
                id TEXT PRIMARY KEY,
                canonical_entity_id TEXT NOT NULL,
                source_id TEXT NOT NULL,
                source_classification TEXT NOT NULL,
                first_seen_at TEXT NOT NULL,
                last_seen_at TEXT NOT NULL,
                appearance_count INTEGER NOT NULL,
                FOREIGN KEY(canonical_entity_id) REFERENCES canonical_entity(id),
                FOREIGN KEY(source_id) REFERENCES source(id)
            )
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE INDEX IF NOT EXISTS entity_source_role_lookup_index
            ON entity_source_role(canonical_entity_id, source_id)
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS entity_history (
                id TEXT PRIMARY KEY,
                canonical_entity_id TEXT NOT NULL DEFAULT '',
                canonical_name TEXT NOT NULL,
                domain TEXT NOT NULL,
                entity_type TEXT NOT NULL,
                first_seen_at TEXT NOT NULL,
                last_seen_at TEXT NOT NULL,
                appearance_count INTEGER NOT NULL,
                source_diversity INTEGER NOT NULL,
                lifecycle_state TEXT NOT NULL DEFAULT 'emerging',
                lifecycle_summary TEXT NOT NULL DEFAULT '',
                conversion_state TEXT NOT NULL DEFAULT 'pending',
                conversion_summary TEXT NOT NULL DEFAULT ''
            )
            """,
            values: []
        )
        try addColumnIfNeeded(database: database, table: "entity_history", column: "canonical_entity_id", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "entity_history", column: "lifecycle_state", definition: "TEXT NOT NULL DEFAULT 'emerging'")
        try addColumnIfNeeded(database: database, table: "entity_history", column: "lifecycle_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "entity_history", column: "conversion_state", definition: "TEXT NOT NULL DEFAULT 'pending'")
        try addColumnIfNeeded(database: database, table: "entity_history", column: "conversion_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try execute(
            database: database,
            sql:
            """
            CREATE INDEX IF NOT EXISTS entity_history_name_index
            ON entity_history(canonical_name)
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS entity_stage_snapshot (
                id TEXT PRIMARY KEY,
                canonical_entity_id TEXT NOT NULL,
                date TEXT NOT NULL,
                stage TEXT NOT NULL,
                source_count INTEGER NOT NULL,
                signal_score REAL NOT NULL,
                FOREIGN KEY(canonical_entity_id) REFERENCES canonical_entity(id)
            )
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE INDEX IF NOT EXISTS entity_stage_snapshot_lookup_index
            ON entity_stage_snapshot(canonical_entity_id, date DESC)
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS pathway_history (
                id TEXT PRIMARY KEY,
                run_at TEXT NOT NULL,
                canonical_entity_id TEXT NOT NULL,
                pathway_pattern TEXT NOT NULL,
                domain TEXT NOT NULL,
                lifecycle_state TEXT NOT NULL,
                conversion_state TEXT NOT NULL DEFAULT 'pending',
                signal_score REAL NOT NULL
            )
            """,
            values: []
        )
        try addColumnIfNeeded(database: database, table: "pathway_history", column: "conversion_state", definition: "TEXT NOT NULL DEFAULT 'pending'")
        try execute(
            database: database,
            sql:
            """
            CREATE INDEX IF NOT EXISTS pathway_history_pattern_index
            ON pathway_history(pathway_pattern, run_at DESC)
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS pathway_stat (
                id TEXT PRIMARY KEY,
                pathway_pattern TEXT NOT NULL,
                domain TEXT NOT NULL,
                sample_count INTEGER NOT NULL,
                advancing_count INTEGER NOT NULL,
                peaked_count INTEGER NOT NULL,
                cooling_count INTEGER NOT NULL,
                failed_count INTEGER NOT NULL,
                disappeared_count INTEGER NOT NULL,
                success_weight REAL NOT NULL,
                failure_weight REAL NOT NULL,
                conversion_count INTEGER NOT NULL DEFAULT 0,
                stalled_conversion_count INTEGER NOT NULL DEFAULT 0,
                never_converted_count INTEGER NOT NULL DEFAULT 0,
                conversion_weight REAL NOT NULL DEFAULT 0,
                predictive_score REAL NOT NULL,
                summary TEXT NOT NULL
            )
            """,
            values: []
        )
        try addColumnIfNeeded(database: database, table: "pathway_stat", column: "conversion_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "pathway_stat", column: "stalled_conversion_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "pathway_stat", column: "never_converted_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "pathway_stat", column: "conversion_weight", definition: "REAL NOT NULL DEFAULT 0")
        try execute(
            database: database,
            sql:
            """
            CREATE INDEX IF NOT EXISTS pathway_stat_pattern_index
            ON pathway_stat(pathway_pattern, predictive_score DESC)
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS outcome_confirmation (
                id TEXT PRIMARY KEY,
                canonical_entity_id TEXT NOT NULL,
                outcome_tier TEXT NOT NULL,
                confirmed_at TEXT NOT NULL,
                source_ids_json TEXT NOT NULL,
                summary TEXT NOT NULL
            )
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE INDEX IF NOT EXISTS outcome_confirmation_entity_index
            ON outcome_confirmation(canonical_entity_id, confirmed_at DESC)
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS signal_run (
                id TEXT PRIMARY KEY,
                run_at TEXT NOT NULL,
                canonical_entity_id TEXT NOT NULL DEFAULT '',
                canonical_name TEXT NOT NULL,
                domain TEXT NOT NULL,
                entity_type TEXT NOT NULL,
                rank INTEGER NOT NULL,
                score REAL NOT NULL,
                supporting_sources_json TEXT NOT NULL,
                observation_count INTEGER NOT NULL,
                source_count INTEGER NOT NULL,
                current_source_count INTEGER NOT NULL DEFAULT 0,
                current_source_family_count INTEGER NOT NULL DEFAULT 0,
                current_observation_count INTEGER NOT NULL DEFAULT 0,
                historical_source_count INTEGER NOT NULL DEFAULT 0,
                historical_observation_count INTEGER NOT NULL DEFAULT 0,
                movement TEXT NOT NULL,
                maturity TEXT NOT NULL DEFAULT 'early_emergence',
                lifecycle_state TEXT NOT NULL DEFAULT 'emerging',
                conversion_state TEXT NOT NULL DEFAULT 'pending',
                outcome_tiers_json TEXT NOT NULL DEFAULT '[]',
                progression_pattern TEXT NOT NULL DEFAULT '',
                explanation TEXT NOT NULL,
                lifecycle_summary TEXT NOT NULL DEFAULT '',
                conversion_summary TEXT NOT NULL DEFAULT '',
                source_influence_summary TEXT NOT NULL DEFAULT ''
            )
            """,
            values: []
        )
        try addColumnIfNeeded(database: database, table: "signal_run", column: "canonical_entity_id", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "current_source_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "current_source_family_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "current_observation_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "historical_source_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "historical_observation_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "maturity", definition: "TEXT NOT NULL DEFAULT 'early_emergence'")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "lifecycle_state", definition: "TEXT NOT NULL DEFAULT 'emerging'")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "conversion_state", definition: "TEXT NOT NULL DEFAULT 'pending'")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "outcome_tiers_json", definition: "TEXT NOT NULL DEFAULT '[]'")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "progression_pattern", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "lifecycle_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "conversion_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(database: database, table: "signal_run", column: "source_influence_summary", definition: "TEXT NOT NULL DEFAULT ''")
        try execute(
            database: database,
            sql:
            """
            CREATE INDEX IF NOT EXISTS signal_run_name_index
            ON signal_run(canonical_name, run_at DESC)
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS source_influence_stat (
                id TEXT PRIMARY KEY,
                scope TEXT NOT NULL,
                scope_key TEXT NOT NULL,
                display_name TEXT NOT NULL,
                domain TEXT NOT NULL,
                sample_count INTEGER NOT NULL,
                advancing_count INTEGER NOT NULL,
                peaked_count INTEGER NOT NULL,
                failed_count INTEGER NOT NULL,
                disappeared_count INTEGER NOT NULL,
                conversion_count INTEGER NOT NULL DEFAULT 0,
                stalled_conversion_count INTEGER NOT NULL DEFAULT 0,
                never_converted_count INTEGER NOT NULL DEFAULT 0,
                average_signal_score REAL NOT NULL DEFAULT 0,
                predictive_score REAL NOT NULL,
                summary TEXT NOT NULL
            )
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE INDEX IF NOT EXISTS source_influence_stat_lookup_index
            ON source_influence_stat(scope, domain, predictive_score DESC)
            """,
            values: []
        )
        try execute(
            database: database,
            sql:
            """
            CREATE TABLE IF NOT EXISTS brief (
                id TEXT PRIMARY KEY,
                generated_at TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                citations_payload TEXT NOT NULL,
                period_type TEXT NOT NULL
            )
            """,
            values: []
        )
        try execute(
            database: database,
            sql: """
            CREATE TABLE IF NOT EXISTS chat_message (
                id TEXT PRIMARY KEY,
                brief_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                turn_number INTEGER NOT NULL
            )
            """,
            values: []
        )
    }

    private static func execute(database: OpaquePointer?, sql: String, values: [SQLValue]) throws {
        guard let database else { throw RepositoryError.message("Database not available") }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw RepositoryError.message(String(cString: sqlite3_errmsg(database)))
        }

        try Self.bind(values, to: statement)

        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            result = sqlite3_step(statement)
        }

        guard result == SQLITE_DONE else {
            throw RepositoryError.message(String(cString: sqlite3_errmsg(database)))
        }
    }

    private static func addColumnIfNeeded(
        database: OpaquePointer?,
        table: String,
        column: String,
        definition: String
    ) throws {
        guard let database else { throw RepositoryError.message("Database not available") }
        guard try !columnExists(database: database, table: table, column: column) else { return }
        try execute(database: database, sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(definition)", values: [])
    }

    private static func columnExists(database: OpaquePointer?, table: String, column: String) throws -> Bool {
        guard let database else { throw RepositoryError.message("Database not available") }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            throw RepositoryError.message(String(cString: sqlite3_errmsg(database)))
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pointer = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: pointer) == column {
                return true
            }
        }
        return false
    }

    private func execute(_ sql: String, values: [SQLValue]) throws {
        guard let database else { throw RepositoryError.message("Database not available") }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw RepositoryError.message(lastErrorMessage())
        }

        try Self.bind(values, to: statement)

        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            result = sqlite3_step(statement)
        }

        guard result == SQLITE_DONE else {
            throw RepositoryError.message(lastErrorMessage())
        }
    }

    private func query<T>(
        _ sql: String,
        values: [SQLValue] = [],
        map: (OpaquePointer?) throws -> T
    ) throws -> [T] {
        guard let database else { throw RepositoryError.message("Database not available") }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw RepositoryError.message(lastErrorMessage())
        }

        try Self.bind(values, to: statement)

        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(try map(statement))
        }
        return rows
    }

    private func querySingle<T>(
        _ sql: String,
        values: [SQLValue] = [],
        map: (OpaquePointer?) throws -> T
    ) throws -> T? {
        try query(sql, values: values, map: map).first
    }

    private func queryValue(_ sql: String, values: [SQLValue]) throws -> String {
        guard let value = try querySingle(sql, values: values, map: { statement in
            text(statement, 0)
        }) else {
            throw RepositoryError.message("Expected a row for query: \(sql)")
        }
        return value
    }

    private func queryCount(_ sql: String, values: [SQLValue]) throws -> Int {
        guard let value = try querySingle(sql, values: values, map: { statement in
            int(statement, 0)
        }) else {
            throw RepositoryError.message("Expected a row for query: \(sql)")
        }
        return value
    }

    private static func bind(_ values: [SQLValue], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let .text(text):
                sqlite3_bind_text(statement, position, text, -1, SQLValue.sqliteTransient)
            case let .int(value):
                sqlite3_bind_int(statement, position, Int32(value))
            case let .double(value):
                sqlite3_bind_double(statement, position, value)
            case .null:
                sqlite3_bind_null(statement, position)
            }
        }
    }

    private func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func date(_ statement: OpaquePointer?, _ column: Int32) -> Date? {
        guard let value = nullableText(statement, column) else { return nil }
        return dateFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func requiredDate(_ statement: OpaquePointer?, _ column: Int32) -> Date {
        date(statement, column) ?? .distantPast
    }

    private func requiredDay(_ statement: OpaquePointer?, _ column: Int32) -> Date {
        guard let value = nullableText(statement, column) else { return .distantPast }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value) ?? .distantPast
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        String(cString: sqlite3_column_text(statement, column))
    }

    private func nullableText(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private func int(_ statement: OpaquePointer?, _ column: Int32) -> Int {
        Int(sqlite3_column_int(statement, column))
    }

    private func double(_ statement: OpaquePointer?, _ column: Int32) -> Double {
        sqlite3_column_double(statement, column)
    }

    private func lastErrorMessage() -> String {
        guard let database, let pointer = sqlite3_errmsg(database) else {
            return "Unknown SQLite error"
        }
        return String(cString: pointer)
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        let data = (try? encoder.encode(value)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeStringArray(from string: String?) -> [String] {
        guard let string, let data = string.data(using: .utf8) else { return [] }
        return (try? decoder.decode([String].self, from: data)) ?? []
    }

    private func decodeSourceClassifications(from string: String?) -> [SourceClassification] {
        decodeStringArray(from: string).compactMap(SourceClassification.init(rawValue:))
    }

    private func decodeOutcomeTiers(from string: String?) -> [DownstreamOutcomeTier] {
        decodeStringArray(from: string).compactMap(DownstreamOutcomeTier.init(rawValue:))
    }

    private func decodeCitations(from string: String) -> [BriefCitation] {
        guard let data = string.data(using: .utf8) else { return [] }
        return (try? decoder.decode([BriefCitation].self, from: data)) ?? []
    }

    private static func databaseURL(override: URL? = nil) throws -> URL {
        if let override {
            let directory = override.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return override
        }

        if let overridePath = ProcessInfo.processInfo.environment["MALCOME_STORAGE_PATH"], !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath)
            let directory = overrideURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return overrideURL
        }

        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("Malcome", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("malcome.sqlite")

        // First launch: copy seed database from bundle if no database exists yet
        if !FileManager.default.fileExists(atPath: dbURL.path) {
            if let seedURL = Bundle.main.url(forResource: "malcome_seed", withExtension: "sqlite") {
                try FileManager.default.copyItem(at: seedURL, to: dbURL)
                UserDefaults.standard.set(true, forKey: "malcome_seeded_from_bundle")
                print("Malcome: Seed database copied from bundle")
            }
        }

        return dbURL
    }
}

private enum SQLValue {
    case text(String)
    case int(Int)
    case double(Double)
    case null

    nonisolated static func nullOrText(_ string: String?) -> SQLValue {
        guard let string else { return .null }
        return .text(string)
    }

    nonisolated static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

enum RepositoryError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): message
        }
    }
}
