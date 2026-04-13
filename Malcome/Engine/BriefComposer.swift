import Foundation

struct BriefingInput: Sendable {
    struct SignalPacket: Sendable {
        let signal: SignalCandidateRecord
        let observations: [ObservationRecord]
        let sourceNames: [String]
        let priorMentions: Int
        let recentMentions: Int
    }

    let generatedAt: Date
    let signals: [SignalPacket]
    let watchlistCandidates: [WatchlistCandidate]
    let domainMix: [String]
    let sourceInfluenceHighlights: [String]
}

protocol BriefGenerating: Sendable {
    func generateBrief(from input: BriefingInput) async throws -> BriefRecord
}

struct BriefComposer: Sendable {
    let repository: AppRepository
    let generator: BriefGenerating

    func composeBrief() async throws -> BriefRecord {
        // Only surface signals with 2+ independent source families in the brief
        let allSignals = try await repository.fetchTopSignals(limit: 12)
        let signals = allSignals.filter { $0.currentSourceFamilyCount >= 2 }.prefix(6).map { $0 }
        let latestObservations = try await repository.fetchObservations(limit: 120)
        let sources = try await repository.fetchSources()
        let sourceInfluenceStats = try await repository.fetchSourceInfluenceStats(limit: 200)
        let sourceNamesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.name) })
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let sourceInfluenceByID = Dictionary(uniqueKeysWithValues: sourceInfluenceStats.map { ($0.id, $0) })
        let observationEntityIDs = latestObservations.map { $0.canonicalEntityID.isEmpty ? $0.normalizedEntityName : $0.canonicalEntityID }
        let entityHistoriesByID = try await repository.entityHistories(forCanonicalEntityIDs: observationEntityIDs)
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now

        var packets: [BriefingInput.SignalPacket] = []
        for signal in signals {
            let evidence = try await repository.observations(forCanonicalEntityID: signal.canonicalEntityID, limit: 6)
            let recentMentions = evidence.filter { $0.scrapedAt >= recentCutoff }.count
            let priorMentions = max(0, evidence.count - recentMentions)

            packets.append(BriefingInput.SignalPacket(
                signal: signal,
                observations: evidence,
                sourceNames: Array(Set(evidence.compactMap { sourceNamesByID[$0.sourceID] })).sorted(),
                priorMentions: priorMentions,
                recentMentions: recentMentions
            ))
        }

        if packets.isEmpty {
            let watchlistCandidates = buildWatchlistCandidates(
                from: latestObservations,
                sourcesByID: sourcesByID,
                entityHistoriesByID: entityHistoriesByID,
                limit: 6
            )
            let domainMix = Array(Set(watchlistCandidates.map(\.domain.label))).sorted()
            let influenceHighlights = buildInfluenceHighlights(
                signals: [],
                watchlist: watchlistCandidates,
                sourcesByID: sourcesByID,
                sourceInfluenceByID: sourceInfluenceByID
            )
            let input = BriefingInput(
                generatedAt: .now,
                signals: [],
                watchlistCandidates: watchlistCandidates,
                domainMix: domainMix,
                sourceInfluenceHighlights: influenceHighlights
            )
            let brief = try await generator.generateBrief(from: input)
            try await repository.storeBrief(brief)
            return brief
        }

        let watchlistForInput = buildWatchlistCandidates(
            from: latestObservations,
            sourcesByID: sourcesByID,
            entityHistoriesByID: entityHistoriesByID,
            limit: 4
        )
        let domainMix = Array(Set(
            packets.map(\.signal.domain.label) + watchlistForInput.map(\.domain.label)
        )).sorted()
        let influenceHighlights = buildInfluenceHighlights(
            signals: packets,
            watchlist: watchlistForInput,
            sourcesByID: sourcesByID,
            sourceInfluenceByID: sourceInfluenceByID
        )

        let input = BriefingInput(
            generatedAt: .now,
            signals: packets,
            watchlistCandidates: watchlistForInput,
            domainMix: domainMix,
            sourceInfluenceHighlights: influenceHighlights
        )
        let brief = try await generator.generateBrief(from: input)
        try await repository.storeBrief(brief)
        return brief
    }

    private func buildInfluenceHighlights(
        signals: [BriefingInput.SignalPacket],
        watchlist: [WatchlistCandidate],
        sourcesByID: [String: SourceRecord],
        sourceInfluenceByID: [String: SourceInfluenceStatRecord]
    ) -> [String] {
        var highlights: [String] = []
        let allCandidates = watchlist.prefix(3)
        for candidate in allCandidates {
            guard let stat = strongestInfluenceStat(
                for: candidate,
                sourcesByID: sourcesByID,
                sourceInfluenceByID: sourceInfluenceByID
            ) else { continue }
            if let summary = watchlistLearningSummary(for: stat, domain: candidate.domain) {
                highlights.append(summary)
                if highlights.count >= 2 { break }
            }
        }
        return highlights
    }

    func watchlistCandidates(limit: Int = 8) async throws -> [WatchlistCandidate] {
        let observations = try await repository.fetchObservations(limit: 120)
        let sources = try await repository.fetchSources()
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let canonicalEntityIDs = observations.map { $0.canonicalEntityID.isEmpty ? $0.normalizedEntityName : $0.canonicalEntityID }
        let entityHistories = try await repository.entityHistories(forCanonicalEntityIDs: canonicalEntityIDs)
        return buildWatchlistCandidates(
            from: observations,
            sourcesByID: sourcesByID,
            entityHistoriesByID: entityHistories,
            limit: limit
        )
    }

    private func buildWatchlistCandidates(
        from observations: [ObservationRecord],
        sourcesByID: [String: SourceRecord],
        entityHistoriesByID: [String: EntityHistoryRecord] = [:],
        limit: Int
    ) -> [WatchlistCandidate] {
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let filtered = observations.filter { observation in
            (observation.publishedAt ?? observation.scrapedAt) >= recentCutoff
        }

        let grouped = Dictionary(grouping: filtered) { observation in
            observation.canonicalEntityID.isEmpty ? observation.normalizedEntityName : observation.canonicalEntityID
        }

        return grouped.compactMap { canonicalEntityID, group in
            guard let lead = group.max(by: { ($0.publishedAt ?? $0.scrapedAt) < ($1.publishedAt ?? $1.scrapedAt) }) else {
                return nil
            }

            let sourceIDs = Array(Set(group.map(\.sourceID))).sorted()
            let sourceFamilies = Set(sourceIDs.map { sourceFamilyKey(for: $0, sourcesByID: sourcesByID) })
            let classifications = Set(sourceIDs.compactMap { sourcesByID[$0]?.classification })
            let latestSeenAt = group.map { $0.publishedAt ?? $0.scrapedAt }.max() ?? lead.scrapedAt
            let history = entityHistoriesByID[canonicalEntityID]
            let displayTitle = watchlistDisplayTitle(for: lead, history: history)
            let historicalAppearances = history?.appearanceCount ?? group.count
            let historicalSourceDiversity = history?.sourceDiversity ?? sourceIDs.count
            let recurringSeriesOnly = group.allSatisfy { $0.tags.contains("recurring_series") }
            let roundupOnly = group.allSatisfy { $0.tags.contains("roundup") }
            let selfBrandedOnly = group.allSatisfy { $0.tags.contains("self_branded") }

            if lead.entityType == .concept, sourceFamilies.count == 1, historicalAppearances < 2 {
                return nil
            }
            if sourceFamilies.count == 1 && (recurringSeriesOnly || roundupOnly || selfBrandedOnly) {
                return nil
            }

            let tierScore = sourceIDs.reduce(0.0) { $0 + tierWeight(for: sourcesByID[$1]?.tier ?? .c) }
            let classificationScore = classifications.reduce(0.0) { $0 + classificationWeight(for: $1) }
            let entityScore = entityWeight(for: lead.entityType)
            let freshnessDays = max(0, min(10, Int(Date().timeIntervalSince(latestSeenAt) / 86_400)))
            let freshnessScore = max(0.0, 3.0 - Double(freshnessDays) * 0.25)
            let repeatScore = min(2.0, Double(group.count - 1) * 0.35)
            let corroborationScore = sourceFamilies.count > 1 ? Double(sourceFamilies.count - 1) * 1.2 : 0
            let historicalScore = min(2.4, Double(max(0, historicalAppearances - 1)) * 0.22)
            let historicalDiversityScore = min(1.8, Double(max(0, (history?.sourceDiversity ?? sourceIDs.count) - 1)) * 0.55)
            let reusableEntityBoost: Double = {
                guard group.count > 1 || sourceIDs.count > 1 else { return 0 }
                switch lead.entityType {
                case .creator: return 1.1
                case .event, .eventSeries: return 0.9
                case .collective: return 0.8
                case .venue: return 0.7
                default: return 0
                }
            }()

            let alias = lead.authorOrArtist ?? lead.title
            let titlePenalty = HTMLSupport.isPotentialTitleCollisionAlias(lead.title) ? 2.4 : 0
            let commonPenalty = HTMLSupport.isCommonCollisionAlias(alias) ? 1.2 : 0
            let shortPenalty = HTMLSupport.isShortAlias(alias) ? 0.8 : 0
            let isolatedPenalty = sourceFamilies.count == 1 && sourceIDs.count == 1 ? 1.0 : 0
            let editorialConceptPenalty = sourceFamilies.count == 1 && classifications == [.editorial] && lead.entityType == .concept ? 2.7 : 0
            let weakAttributionPenalty = lead.authorOrArtist == nil && lead.entityType == .concept ? 0.8 : 0
            let singletonConceptPenalty = group.count == 1 && lead.entityType == .concept ? 0.9 : 0
            let titleDrivenPenalty = displayTitle == lead.title && lead.entityType == .concept && sourceFamilies.count == 1 ? 0.8 : 0
            let recurringSeriesPenalty = recurringSeriesOnly ? 2.6 : 0
            let roundupPenalty = roundupOnly ? 2.1 : 0
            let selfBrandedPenalty = selfBrandedOnly ? 2.2 : 0

            let score = freshnessScore + tierScore + classificationScore + entityScore + repeatScore + corroborationScore + historicalScore + historicalDiversityScore + reusableEntityBoost - titlePenalty - commonPenalty - shortPenalty - isolatedPenalty - editorialConceptPenalty - weakAttributionPenalty - singletonConceptPenalty - titleDrivenPenalty - recurringSeriesPenalty - roundupPenalty - selfBrandedPenalty
            guard score > 1.2 else { return nil }
            guard sourceFamilies.count > 1 else { return nil }

            let sourceSummary = watchlistSourceSummary(sourceIDs: sourceIDs, sourcesByID: sourcesByID)
            let stage = watchlistStage(
                sourceFamilyCount: sourceFamilies.count,
                observationCount: group.count,
                historicalAppearances: historicalAppearances,
                classifications: classifications
            )
            let whyNow = watchlistWhyNow(
                entityType: lead.entityType,
                stage: stage,
                sourceFamilyCount: sourceFamilies.count,
                observationCount: group.count,
                historicalAppearances: historicalAppearances,
                historicalSourceDiversity: historicalSourceDiversity,
                sourceSummary: sourceSummary,
                classifications: classifications
            )
            let upgradeTrigger = watchlistUpgradeTrigger(
                entityType: lead.entityType,
                stage: stage,
                sourceFamilyCount: sourceFamilies.count,
                classifications: classifications
            )
            let summary = sourceFamilies.count > 1
                ? "Seen across \(sourceFamilies.count) independent source families, led by \(sourceSummary)."
                : "Seen via \(sourceSummary); still waiting on a second source family."
            let note: String = {
                let classificationSummary = classifications.isEmpty
                    ? "Current shape still needs more context."
                    : "Current shape: \(classifications.map(\.label).sorted().joined(separator: " + "))."
                guard displayTitle != lead.title else {
                    return classificationSummary
                }
                return "\(classificationSummary) Latest evidence title: \(lead.title)."
            }()

            return WatchlistCandidate(
                id: canonicalEntityID,
                canonicalEntityID: canonicalEntityID,
                title: displayTitle,
                domain: lead.domain,
                entityType: lead.entityType,
                stage: stage,
                sourceIDs: sourceIDs,
                sourceFamilyCount: sourceFamilies.count,
                observationCount: group.count,
                historicalMentionCount: historicalAppearances,
                historicalSourceDiversity: historicalSourceDiversity,
                latestSeenAt: latestSeenAt,
                summary: summary,
                note: note,
                whyNow: whyNow,
                upgradeTrigger: upgradeTrigger,
                score: score
            )
        }
        .sorted {
            if $0.score == $1.score {
                return $0.latestSeenAt > $1.latestSeenAt
            }
            return $0.score > $1.score
        }
        .prefix(limit)
        .map { $0 }
    }

    private func watchlistSourceSummary(sourceIDs: [String], sourcesByID: [String: SourceRecord]) -> String {
        let names = sourceIDs.compactMap { sourcesByID[$0]?.name }
        if names.count <= 2 {
            return names.joined(separator: ", ")
        }
        return "\(names.prefix(2).joined(separator: ", ")) + \(names.count - 2) more"
    }

    private func watchlistBriefLine(for candidate: WatchlistCandidate) -> String {
        let evidence = watchlistEvidenceLine(for: candidate)
        return "\(candidate.whyNow) \(evidence) \(candidate.upgradeTrigger)"
    }

    private func watchlistNarrativeIntro(leads: String, domains: String) -> String {
        guard !leads.isEmpty else {
            return "The first pass is still building corroboration, so today’s brief is a watchlist rather than a high-conviction cultural read."
        }

        return "\(leads) sit at the front of today’s radar. The energy is real, but it still reads as an early watchlist built from \(domains), not a fully corroborated cultural signal."
    }

    private func domainPhrase(for domains: [String]) -> String {
        if domains.isEmpty {
            return "today's source mix"
        }
        return naturalLanguageList(domains).lowercased()
    }

    private func naturalLanguageList(_ items: [String]) -> String {
        let cleaned = items.filter { !$0.isEmpty }
        switch cleaned.count {
        case 0:
            return ""
        case 1:
            return cleaned[0]
        case 2:
            return "\(cleaned[0]) and \(cleaned[1])"
        default:
            let head = cleaned.dropLast().joined(separator: ", ")
            return "\(head), and \(cleaned.last!)"
        }
    }

    private func tierWeight(for tier: SourceTier) -> Double {
        switch tier {
        case .a: return 1.8
        case .b: return 1.1
        case .c: return 0.6
        }
    }

    private func classificationWeight(for classification: SourceClassification) -> Double {
        switch classification {
        case .discovery: return 0.4
        case .editorial: return 1.0
        case .community: return 0.9
        case .institutional: return 1.0
        case .venue: return 0.7
        case .commercialScaling: return 0.5
        }
    }

    private func entityWeight(for entityType: EntityType) -> Double {
        switch entityType {
        case .creator: return 1.4
        case .collective: return 1.1
        case .event, .eventSeries: return 1.0
        case .venue: return 0.9
        case .organization, .brand, .publication: return 0.6
        case .scene: return 0.5
        case .concept: return 0.1
        case .unknown: return 0
        }
    }

    private func watchlistStage(
        sourceFamilyCount: Int,
        observationCount: Int,
        historicalAppearances: Int,
        classifications: Set<SourceClassification>
    ) -> WatchlistStage {
        if sourceFamilyCount > 1 {
            return .corroborating
        }

        let evidenceVolume = observationCount + historicalAppearances
        if evidenceVolume >= 4 || classifications.count > 1 {
            return .forming
        }

        return .early
    }

    private func watchlistWhyNow(
        entityType: EntityType,
        stage: WatchlistStage,
        sourceFamilyCount: Int,
        observationCount: Int,
        historicalAppearances: Int,
        historicalSourceDiversity: Int,
        sourceSummary: String,
        classifications: Set<SourceClassification>
    ) -> String {
        let shape = classifications.map(\.label).sorted().joined(separator: " + ")
        let historicalRepeats = max(0, historicalAppearances - observationCount)

        switch stage {
        case .corroborating:
            return "It is already surfacing across \(sourceFamilyCount) independent source families, led by \(sourceSummary)."
        case .forming:
            if historicalRepeats > 0 && sourceFamilyCount <= 1 {
                return "It has repeated in Malcome’s stored history enough to look like more than a one-off mention, even though the current read is still thin."
            }
            switch entityType {
            case .creator, .collective:
                return "It is repeating enough to look like a forming cultural entity rather than a one-off mention."
            case .event, .eventSeries:
                return "It is showing enough repeat activity to look like a forming event pattern."
            case .venue, .organization, .publication, .brand:
                return "It is starting to behave like a node of movement rather than background context."
            case .concept, .scene, .unknown:
                return "It has enough repeat evidence to stay on the radar, even if the shape is still loose."
            }
        case .early:
            if historicalSourceDiversity > sourceFamilyCount && historicalAppearances > observationCount {
                return "The current read is still early, but the stored history says this is not the first time Malcome has seen it."
            }
            switch entityType {
            case .creator, .collective:
                return "It has an early live appearance through \(sourceSummary), which is enough to keep an eye on."
            case .event, .eventSeries:
                return "It has started to register through \(sourceSummary), but it is still early."
            case .venue, .organization, .publication, .brand:
                return "It is showing a first hint of movement through \(sourceSummary)."
            case .concept, .scene, .unknown:
                if !shape.isEmpty {
                    return "It has some early energy in \(shape.lowercased()), but the underlying entity still needs to get clearer."
                }
                return "It has some early energy, but the underlying entity still needs to get clearer."
            }
        }
    }

    private func watchlistEvidenceLine(for candidate: WatchlistCandidate) -> String {
        let currentMentionPhrase = "\(candidate.observationCount) current mention\(candidate.observationCount == 1 ? "" : "s")"
        let currentFamilyPhrase = "\(candidate.sourceFamilyCount) current source \(candidate.sourceFamilyCount == 1 ? "family" : "families")"
        let historicalMentionPhrase = "\(candidate.historicalMentionCount) historical mention\(candidate.historicalMentionCount == 1 ? "" : "s")"
        return "Current read: \(currentMentionPhrase) across \(currentFamilyPhrase). Stored history: \(historicalMentionPhrase)."
    }

    private func watchlistUpgradeTrigger(
        entityType: EntityType,
        stage: WatchlistStage,
        sourceFamilyCount: Int,
        classifications: Set<SourceClassification>
    ) -> String {
        if sourceFamilyCount > 1 {
            return "Another repeat appearance or movement into a new source role would likely promote it into a real signal."
        }

        switch entityType {
        case .creator, .collective:
            return "A second source family or a discovery-to-editorial crossover would make it much more convincing."
        case .event, .eventSeries:
            return "Another appearance on the next pass or confirmation outside the current source family would strengthen it fast."
        case .venue, .organization, .publication, .brand:
            return classifications.contains(.editorial)
                ? "A second source family or clearer downstream pickup would make it feel more than incidental."
                : "A second source family or stronger repeat visibility would make it feel more than incidental."
        case .concept, .scene, .unknown:
            return "It needs repetition, a cleaner reusable entity, or confirmation outside one source family."
        }
    }

    private func watchlistDisplayTitle(for observation: ObservationRecord, history: EntityHistoryRecord?) -> String {
        let canonicalName = history?.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let attributedName = observation.authorOrArtist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch observation.entityType {
        case .creator, .collective, .venue, .publication, .organization, .brand, .scene:
            if !canonicalName.isEmpty {
                return canonicalName
            }
            if !attributedName.isEmpty {
                return attributedName
            }
            return observation.title
        case .event, .eventSeries:
            if !canonicalName.isEmpty, canonicalName.count >= observation.title.count / 2 {
                return canonicalName
            }
            return observation.title
        case .concept, .unknown:
            return observation.title
        }
    }

    private func sourceFamilyKey(for sourceID: String, sourcesByID: [String: SourceRecord]) -> String {
        guard let source = sourcesByID[sourceID] else {
            return sourceID
        }
        if !source.sourceFamilyID.isEmpty {
            return source.sourceFamilyID
        }
        guard let url = URL(string: source.baseURL) else { return sourceID }
        let host = url.host?.lowercased() ?? sourceID
        return host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    }
}

struct LocalBriefGenerator: BriefGenerating {
    func generateBrief(from input: BriefingInput) async throws -> BriefRecord {
        generate(from: input)
    }

    func generate(from input: BriefingInput) -> BriefRecord {
        let topSignals = Array(input.signals.prefix(3))
        let bubbling = topSignals.map { packet in
            let displayName = packet.signal.canonicalName
            let sourceCount = packet.signal.sourceCount
            let sourceWord = sourceCount == 1 ? "source" : "sources"
            return "• \(displayName) is \(packet.signal.movement.rawValue) across \(sourceCount) \(sourceWord)."
        }.joined(separator: "\n")

        let whyItMatters = topSignals.map { packet in
            let movement = condensedSummary(packet.signal.movementSummary)
            let sourceLearning = condensedSummary(packet.signal.sourceInfluenceSummary)
            let suffix = shouldSurfaceSourceLearning(sourceLearning) ? " \(sourceLearning)" : ""
            return "• \(packet.signal.canonicalName): \(movement)\(suffix)"
        }.joined(separator: "\n")

        let whatChanged = topSignals.map { packet in
            let sources = packet.sourceNames.joined(separator: ", ")
            let sourcePhrase = sources.isEmpty ? "current sources" : sources
            return "• \(packet.signal.canonicalName): now seen \(packet.recentMentions) time\(packet.recentMentions == 1 ? "" : "s") recently, previously \(packet.priorMentions). Main evidence: \(sourcePhrase)."
        }.joined(separator: "\n")

        let watchClosely = topSignals.map { packet in
            "• \(packet.signal.canonicalName): \(condensedSummary(packet.signal.progressionSummary.isEmpty ? packet.signal.lifecycleSummary : packet.signal.progressionSummary))"
        }.joined(separator: "\n")

        let overcooked = input.signals
            .filter { $0.signal.saturationScore > 2.5 }
            .prefix(2)
            .map { "• \($0.signal.canonicalName) is spreading fast enough that it may already be moving out of the early-signal zone." }
            .joined(separator: "\n")

        let summary: String
        if let first = topSignals.first {
            let sourcePhrase = first.sourceNames.isEmpty ? "today’s source set" : first.sourceNames.joined(separator: ", ")
            let learnedTrust = briefLeadSourceTrustLine(from: first.signal.sourceInfluenceSummary)
            summary = "\(first.signal.canonicalName) leads today’s scan, with evidence from \(sourcePhrase). The interesting part is not raw volume, but the way it is beginning to gather recognizable support.\(learnedTrust)"
        } else {
            summary = "Today’s scan is light, but the app is tracking a few repeat appearances that should get sharper with another refresh cycle."
        }

        let body = """
        \(summary)

        What’s bubbling
        \(bubbling.isEmpty ? "• No clear emergent cluster yet." : bubbling)

        Why it matters
        \(whyItMatters.isEmpty ? "• More history is needed before the trendline gets persuasive." : whyItMatters)

        What changed
        \(whatChanged.isEmpty ? "• Not enough history yet to describe directional change." : whatChanged)

        What to keep watching
        \(watchClosely.isEmpty ? "• No clear progression path yet." : watchClosely)

        What may already be overcooked
        \(overcooked.isEmpty ? "• Nothing looks fully overcooked yet, which is a nice place to be." : overcooked)
        """

        let citations = input.signals.flatMap { packet in
            packet.observations.prefix(2).enumerated().map { index, observation in
                BriefCitation(
                    id: "\(packet.signal.id)-\(index)",
                    signalName: packet.signal.canonicalName,
                    sourceName: packet.sourceNames.first ?? "Unknown Source",
                    observationTitle: observation.title,
                    url: observation.url,
                    note: observation.excerpt ?? "Observed during the latest refresh."
                )
            }
        }

        return BriefRecord(
            id: UUID().uuidString,
            generatedAt: input.generatedAt,
            title: topSignals.first.map { "\($0.signal.canonicalName) and the Cultural Current" } ?? "Malcome Daily Brief",
            body: body,
            citationsPayload: citations,
            periodType: .daily
        )
    }

    private func condensedSummary(_ summary: String) -> String {
        let cleaned = summary.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let sentenceBoundaries = [". ", "! ", "? "]
        if let boundary = sentenceBoundaries.compactMap({ cleaned.range(of: $0) }).map(\.upperBound).min() {
            return String(cleaned[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.hasSuffix(".") || cleaned.hasSuffix("!") || cleaned.hasSuffix("?") {
            return cleaned
        }
        return cleaned
    }

    private func shouldSurfaceSourceLearning(_ summary: String) -> Bool {
        let cleaned = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        return !cleaned.localizedCaseInsensitiveContains("too early")
    }

    private func briefLeadSourceTrustLine(from summary: String) -> String {
        let cleaned = condensedSummary(summary)
        guard shouldSurfaceSourceLearning(cleaned) else { return "" }
        return " \(cleaned)"
    }
}

private extension BriefComposer {
    func watchlistLearningBullets(
        for candidates: [WatchlistCandidate],
        sourcesByID: [String: SourceRecord],
        sourceInfluenceByID: [String: SourceInfluenceStatRecord]
    ) -> [String] {
        var seenStats = Set<String>()
        var summaries: [String] = []

        for candidate in candidates {
            guard let stat = strongestInfluenceStat(
                for: candidate,
                sourcesByID: sourcesByID,
                sourceInfluenceByID: sourceInfluenceByID
            ) else {
                continue
            }
            guard seenStats.insert(stat.id).inserted else {
                continue
            }
            guard let summary = watchlistLearningSummary(for: stat, domain: candidate.domain) else {
                continue
            }
            summaries.append(summary)
        }

        return summaries
    }

    func watchlistLearningSummary(for stat: SourceInfluenceStatRecord, domain: CulturalDomain) -> String? {
        if stat.predictiveScore >= 0.7 {
            return "\(stat.displayName) has historically been one of Malcome’s more predictive early-reading lanes in \(domain.label.lowercased()), which makes names surfacing there more worth watching."
        }

        if stat.predictiveScore >= 0.25 {
            return "\(stat.displayName) has been a meaningfully trustworthy lane in \(domain.label.lowercased()), even when the current pass is still early."
        }

        if stat.predictiveScore <= -0.7 {
            return "\(stat.displayName) still reads as a more exploratory lane than a predictive one in \(domain.label.lowercased()), so Malcome is treating those names with caution."
        }

        return nil
    }

    func strongestInfluenceStat(
        for candidate: WatchlistCandidate,
        sourcesByID: [String: SourceRecord],
        sourceInfluenceByID: [String: SourceInfluenceStatRecord]
    ) -> SourceInfluenceStatRecord? {
        let domain = candidate.domain
        let sourceStats = candidate.sourceIDs.compactMap { sourceID -> SourceInfluenceStatRecord? in
            guard sourcesByID[sourceID] != nil else { return nil }
            return sourceInfluenceByID[sourceInfluenceStatID(scope: .source, scopeKey: sourceID, domain: domain)]
        }

        let familyStats = Set(candidate.sourceIDs.compactMap { sourceID in
            sourceFamilyKey(for: sourceID, sourcesByID: sourcesByID)
        }).compactMap { familyID in
            sourceInfluenceByID[sourceInfluenceStatID(scope: .family, scopeKey: familyID, domain: domain)]
        }

        return (Array(familyStats) + sourceStats)
            .filter { $0.sampleCount >= 3 }
            .sorted(by: compareInfluenceStats)
            .first
    }

    func compareInfluenceStats(_ lhs: SourceInfluenceStatRecord, _ rhs: SourceInfluenceStatRecord) -> Bool {
        if lhs.predictiveScore == rhs.predictiveScore {
            if lhs.sampleCount == rhs.sampleCount {
                return lhs.scope == .family && rhs.scope != .family
            }
            return lhs.sampleCount > rhs.sampleCount
        }
        return lhs.predictiveScore > rhs.predictiveScore
    }

    func sourceInfluenceStatID(scope: SourceInfluenceScope, scopeKey: String, domain: CulturalDomain) -> String {
        "\(scope.rawValue)::\(scopeKey)::\(domain.rawValue)"
    }
}
