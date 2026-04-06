import Foundation

struct SignalEngine: Sendable {
    struct ComputationResult: Sendable {
        let canonicalEntities: [CanonicalEntityRecord]
        let aliases: [EntityAliasRecord]
        let sourceRoles: [EntitySourceRoleRecord]
        let observationMappings: [String: String]
        let stageSnapshots: [EntityStageSnapshotRecord]
        let entityHistories: [EntityHistoryRecord]
        let signals: [SignalCandidateRecord]
        let runs: [SignalRunRecord]
        let pathwayHistories: [PathwayHistoryRecord]
        let pathwayStats: [PathwayStatRecord]
        let sourceInfluenceStats: [SourceInfluenceStatRecord]
        let outcomeConfirmations: [OutcomeConfirmationRecord]
    }

    func compute(
        from observations: [ObservationRecord],
        sourcesByID: [String: SourceRecord],
        runHistoryByName: [String: [SignalRunRecord]],
        pathwayStatsByPattern: [String: PathwayStatRecord],
        now: Date = .now
    ) -> ComputationResult {
        let resolution = resolveCanonicalEntities(from: observations, sourcesByID: sourcesByID)
        let sourceRolesByEntityID = Dictionary(grouping: resolution.sourceRoles, by: \.canonicalEntityID)
        let priorSourceInfluenceStats = buildSourceInfluenceStats(
            priorRunHistoryByName: runHistoryByName,
            currentRuns: [],
            sourcesByID: sourcesByID
        )
        let priorSourceInfluenceByKey = Dictionary(uniqueKeysWithValues: priorSourceInfluenceStats.map {
            (sourceInfluenceKey(scope: $0.scope, scopeKey: $0.scopeKey, domain: $0.domain), $0)
        })
        let stageSnapshots = buildEntityStageSnapshots(
            groupedObservations: resolution.groupedObservations,
            sourcesByID: sourcesByID
        )
        let outcomeConfirmations = buildOutcomeConfirmations(
            groupedObservations: resolution.groupedObservations,
            sourceRolesByEntityID: sourceRolesByEntityID,
            sourcesByID: sourcesByID
        )
        let signals = generateSignals(
            groupedObservations: resolution.groupedObservations,
            displayNameByID: resolution.displayNameByID,
            sourceRolesByEntityID: sourceRolesByEntityID,
            stageSnapshotsByEntityID: Dictionary(grouping: stageSnapshots, by: \.canonicalEntityID),
            outcomeConfirmationsByEntityID: Dictionary(grouping: outcomeConfirmations, by: \.canonicalEntityID),
            sourcesByID: sourcesByID,
            runHistoryByName: runHistoryByName,
            pathwayStatsByPattern: pathwayStatsByPattern,
            sourceInfluenceByKey: priorSourceInfluenceByKey,
            now: now
        )
        let signalMetaByEntityID = Dictionary(uniqueKeysWithValues: signals.map {
            ($0.canonicalEntityID, ($0.lifecycleState, $0.lifecycleSummary, $0.conversionState, $0.conversionSummary))
        })
        let entityHistories = buildEntityHistories(
            groupedObservations: resolution.groupedObservations,
            displayNameByID: resolution.displayNameByID,
            signalMetaByEntityID: signalMetaByEntityID
        )
        let runs = buildSignalRuns(from: signals, runAt: now)
        let pathwayHistories = buildPathwayHistories(from: signals, runAt: now)
        let pathwayStats = buildPathwayStats(
            priorRunHistoryByName: runHistoryByName,
            currentPathwayHistories: pathwayHistories
        )
        let sourceInfluenceStats = buildSourceInfluenceStats(
            priorRunHistoryByName: runHistoryByName,
            currentRuns: runs,
            sourcesByID: sourcesByID
        )

        return ComputationResult(
            canonicalEntities: resolution.entities,
            aliases: resolution.aliases,
            sourceRoles: resolution.sourceRoles,
            observationMappings: resolution.observationMappings,
            stageSnapshots: stageSnapshots,
            entityHistories: entityHistories,
            signals: runs.isEmpty ? [] : signals,
            runs: runs,
            pathwayHistories: pathwayHistories,
            pathwayStats: pathwayStats,
            sourceInfluenceStats: sourceInfluenceStats,
            outcomeConfirmations: outcomeConfirmations
        )
    }

    func generateSignals(
        groupedObservations: [String: [ObservationRecord]],
        displayNameByID: [String: String],
        sourceRolesByEntityID: [String: [EntitySourceRoleRecord]],
        stageSnapshotsByEntityID: [String: [EntityStageSnapshotRecord]],
        outcomeConfirmationsByEntityID: [String: [OutcomeConfirmationRecord]],
        sourcesByID: [String: SourceRecord],
        runHistoryByName: [String: [SignalRunRecord]],
        pathwayStatsByPattern: [String: PathwayStatRecord],
        sourceInfluenceByKey: [String: SourceInfluenceStatRecord],
        now: Date = .now
    ) -> [SignalCandidateRecord] {
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now
        let priorCutoff = Calendar.current.date(byAdding: .day, value: -10, to: now) ?? now
        let previousRunsByName = latestRuns(from: runHistoryByName)

        let rawSignals = groupedObservations.compactMap { canonicalEntityID, group in
            rawSignal(
                canonicalEntityID: canonicalEntityID,
                displayName: displayNameByID[canonicalEntityID] ?? canonicalEntityID,
                observations: group,
                sourceRoles: sourceRolesByEntityID[canonicalEntityID] ?? [],
                stageSnapshots: stageSnapshotsByEntityID[canonicalEntityID] ?? [],
                sourcesByID: sourcesByID,
                pathwayStatsByPattern: pathwayStatsByPattern,
                sourceInfluenceByKey: sourceInfluenceByKey,
                recentCutoff: recentCutoff,
                priorCutoff: priorCutoff,
                now: now
            )
        }
        .sorted {
            if $0.emergenceScore == $1.emergenceScore {
                return $0.latestSeenAt > $1.latestSeenAt
            }
            return $0.emergenceScore > $1.emergenceScore
        }

        let activeSignals = rawSignals.enumerated().map { index, raw in
            let previous = previousRunsByName[raw.canonicalEntityID] ?? previousRunsByName[raw.canonicalName]
            let runHistory = runHistoryByName[raw.canonicalEntityID] ?? runHistoryByName[raw.canonicalName] ?? []
            let movement = classifyMovement(for: raw, previous: previous, rank: index + 1)
            let summary = buildMovementSummary(
                for: raw,
                previous: previous,
                movement: movement,
                rank: index + 1,
                sourcesByID: sourcesByID
            )
            let lifecycle = classifyLifecycle(
                for: raw,
                previous: previous,
                runHistory: runHistory,
                movement: movement
            )
            let conversion = classifyConversion(
                for: raw,
                lifecycle: lifecycle,
                outcomeConfirmations: outcomeConfirmationsByEntityID[raw.canonicalEntityID] ?? [],
                runHistory: runHistory
            )

            return SignalCandidateRecord(
                id: UUID().uuidString,
                canonicalEntityID: raw.canonicalEntityID,
                domain: raw.domain,
                canonicalName: raw.canonicalName,
                entityType: raw.entityType,
                firstSeenAt: raw.firstSeenAt,
                latestSeenAt: raw.latestSeenAt,
                sourceCount: raw.sourceCount,
                observationCount: raw.observationCount,
                currentSourceCount: raw.currentSourceCount,
                currentSourceFamilyCount: raw.currentSourceFamilyCount,
                currentObservationCount: raw.currentObservationCount,
                historicalSourceCount: raw.sourceCount,
                historicalObservationCount: raw.observationCount,
                growthScore: raw.growthScore,
                diversityScore: raw.diversityScore,
                repeatAppearanceScore: raw.repeatAppearanceScore,
                progressionScore: raw.progressionScore,
                saturationScore: raw.saturationScore,
                emergenceScore: raw.emergenceScore,
                confidence: raw.confidence,
                movement: movement,
                maturity: raw.maturity,
                lifecycleState: lifecycle.state,
                conversionState: conversion.state,
                outcomeTiers: conversion.outcomeTiers,
                supportingSourceIDs: raw.supportingSourceIDs,
                progressionStages: raw.progressionStages,
                progressionPattern: raw.progressionPattern,
                movementSummary: summary,
                maturitySummary: raw.maturitySummary,
                lifecycleSummary: lifecycle.summary,
                conversionSummary: conversion.summary,
                pathwaySummary: raw.pathwaySummary,
                sourceInfluenceSummary: raw.sourceInfluenceSummary,
                progressionSummary: raw.progressionSummary,
                evidenceSummary: raw.evidenceSummary
            )
        }

        let missingSignals = synthesizeAbsentSignals(
            activeCanonicalEntityIDs: Set(activeSignals.map(\.canonicalEntityID)),
            runHistoryByName: runHistoryByName,
            now: now
        )

        return (activeSignals + missingSignals)
            .sorted { lhs, rhs in
                if lhs.emergenceScore == rhs.emergenceScore {
                    return lhs.latestSeenAt > rhs.latestSeenAt
                }
                return lhs.emergenceScore > rhs.emergenceScore
            }
    }

    func buildSignalRuns(from signals: [SignalCandidateRecord], runAt: Date) -> [SignalRunRecord] {
        signals.enumerated().map { index, signal in
            SignalRunRecord(
                id: UUID().uuidString,
                runAt: runAt,
                canonicalEntityID: signal.canonicalEntityID,
                canonicalName: signal.canonicalName,
                domain: signal.domain,
                entityType: signal.entityType,
                rank: index + 1,
                score: signal.emergenceScore,
                supportingSourceIDs: signal.supportingSourceIDs,
                observationCount: signal.observationCount,
                sourceCount: signal.sourceCount,
                currentSourceCount: signal.currentSourceCount,
                currentSourceFamilyCount: signal.currentSourceFamilyCount,
                currentObservationCount: signal.currentObservationCount,
                historicalSourceCount: signal.historicalSourceCount,
                historicalObservationCount: signal.historicalObservationCount,
                movement: signal.movement,
                maturity: signal.maturity,
                lifecycleState: signal.lifecycleState,
                conversionState: signal.conversionState,
                outcomeTiers: signal.outcomeTiers,
                progressionPattern: signal.progressionPattern,
                explanation: signal.movementSummary,
                lifecycleSummary: signal.lifecycleSummary,
                conversionSummary: signal.conversionSummary,
                sourceInfluenceSummary: signal.sourceInfluenceSummary
            )
        }
    }

    func buildPathwayHistories(from signals: [SignalCandidateRecord], runAt: Date) -> [PathwayHistoryRecord] {
        signals.compactMap { signal in
            guard !signal.progressionPattern.isEmpty else { return nil }
            return PathwayHistoryRecord(
                id: "\(signal.canonicalEntityID)::\(ISO8601DateFormatter().string(from: runAt))",
                runAt: runAt,
                canonicalEntityID: signal.canonicalEntityID,
                pathwayPattern: signal.progressionPattern,
                domain: signal.domain,
                lifecycleState: signal.lifecycleState,
                conversionState: signal.conversionState,
                signalScore: signal.emergenceScore
            )
        }
    }

    func buildPathwayStats(
        priorRunHistoryByName: [String: [SignalRunRecord]],
        currentPathwayHistories: [PathwayHistoryRecord]
    ) -> [PathwayStatRecord] {
        let priorHistories = priorRunHistoryByName.values
            .flatMap { $0 }
            .compactMap { run -> PathwayHistoryRecord? in
                guard !run.progressionPattern.isEmpty else { return nil }
                return PathwayHistoryRecord(
                    id: run.id,
                    runAt: run.runAt,
                    canonicalEntityID: run.canonicalEntityID.isEmpty ? run.canonicalName : run.canonicalEntityID,
                pathwayPattern: run.progressionPattern,
                domain: run.domain,
                lifecycleState: run.lifecycleState,
                conversionState: run.conversionState,
                signalScore: run.score
            )
        }

        let grouped = Dictionary(grouping: priorHistories + currentPathwayHistories) {
            pathwayKey(pattern: $0.pathwayPattern, domain: $0.domain)
        }

        return grouped.compactMap { key, histories in
            guard let exemplar = histories.first else { return nil }
            let sampleCount = histories.count
            let advancingCount = histories.filter { $0.lifecycleState == .advancing }.count
            let peakedCount = histories.filter { $0.lifecycleState == .peaked }.count
            let coolingCount = histories.filter { $0.lifecycleState == .cooling }.count
            let failedCount = histories.filter { $0.lifecycleState == .failed }.count
            let disappearedCount = histories.filter { $0.lifecycleState == .disappeared }.count
            let conversionCount = histories.filter { $0.conversionState == .converted }.count
            let stalledConversionCount = histories.filter { $0.conversionState == .stalledBeforeConversion }.count
            let neverConvertedCount = histories.filter { $0.conversionState == .neverConverted }.count
            let successWeight = Double(advancingCount) * 0.9 + Double(peakedCount) * 1.4
            let failureWeight = Double(failedCount) * 1.3 + Double(disappearedCount) * 1.0 + Double(coolingCount) * 0.5
            let conversionWeight = Double(conversionCount) * 1.8 - Double(stalledConversionCount) * 0.8 - Double(neverConvertedCount) * 1.4
            let predictiveScore = ((successWeight - failureWeight + conversionWeight) / Double(sampleCount)) + log(Double(sampleCount) + 1) * 0.35
            let summary = pathwaySummary(
                pattern: exemplar.pathwayPattern,
                sampleCount: sampleCount,
                advancingCount: advancingCount,
                peakedCount: peakedCount,
                coolingCount: coolingCount,
                failedCount: failedCount,
                disappearedCount: disappearedCount,
                conversionCount: conversionCount,
                stalledConversionCount: stalledConversionCount,
                neverConvertedCount: neverConvertedCount,
                predictiveScore: predictiveScore
            )

            return PathwayStatRecord(
                id: key,
                pathwayPattern: exemplar.pathwayPattern,
                domain: exemplar.domain,
                sampleCount: sampleCount,
                advancingCount: advancingCount,
                peakedCount: peakedCount,
                coolingCount: coolingCount,
                failedCount: failedCount,
                disappearedCount: disappearedCount,
                successWeight: successWeight,
                failureWeight: failureWeight,
                conversionCount: conversionCount,
                stalledConversionCount: stalledConversionCount,
                neverConvertedCount: neverConvertedCount,
                conversionWeight: conversionWeight,
                predictiveScore: predictiveScore,
                summary: summary
            )
        }
        .sorted { lhs, rhs in
            if lhs.predictiveScore == rhs.predictiveScore {
                return lhs.sampleCount > rhs.sampleCount
            }
            return lhs.predictiveScore > rhs.predictiveScore
        }
    }

    func buildSourceInfluenceStats(
        priorRunHistoryByName: [String: [SignalRunRecord]],
        currentRuns: [SignalRunRecord],
        sourcesByID: [String: SourceRecord]
    ) -> [SourceInfluenceStatRecord] {
        let priorRuns = deduplicatedRuns(from: priorRunHistoryByName)
        let runs = priorRuns + currentRuns

        struct Accumulator {
            var displayName: String
            var domain: CulturalDomain
            var sampleCount = 0
            var advancingCount = 0
            var peakedCount = 0
            var failedCount = 0
            var disappearedCount = 0
            var conversionCount = 0
            var stalledConversionCount = 0
            var neverConvertedCount = 0
            var totalScore = 0.0
        }

        var grouped: [String: (SourceInfluenceScope, String, Accumulator)] = [:]

        func update(scope: SourceInfluenceScope, scopeKey: String, displayName: String, domain: CulturalDomain, with run: SignalRunRecord) {
            let key = sourceInfluenceKey(scope: scope, scopeKey: scopeKey, domain: domain)
            var entry = grouped[key] ?? (
                scope,
                scopeKey,
                Accumulator(displayName: displayName, domain: domain)
            )
            entry.2.sampleCount += 1
            if run.lifecycleState == .advancing { entry.2.advancingCount += 1 }
            if run.lifecycleState == .peaked { entry.2.peakedCount += 1 }
            if run.lifecycleState == .failed { entry.2.failedCount += 1 }
            if run.lifecycleState == .disappeared { entry.2.disappearedCount += 1 }
            if run.conversionState == .converted { entry.2.conversionCount += 1 }
            if run.conversionState == .stalledBeforeConversion { entry.2.stalledConversionCount += 1 }
            if run.conversionState == .neverConverted { entry.2.neverConvertedCount += 1 }
            entry.2.totalScore += run.score
            grouped[key] = entry
        }

        for run in runs {
            let sourceIDs = Array(Set(run.supportingSourceIDs)).sorted()
            let familyIDs = Set(sourceIDs.compactMap { sourcesByID[$0]?.sourceFamilyID })

            for sourceID in sourceIDs {
                guard let source = sourcesByID[sourceID] else { continue }
                update(
                    scope: .source,
                    scopeKey: sourceID,
                    displayName: source.name,
                    domain: run.domain,
                    with: run
                )
            }

            for familyID in familyIDs {
                let familyName = sourceIDs
                    .compactMap { sourcesByID[$0] }
                    .first(where: { $0.sourceFamilyID == familyID })?.sourceFamilyName ?? familyID
                update(
                    scope: .family,
                    scopeKey: familyID,
                    displayName: familyName,
                    domain: run.domain,
                    with: run
                )
            }
        }

        return grouped.values.map { scope, scopeKey, accumulator in
            let successWeight = Double(accumulator.advancingCount) * 1.4
                + Double(accumulator.peakedCount) * 2.1
                + Double(accumulator.conversionCount) * 2.4
            let failureWeight = Double(accumulator.failedCount) * 1.7
                + Double(accumulator.disappearedCount) * 1.2
                + Double(accumulator.stalledConversionCount) * 0.8
                + Double(accumulator.neverConvertedCount) * 1.4
            let predictiveScore = ((successWeight - failureWeight) / Double(max(1, accumulator.sampleCount)))
                + log(Double(accumulator.sampleCount) + 1) * 0.28
            let averageSignalScore = accumulator.totalScore / Double(max(1, accumulator.sampleCount))

            return SourceInfluenceStatRecord(
                id: "\(scope.rawValue)::\(scopeKey)::\(accumulator.domain.rawValue)",
                scope: scope,
                scopeKey: scopeKey,
                displayName: accumulator.displayName,
                domain: accumulator.domain,
                sampleCount: accumulator.sampleCount,
                advancingCount: accumulator.advancingCount,
                peakedCount: accumulator.peakedCount,
                failedCount: accumulator.failedCount,
                disappearedCount: accumulator.disappearedCount,
                conversionCount: accumulator.conversionCount,
                stalledConversionCount: accumulator.stalledConversionCount,
                neverConvertedCount: accumulator.neverConvertedCount,
                averageSignalScore: averageSignalScore,
                predictiveScore: predictiveScore,
                summary: sourceInfluenceSummary(
                    displayName: accumulator.displayName,
                    scope: scope,
                    sampleCount: accumulator.sampleCount,
                    advancingCount: accumulator.advancingCount,
                    peakedCount: accumulator.peakedCount,
                    failedCount: accumulator.failedCount,
                    disappearedCount: accumulator.disappearedCount,
                    conversionCount: accumulator.conversionCount,
                    neverConvertedCount: accumulator.neverConvertedCount,
                    predictiveScore: predictiveScore
                )
            )
        }
        .sorted {
            if $0.predictiveScore == $1.predictiveScore {
                return $0.sampleCount > $1.sampleCount
            }
            return $0.predictiveScore > $1.predictiveScore
        }
    }

    func buildEntityHistories(
        groupedObservations: [String: [ObservationRecord]],
        displayNameByID: [String: String],
        signalMetaByEntityID: [String: (SignalLifecycleState, String, ConversionState, String)]
    ) -> [EntityHistoryRecord] {
        groupedObservations.compactMap { canonicalEntityID, group in
            guard let canonicalName = displayNameByID[canonicalEntityID] else { return nil }
            let countedGroup = dedupedHistoryObservations(group)
            let firstSeen = countedGroup.map(observationDate).min() ?? .distantPast
            let lastSeen = countedGroup.map(observationDate).max() ?? .distantPast
            let signalMeta = signalMetaByEntityID[canonicalEntityID] ?? (.emerging, "Still gathering enough historical signal to classify a full lifecycle.", .pending, "Too early to call conversion.")
            return EntityHistoryRecord(
                id: canonicalEntityID,
                canonicalEntityID: canonicalEntityID,
                canonicalName: canonicalName,
                domain: dominantDomain(in: countedGroup),
                entityType: inferType(from: countedGroup),
                firstSeenAt: firstSeen,
                lastSeenAt: lastSeen,
                appearanceCount: countedGroup.count,
                sourceDiversity: Set(countedGroup.map(\.sourceID)).count,
                lifecycleState: signalMeta.0,
                lifecycleSummary: signalMeta.1,
                conversionState: signalMeta.2,
                conversionSummary: signalMeta.3
            )
        }
        .sorted { lhs, rhs in
            if lhs.appearanceCount == rhs.appearanceCount {
                return lhs.lastSeenAt > rhs.lastSeenAt
            }
            return lhs.appearanceCount > rhs.appearanceCount
        }
    }

    func buildEntityStageSnapshots(
        groupedObservations: [String: [ObservationRecord]],
        sourcesByID: [String: SourceRecord]
    ) -> [EntityStageSnapshotRecord] {
        groupedObservations.flatMap { canonicalEntityID, group in
            let byDay = Dictionary(grouping: group) { observation in
                Calendar(identifier: .gregorian).startOfDay(for: observationDate(observation))
            }
            return byDay.compactMap { entry -> EntityStageSnapshotRecord? in
                let (day, dayGroup) = entry
                let countedDayGroup = dedupedHistoryObservations(dayGroup)
                let classifications = countedDayGroup.compactMap { sourcesByID[$0.sourceID]?.classification }
                guard let stage = highestStage(in: classifications) else { return nil }
                let sourceCount = Set(countedDayGroup.map(\.sourceID)).count
                let stageBonus = Double(stageRank(stage))
                let signalScore = Double(countedDayGroup.count) * 0.8 + Double(sourceCount) * 1.2 + stageBonus
                let dayKey = ISO8601DateFormatter().string(from: day)
                return EntityStageSnapshotRecord(
                    id: "\(canonicalEntityID)::\(dayKey)",
                    canonicalEntityID: canonicalEntityID,
                    date: day,
                    stage: stage,
                    sourceCount: sourceCount,
                    signalScore: signalScore
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.canonicalEntityID == rhs.canonicalEntityID {
                return lhs.date > rhs.date
            }
            return lhs.canonicalEntityID < rhs.canonicalEntityID
        }
    }

    func buildOutcomeConfirmations(
        groupedObservations: [String: [ObservationRecord]],
        sourceRolesByEntityID: [String: [EntitySourceRoleRecord]],
        sourcesByID: [String: SourceRecord]
    ) -> [OutcomeConfirmationRecord] {
        groupedObservations.flatMap { canonicalEntityID, observations in
            let sourceRoles = sourceRolesByEntityID[canonicalEntityID] ?? []
            let orderedRoles = sourceRoles.sorted { $0.firstSeenAt < $1.firstSeenAt }
            let firstStage = orderedRoles.first?.sourceClassification
            let domains = Set(observations.map(\.domain).filter { $0 != .generalCulture })
            var confirmations: [OutcomeConfirmationRecord] = []

            let editorialRoles = orderedRoles.filter { $0.sourceClassification == .editorial }
            if !editorialRoles.isEmpty,
               firstStage != .editorial || editorialRoles.count >= 2,
               let confirmedAt = editorialRoles.map(\.firstSeenAt).min() {
                confirmations.append(OutcomeConfirmationRecord(
                    id: "\(canonicalEntityID)::major_editorial_coverage",
                    canonicalEntityID: canonicalEntityID,
                    outcomeTier: .majorEditorialCoverage,
                    confirmedAt: confirmedAt,
                    sourceIDs: editorialRoles.map(\.sourceID),
                    summary: "Confirmed by stronger editorial attention."
                ))
            }

            let venueRoles = orderedRoles.filter { $0.sourceClassification == .venue }
            let largerVenueRoles = venueRoles.filter { role in
                let tier = sourcesByID[role.sourceID]?.tier ?? .c
                return tier == .b || tier == .a
            }
            if !largerVenueRoles.isEmpty,
               firstStage != .venue,
               let confirmedAt = largerVenueRoles.map(\.firstSeenAt).min() {
                confirmations.append(OutcomeConfirmationRecord(
                    id: "\(canonicalEntityID)::larger_venue_tier",
                    canonicalEntityID: canonicalEntityID,
                    outcomeTier: .largerVenueTier,
                    confirmedAt: confirmedAt,
                    sourceIDs: largerVenueRoles.map(\.sourceID),
                    summary: "Confirmed by venue progression into a broader room tier."
                ))
            }

            let institutionalRoles = orderedRoles.filter {
                $0.sourceClassification == .institutional || $0.sourceClassification == .commercialScaling
            }
            if !institutionalRoles.isEmpty,
               let confirmedAt = institutionalRoles.map(\.firstSeenAt).min() {
                confirmations.append(OutcomeConfirmationRecord(
                    id: "\(canonicalEntityID)::institutional_pickup",
                    canonicalEntityID: canonicalEntityID,
                    outcomeTier: .institutionalPickup,
                    confirmedAt: confirmedAt,
                    sourceIDs: institutionalRoles.map(\.sourceID),
                    summary: "Confirmed by institutional or scaled pickup."
                ))
            }

            if domains.count >= 2,
               let confirmedAt = firstCrossDomainDate(in: observations) {
                confirmations.append(OutcomeConfirmationRecord(
                    id: "\(canonicalEntityID)::cross_domain_appearance",
                    canonicalEntityID: canonicalEntityID,
                    outcomeTier: .crossDomainAppearance,
                    confirmedAt: confirmedAt,
                    sourceIDs: Array(Set(observations.map(\.sourceID))).sorted(),
                    summary: "Confirmed by crossing into more than one cultural domain."
                ))
            }

            return confirmations
        }
    }

    private func resolveCanonicalEntities(
        from observations: [ObservationRecord],
        sourcesByID: [String: SourceRecord]
    ) -> CanonicalResolution {
        var entitiesByID: [String: MutableCanonicalEntity] = [:]
        var exactLookup: [String: Set<String>] = [:]
        var relaxedLookup: [String: Set<String>] = [:]
        var observationMappings: [String: String] = [:]
        var aliasSightings: [String: [AliasSighting]] = [:]

        let sortedObservations = observations.sorted { observationDate($0) < observationDate($1) }

        for observation in sortedObservations {
            let aliasTexts = aliasTexts(for: observation)
            let exactKeys = Set(aliasTexts.map(HTMLSupport.normalizedAlias).filter { !$0.isEmpty })
            let relaxedKeys = Set(aliasTexts.map(HTMLSupport.relaxedAliasKey).filter { $0.count >= 4 })
            let preferredName = preferredDisplayName(for: observation, aliases: aliasTexts)
            let entityType = inferType(from: [observation])
            let domain = observation.domain
            let observedAt = observationDate(observation)
            let source = sourcesByID[observation.sourceID]

            let mergeDecision = matchedEntity(
                exactKeys: exactKeys,
                relaxedKeys: relaxedKeys,
                preferredName: preferredName,
                domain: domain,
                entityType: entityType,
                sourceID: observation.sourceID,
                sourceClassification: source?.classification,
                observedAt: observedAt,
                entitiesByID: entitiesByID,
                exactLookup: exactLookup,
                relaxedLookup: relaxedLookup
            )

            let canonicalEntityID: String
            if let mergeDecision {
                canonicalEntityID = mergeDecision.entityID
            } else {
                canonicalEntityID = canonicalID(
                    domain: domain,
                    entityType: entityType,
                    preferredName: preferredName,
                    fallback: observation.normalizedEntityName
                )
                entitiesByID[canonicalEntityID] = MutableCanonicalEntity(
                    id: canonicalEntityID,
                    displayName: preferredName,
                    domain: domain,
                    entityType: entityType,
                    mergeConfidence: 1.0,
                    mergeSummary: "No merge required yet. This identity is still anchored to direct source evidence without a risky cross-observation merge."
                )
            }

            guard var entity = entitiesByID[canonicalEntityID] else { continue }
            entity.displayName = betterDisplayName(current: entity.displayName, candidate: preferredName)
            entity.aliases.formUnion(aliasTexts)
            entity.normalizedAliases.formUnion(exactKeys)
            entity.relaxedAliases.formUnion(relaxedKeys)
            entity.sourceIDs.insert(observation.sourceID)
            if let classification = source?.classification {
                entity.sourceClassifications.insert(classification)
            }
            entity.firstSeenAt = min(entity.firstSeenAt ?? observedAt, observedAt)
            entity.lastSeenAt = max(entity.lastSeenAt ?? observedAt, observedAt)
            if let mergeDecision {
                if mergeDecision.confidence < entity.mergeConfidence {
                    entity.mergeConfidence = mergeDecision.confidence
                    entity.mergeSummary = mergeDecision.summary
                }
            }
            entitiesByID[canonicalEntityID] = entity
            observationMappings[observation.id] = canonicalEntityID

            for exact in exactKeys {
                exactLookup[exact, default: []].insert(canonicalEntityID)
            }
            for relaxed in relaxedKeys {
                relaxedLookup[relaxed, default: []].insert(canonicalEntityID)
            }

            let sourceID = sourcesByID[observation.sourceID]?.id
            let sourceAliasSightings = aliasTexts.map {
                AliasSighting(text: $0, normalized: HTMLSupport.normalizedAlias($0), sourceID: sourceID)
            }
            aliasSightings[canonicalEntityID, default: []].append(contentsOf: sourceAliasSightings)
        }

        let groupedObservations = Dictionary(grouping: observations) {
            observationMappings[$0.id] ?? $0.normalizedEntityName
        }

        let canonicalEntities = entitiesByID.values
            .map { entity in
                CanonicalEntityRecord(
                    id: entity.id,
                    displayName: entity.displayName,
                    domain: entity.domain,
                    entityType: entity.entityType,
                    aliases: Array(entity.aliases).sorted(),
                    mergeConfidence: entity.mergeConfidence,
                    mergeSummary: entity.mergeSummary
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let aliases = aliasSightings.flatMap { canonicalEntityID, sightings in
            uniqueAliasRecords(canonicalEntityID: canonicalEntityID, sightings: sightings)
        }

        let sourceRoles = groupedObservations.map { canonicalEntityID, group in
            Dictionary(grouping: group, by: \.sourceID).compactMap { item -> EntitySourceRoleRecord? in
                let sourceID = item.key
                let sourceGroup = dedupedHistoryObservations(item.value)
                guard let source = sourcesByID[sourceID] else { return nil }
                return EntitySourceRoleRecord(
                    id: "\(canonicalEntityID)::\(sourceID)",
                    canonicalEntityID: canonicalEntityID,
                    sourceID: sourceID,
                    sourceClassification: source.classification,
                    firstSeenAt: sourceGroup.map(observationDate).min() ?? .distantPast,
                    lastSeenAt: sourceGroup.map(observationDate).max() ?? .distantPast,
                    appearanceCount: sourceGroup.count
                )
            }
        }
        .flatMap { $0 }
        .sorted { lhs, rhs in
            if lhs.canonicalEntityID == rhs.canonicalEntityID {
                return lhs.sourceID < rhs.sourceID
            }
            return lhs.canonicalEntityID < rhs.canonicalEntityID
        }

        let displayNameByID = Dictionary(uniqueKeysWithValues: canonicalEntities.map { ($0.id, $0.displayName) })

        return CanonicalResolution(
            entities: canonicalEntities,
            aliases: aliases,
            sourceRoles: sourceRoles,
            observationMappings: observationMappings,
            groupedObservations: groupedObservations,
            displayNameByID: displayNameByID
        )
    }

    private func rawSignal(
        canonicalEntityID: String,
        displayName: String,
        observations group: [ObservationRecord],
        sourceRoles: [EntitySourceRoleRecord],
        stageSnapshots: [EntityStageSnapshotRecord],
        sourcesByID: [String: SourceRecord],
        pathwayStatsByPattern: [String: PathwayStatRecord],
        sourceInfluenceByKey: [String: SourceInfluenceStatRecord],
        recentCutoff: Date,
        priorCutoff: Date,
        now: Date
    ) -> RawSignal? {
        guard isEligibleSignalName(displayName), group.count >= 2 else { return nil }

        let countedGroup = dedupedHistoryObservations(group)
        guard countedGroup.count >= 2 else { return nil }

        let recent = countedGroup.filter { observationDate($0) >= recentCutoff }
        let prior = countedGroup.filter {
            let seenAt = observationDate($0)
            return seenAt < recentCutoff && seenAt >= priorCutoff
        }
        let sources = Set(countedGroup.map(\.sourceID))
        let recentSources = Set(recent.map(\.sourceID))
        let priorSources = Set(prior.map(\.sourceID))
        let sourceFamilies = Set(sources.map { sourceFamilyKey(for: $0, sourcesByID: sourcesByID) })
        let recentSourceFamilies = Set(recentSources.map { sourceFamilyKey(for: $0, sourcesByID: sourcesByID) })
        let priorSourceFamilies = Set(priorSources.map { sourceFamilyKey(for: $0, sourcesByID: sourcesByID) })
        let tierARecentSources = Set(recent.compactMap { sourcesByID[$0.sourceID]?.tier == .a ? $0.sourceID : nil })
        let tierATotalSources = Set(countedGroup.compactMap { sourcesByID[$0.sourceID]?.tier == .a ? $0.sourceID : nil })
        let tierARecentFamilies = Set(tierARecentSources.map { sourceFamilyKey(for: $0, sourcesByID: sourcesByID) })
        let tierATotalFamilies = Set(tierATotalSources.map { sourceFamilyKey(for: $0, sourcesByID: sourcesByID) })
        let distinctSnapshots = Set(countedGroup.map(\.snapshotID))
        let recurringSeriesOnly = countedGroup.allSatisfy { $0.tags.contains("recurring_series") }
        let roundupOnly = countedGroup.allSatisfy { $0.tags.contains("roundup") }
        let selfBrandedOnly = countedGroup.allSatisfy { $0.tags.contains("self_branded") }
        let signalDomain = dominantDomain(in: countedGroup)
        let signalType = inferType(from: countedGroup)
        let progression = progressionIntelligence(
            canonicalName: displayName,
            sourceRoles: sourceRoles,
            sourcesByID: sourcesByID
        )
        let pathwayStat = progression.pattern.isEmpty ? nil : pathwayStatsByPattern[pathwayKey(pattern: progression.pattern, domain: signalDomain)]
        let horizon = horizonIntelligence(
            displayName: displayName,
            stageSnapshots: stageSnapshots,
            progression: progression,
            latestSeen: countedGroup.map(observationDate).max() ?? now,
            now: now
        )

        guard !recent.isEmpty else { return nil }
        guard sourceFamilies.count >= 2 || distinctSnapshots.count >= 4 || progression.stages.count >= 2 else { return nil }
        if sourceFamilies.count == 1 && (recurringSeriesOnly || roundupOnly || selfBrandedOnly) {
            return nil
        }

        let firstSeen = countedGroup.map(observationDate).min() ?? now
        let latestSeen = countedGroup.map(observationDate).max() ?? now
        let sourceCount = sources.count
        let observationCount = countedGroup.count
        let familyCount = sourceFamilies.count
        let currentSourceCount = recentSources.count
        let recentFamilyCount = recentSourceFamilies.count
        let currentObservationCount = recent.count
        let sameFamilySupport = sourceCount > 1 && familyCount == 1

        if sameFamilySupport && progression.stages.count < 2 {
            return nil
        }

        let growthScore: Double = {
            if prior.isEmpty {
                return Double(recentFamilyCount) * 2.4
                    + Double(max(0, recentSources.count - recentFamilyCount)) * 0.35
                    + Double(recent.count) * 0.25
            }
            let familyGrowth = Double(recentSourceFamilies.count - priorSourceFamilies.count) * 2.6
            let sourceGrowth = Double(recentSources.count - priorSources.count) * 0.6
            let mentionGrowth = Double(recent.count - prior.count) * 0.45
            return max(0, familyGrowth + sourceGrowth + mentionGrowth + Double(recentFamilyCount) * 0.7)
        }()

        let diversityScore = Double(recentFamilyCount) * 3.1
            + Double(max(0, recentSources.count - recentFamilyCount)) * 0.35
            + Double(tierARecentFamilies.count) * 1.9
        let repeatAppearanceScore = log(Double(distinctSnapshots.count) + 1) * 2.0

        var saturationScore = 0.0
        if familyCount >= 5 {
            saturationScore += Double(familyCount - 4) * 1.8
        }
        if observationCount >= 8 {
            saturationScore += Double(observationCount - 7) * 0.9
        }
        if displayName.count <= 3 {
            saturationScore += 1.5
        }
        if familyCount == 1 {
            saturationScore += 3.0
        }
        if recurringSeriesOnly {
            saturationScore += 3.0
        }
        if roundupOnly {
            saturationScore += 2.4
        }
        if selfBrandedOnly {
            saturationScore += 2.8
        }
        if sameFamilySupport {
            saturationScore += 2.8
        }
        if tierATotalFamilies.isEmpty {
            saturationScore += 1.8
        }

        let recentSourceInfluence = recentSources.compactMap {
            sourceInfluenceByKey[sourceInfluenceKey(scope: .source, scopeKey: $0, domain: signalDomain)]
        }
        let recentFamilyInfluence = recentSourceFamilies.compactMap {
            sourceInfluenceByKey[sourceInfluenceKey(scope: .family, scopeKey: $0, domain: signalDomain)]
        }
        let sourceInfluenceBonus = learnedInfluenceBonus(
            sourceStats: recentSourceInfluence,
            familyStats: recentFamilyInfluence
        )
        let pathwayBonus = pathwayStat.map { max(-2.4, min(3.6, $0.predictiveScore)) } ?? 0
        let emergenceScore = max(0, growthScore + diversityScore + repeatAppearanceScore + progression.score + pathwayBonus + sourceInfluenceBonus + horizon.bonus - saturationScore)
        let confidence = min(
            0.98,
            0.18
                + Double(familyCount) * 0.18
                + Double(max(0, sourceCount - familyCount)) * 0.03
                + Double(tierATotalFamilies.count) * 0.1
                + min(Double(distinctSnapshots.count), 4) * 0.07
        )

        let sortedEvidence = group.sorted { observationDate($0) > observationDate($1) }
        var seenTitles = Set<String>()
        let uniqueEvidence = sortedEvidence.compactMap { observation -> String? in
            guard seenTitles.insert(observation.title).inserted else { return nil }
            return observation.title
        }
        let evidenceHeadline = uniqueEvidence.first ?? displayName
        let sourceInfluenceSummary = sourceInfluenceNarrative(
            sourceStats: recentSourceInfluence,
            familyStats: recentFamilyInfluence
        )
        let evidenceSummary: String
        if sameFamilySupport {
            evidenceSummary = "\(evidenceHeadline) • support is still concentrated in one source family."
        } else {
            evidenceSummary = "\(evidenceHeadline) • corroborated across \(familyCount) independent source families."
        }

        guard emergenceScore >= 4.5 else { return nil }

        return RawSignal(
            canonicalEntityID: canonicalEntityID,
            domain: signalDomain,
            canonicalName: displayName,
            entityType: signalType,
            firstSeenAt: firstSeen,
            latestSeenAt: latestSeen,
            sourceCount: sourceCount,
            observationCount: observationCount,
            currentSourceCount: currentSourceCount,
            currentSourceFamilyCount: recentFamilyCount,
            currentObservationCount: currentObservationCount,
            growthScore: growthScore,
            diversityScore: diversityScore,
            repeatAppearanceScore: repeatAppearanceScore,
            progressionScore: progression.score,
            saturationScore: saturationScore,
            emergenceScore: emergenceScore,
            confidence: confidence,
            maturity: horizon.maturity,
            supportingSourceIDs: Array(recentSources.isEmpty ? sources : recentSources).sorted(),
            supportingSourceFamilyCount: familyCount,
            progressionStages: progression.stages,
            progressionPattern: progression.pattern,
            maturitySummary: horizon.summary,
            pathwaySummary: pathwayStat?.summary ?? "No learned pathway history yet for this route.",
            sourceInfluenceSummary: sourceInfluenceSummary,
            progressionSummary: progression.summary,
            evidenceSummary: evidenceSummary
        )
    }

    private func inferType(from observations: [ObservationRecord]) -> EntityType {
        let explicitTypes = observations.map(\.entityType).filter { $0 != .unknown }
        if let dominant = mode(of: explicitTypes) {
            return dominant
        }
        if observations.contains(where: { $0.tags.contains("event") || $0.tags.contains("venue-calendar") || $0.entityType == .event }) {
            return .event
        }
        if observations.contains(where: { ($0.location ?? "").isEmpty == false && $0.entityType == .venue }) {
            return .venue
        }
        if observations.contains(where: { $0.tags.contains("editorial") }) {
            return .concept
        }
        return .scene
    }

    private func aliasTexts(for observation: ObservationRecord) -> [String] {
        var aliases = HTMLSupport.aliasCandidates(title: observation.title, author: observation.authorOrArtist)
        if HTMLSupport.isMeaningfulEntityName(observation.normalizedEntityName) {
            aliases.append(observation.normalizedEntityName)
        }

        var seen = Set<String>()
        return aliases.filter { alias in
            let normalized = HTMLSupport.normalizedAlias(alias)
            guard !normalized.isEmpty else { return false }
            return seen.insert(normalized).inserted
        }
    }

    private func preferredDisplayName(for observation: ObservationRecord, aliases: [String]) -> String {
        if let author = observation.authorOrArtist {
            let cleaned = HTMLSupport.cleanText(author)
            if HTMLSupport.isMeaningfulEntityName(cleaned) {
                return cleaned
            }
        }
        return aliases.first ?? HTMLSupport.cleanText(observation.title)
    }

    private func matchedEntity(
        exactKeys: Set<String>,
        relaxedKeys: Set<String>,
        preferredName: String,
        domain: CulturalDomain,
        entityType: EntityType,
        sourceID: String,
        sourceClassification: SourceClassification?,
        observedAt: Date,
        entitiesByID: [String: MutableCanonicalEntity],
        exactLookup: [String: Set<String>],
        relaxedLookup: [String: Set<String>]
    ) -> MergeDecision? {
        let exactMatches = Set(exactKeys.flatMap { exactLookup[$0] ?? [] }).filter {
            guard let entity = entitiesByID[$0] else { return false }
            return isCompatible(entity: entity, domain: domain, entityType: entityType)
        }

        let exactDecisions = exactMatches.compactMap { entityID -> MergeDecision? in
            guard let entity = entitiesByID[entityID] else { return nil }
            return mergeDecision(
                entity: entity,
                matchStrength: .exact,
                preferredName: preferredName,
                domain: domain,
                entityType: entityType,
                sourceID: sourceID,
                sourceClassification: sourceClassification,
                observedAt: observedAt
            )
        }

        if exactDecisions.count == 1 {
            return exactDecisions.first
        }

        guard exactMatches.isEmpty else { return nil }

        let relaxedMatches = Set(relaxedKeys.flatMap { relaxedLookup[$0] ?? [] }).filter {
            guard let entity = entitiesByID[$0] else { return false }
            return isCompatible(entity: entity, domain: domain, entityType: entityType)
        }

        let relaxedDecisions = relaxedMatches.compactMap { entityID -> MergeDecision? in
            guard let entity = entitiesByID[entityID] else { return nil }
            return mergeDecision(
                entity: entity,
                matchStrength: .relaxed,
                preferredName: preferredName,
                domain: domain,
                entityType: entityType,
                sourceID: sourceID,
                sourceClassification: sourceClassification,
                observedAt: observedAt
            )
        }

        if relaxedDecisions.count == 1 {
            return relaxedDecisions.first
        }

        return nil
    }

    private func isCompatible(
        entity: MutableCanonicalEntity,
        domain: CulturalDomain,
        entityType: EntityType
    ) -> Bool {
        let domainsCompatible =
            entity.domain == domain ||
            (entity.domain == .mixed && domain != .generalCulture) ||
            (domain == .mixed && entity.domain != .generalCulture) ||
            (entity.domain == .generalCulture && !HTMLSupport.isCommonCollisionAlias(entity.displayName)) ||
            (domain == .generalCulture && !HTMLSupport.isCommonCollisionAlias(entity.displayName))

        let typesCompatible =
            entity.entityType == entityType ||
            entity.entityType == .unknown ||
            entityType == .unknown

        return domainsCompatible && typesCompatible
    }

    private func mergeDecision(
        entity: MutableCanonicalEntity,
        matchStrength: MergeMatchStrength,
        preferredName: String,
        domain: CulturalDomain,
        entityType: EntityType,
        sourceID: String,
        sourceClassification: SourceClassification?,
        observedAt: Date
    ) -> MergeDecision? {
        let isShort = HTMLSupport.isShortAlias(preferredName)
        let isCommon = HTMLSupport.isCommonCollisionAlias(preferredName)
        let isTitleCollision = HTMLSupport.isPotentialTitleCollisionAlias(preferredName)
        let isRisky = isShort || isCommon || isTitleCollision
        let domainExact = entity.domain == domain
        let typeExact = entity.entityType == entityType
        let sameSource = entity.sourceIDs.contains(sourceID)
        let sameClassification = sourceClassification.map { entity.sourceClassifications.contains($0) } ?? false
        let multiSourceAgreement = entity.sourceIDs.count >= 2
        let gapDays = historicalGapDays(entity: entity, observedAt: observedAt)

        if matchStrength == .relaxed && isRisky {
            return nil
        }

        if isCommon && !sameSource && !sameClassification && !multiSourceAgreement {
            return nil
        }

        if gapDays > 365, matchStrength == .relaxed {
            return nil
        }

        if gapDays > 365, !sameSource, !sameClassification, !multiSourceAgreement {
            return nil
        }

        if gapDays > 365,
           !sameSource,
           !sameClassification,
           entity.sourceClassifications.count <= 1 {
            return nil
        }

        if gapDays > 1825, !sameSource {
            return nil
        }

        var confidence: Double = matchStrength == .exact ? 0.58 : 0.28
        var reasons: [String] = [matchStrength == .exact ? "exact alias match" : "relaxed alias match"]

        if domainExact {
            confidence += 0.16
            reasons.append("same domain")
        } else if entity.domain == .mixed || domain == .mixed || entity.domain == .generalCulture || domain == .generalCulture {
            confidence += 0.04
            reasons.append("compatible domain")
        } else {
            return nil
        }

        if typeExact {
            confidence += 0.12
            reasons.append("same entity type")
        } else if entity.entityType == .unknown || entityType == .unknown {
            confidence += 0.03
            reasons.append("compatible entity type")
        } else {
            return nil
        }

        if sameSource {
            confidence += 0.14
            reasons.append("same source")
        } else if sameClassification {
            confidence += 0.08
            reasons.append("same source role")
        }

        if multiSourceAgreement {
            confidence += 0.05
            reasons.append("existing source agreement")
        }

        if !isRisky {
            confidence += 0.08
        }

        if isShort {
            confidence -= 0.16
            reasons.append("short-name penalty")
        }
        if isCommon {
            confidence -= 0.18
            reasons.append("common-name penalty")
        }
        if isTitleCollision {
            confidence -= 0.18
            reasons.append("title-collision penalty")
        }

        if gapDays > 180 {
            confidence -= 0.08
            reasons.append("historical gap \(Int(gapDays))d")
        }
        if gapDays > 365 {
            confidence -= 0.12
        }
        if gapDays > 1825 {
            confidence -= 0.16
        }

        let threshold = matchStrength == .exact ? 0.72 : 0.82
        guard confidence >= threshold else { return nil }

        let summary = "Merge confidence \(formatted(confidence)). Accepted on \(reasons.joined(separator: ", "))."
        return MergeDecision(
            entityID: entity.id,
            confidence: min(1.0, max(0.0, confidence)),
            summary: summary
        )
    }

    private func historicalGapDays(entity: MutableCanonicalEntity, observedAt: Date) -> Double {
        if let lastSeenAt = entity.lastSeenAt {
            return max(0, observedAt.timeIntervalSince(lastSeenAt) / 86_400)
        }
        if let firstSeenAt = entity.firstSeenAt {
            return max(0, observedAt.timeIntervalSince(firstSeenAt) / 86_400)
        }
        return 0
    }

    private func canonicalID(
        domain: CulturalDomain,
        entityType: EntityType,
        preferredName: String,
        fallback: String
    ) -> String {
        let key = HTMLSupport.relaxedAliasKey(preferredName)
        let finalKey = key.isEmpty ? HTMLSupport.relaxedAliasKey(fallback) : key
        return "\(domain.rawValue)::\(entityType.rawValue)::\(finalKey)"
    }

    private func betterDisplayName(current: String, candidate: String) -> String {
        if displayScore(candidate) > displayScore(current) {
            return candidate
        }
        return current
    }

    private func displayScore(_ value: String) -> Int {
        let cleaned = HTMLSupport.cleanText(value)
        let hasUppercase = cleaned.contains(where: \.isUppercase)
        let meaningful = HTMLSupport.isMeaningfulEntityName(cleaned)
        return (meaningful ? 10 : 0) + (hasUppercase ? 4 : 0) + min(cleaned.count, 20)
    }

    private func uniqueAliasRecords(
        canonicalEntityID: String,
        sightings: [AliasSighting]
    ) -> [EntityAliasRecord] {
        var seen = Set<String>()
        return sightings.compactMap { sighting in
            let key = "\(sighting.normalized)::\(sighting.sourceID ?? "")"
            guard seen.insert(key).inserted else { return nil }
            return EntityAliasRecord(
                id: "\(canonicalEntityID)::\(sighting.normalized)::\(sighting.sourceID ?? "global")",
                canonicalEntityID: canonicalEntityID,
                aliasText: sighting.text,
                normalizedAlias: sighting.normalized,
                sourceID: sighting.sourceID
            )
        }
    }

    private func isEligibleSignalName(_ value: String) -> Bool {
        guard HTMLSupport.isMeaningfulEntityName(value) else { return false }

        let blockedPrefixes = [
            "the aquarium drunkard show",
            "radio free aquarium drunkard",
            "upcoming show"
        ]

        let normalized = HTMLSupport.normalizedAlias(value)
        return !blockedPrefixes.contains(where: { normalized.hasPrefix($0) })
    }

    private func sourceFamilyKey(
        for sourceID: String,
        sourcesByID: [String: SourceRecord]
    ) -> String {
        guard let source = sourcesByID[sourceID] else { return sourceID }
        if !source.sourceFamilyID.isEmpty {
            return source.sourceFamilyID
        }
        guard let host = URL(string: source.baseURL)?.host?.lowercased(), !host.isEmpty else {
            return sourceID
        }
        return host
    }

    private func dominantDomain(in observations: [ObservationRecord]) -> CulturalDomain {
        mode(of: observations.map(\.domain)) ?? .generalCulture
    }

    private func observationDate(_ observation: ObservationRecord) -> Date {
        observation.publishedAt ?? observation.scrapedAt
    }

    private func dedupedHistoryObservations(_ observations: [ObservationRecord]) -> [ObservationRecord] {
        guard observations.contains(where: isEventLikeObservation) else {
            return observations
        }

        var chosenByKey: [String: ObservationRecord] = [:]
        for observation in observations {
            let key = historyInstanceKey(for: observation)
            if let existing = chosenByKey[key] {
                if observationDate(observation) > observationDate(existing) {
                    chosenByKey[key] = observation
                }
            } else {
                chosenByKey[key] = observation
            }
        }
        return Array(chosenByKey.values)
    }

    private func isEventLikeObservation(_ observation: ObservationRecord) -> Bool {
        observation.entityType == .event
            || observation.entityType == .eventSeries
            || observation.tags.contains("event")
            || observation.tags.contains("venue-calendar")
    }

    private func historyInstanceKey(for observation: ObservationRecord) -> String {
        guard isEventLikeObservation(observation) else {
            return observation.id
        }

        return observation.eventInstanceKey ?? observation.id
    }

    private func progressionIntelligence(
        canonicalName: String,
        sourceRoles: [EntitySourceRoleRecord],
        sourcesByID: [String: SourceRecord]
    ) -> ProgressionIntelligence {
        let orderedRoles = sourceRoles.sorted { lhs, rhs in
            if lhs.firstSeenAt == rhs.firstSeenAt {
                return lhs.sourceID < rhs.sourceID
            }
            return lhs.firstSeenAt < rhs.firstSeenAt
        }

        var stages: [SourceClassification] = []
        var firstRolePerStage: [SourceClassification: EntitySourceRoleRecord] = [:]
        for role in orderedRoles where firstRolePerStage[role.sourceClassification] == nil {
            firstRolePerStage[role.sourceClassification] = role
            stages.append(role.sourceClassification)
        }

        guard let firstStage = stages.first, let firstRole = firstRolePerStage[firstStage] else {
            return ProgressionIntelligence(
                score: 0,
                stages: [],
                pattern: "",
                summary: "No clear progression pattern yet."
            )
        }

        let pattern = stages.map(\.label).joined(separator: " -> ")
        let stagePairs = zip(stages, stages.dropFirst()).compactMap { lhs, rhs -> StageTransition? in
            guard let fromRole = firstRolePerStage[lhs], let toRole = firstRolePerStage[rhs] else { return nil }
            let seconds = max(0, toRole.firstSeenAt.timeIntervalSince(fromRole.firstSeenAt))
            return StageTransition(from: lhs, to: rhs, gapDays: seconds / 86_400)
        }

        let patternBonus = progressionPatternBonus(for: stages)
        let transitionBonus = Double(stagePairs.count) * 0.9
        let timeGapBonus = stagePairs.reduce(0.0) { partial, transition in
            partial + timeGapScore(days: transition.gapDays)
        }
        let score = patternBonus + transitionBonus + timeGapBonus

        let firstSourceName = sourcesByID[firstRole.sourceID]?.name ?? firstRole.sourceID
        let summary: String
        if let nextStage = stages.dropFirst().first,
           let nextRole = firstRolePerStage[nextStage] {
            let nextSourceName = sourcesByID[nextRole.sourceID]?.name ?? nextRole.sourceID
            let gapDays = max(0, nextRole.firstSeenAt.timeIntervalSince(firstRole.firstSeenAt) / 86_400)
            summary = "Started in \(firstStage.label.lowercased()) via \(firstSourceName), then appeared in \(nextStage.label.lowercased()) via \(nextSourceName) \(formattedGap(days: gapDays)) later. Pattern: \(pattern)."
        } else {
            summary = "Started in \(firstStage.label.lowercased()) via \(firstSourceName). Pattern so far: \(firstStage.label)."
        }

        return ProgressionIntelligence(
            score: score,
            stages: stages,
            pattern: pattern,
            summary: summary
        )
    }

    private func horizonIntelligence(
        displayName: String,
        stageSnapshots: [EntityStageSnapshotRecord],
        progression: ProgressionIntelligence,
        latestSeen: Date,
        now: Date
    ) -> HorizonIntelligence {
        let sevenDayCutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let thirtyDayCutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let ninetyDayCutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now

        let last7 = stageSnapshots.filter { $0.date >= sevenDayCutoff }
        let last30 = stageSnapshots.filter { $0.date >= thirtyDayCutoff }
        let last90 = stageSnapshots.filter { $0.date >= ninetyDayCutoff }

        let score7 = last7.reduce(0.0) { $0 + $1.signalScore }
        let score30 = last30.reduce(0.0) { $0 + $1.signalScore }
        let score90 = last90.reduce(0.0) { $0 + $1.signalScore }
        let stageCount = Set(last90.map(\.stage)).count
        let latestStage = highestStage(in: last30.map(\.stage)) ?? highestStage(in: last90.map(\.stage))
        let daysSinceLatest = max(0, now.timeIntervalSince(latestSeen) / 86_400)

        let maturity: SignalMaturity
        if daysSinceLatest > 30 {
            maturity = .cooling
        } else if stageCount <= 1 && latestStage == .discovery && (last90.count >= 4 || score30 > 6) {
            maturity = .stalled
        } else if latestStage == .commercialScaling || latestStage == .institutional || score7 >= max(6, score30 * 0.45) {
            maturity = .peaking
        } else if latestStage != nil && stageCount >= 2 && progression.stages.count >= 2 {
            maturity = .advancing
        } else {
            maturity = .earlyEmergence
        }

        let bonus: Double = {
            switch maturity {
            case .earlyEmergence: return 0.8
            case .advancing: return 2.1
            case .peaking: return 1.2
            case .cooling: return -1.1
            case .stalled: return -1.6
            }
        }()

        let summary = "7d \(formatted(score7)) • 30d \(formatted(score30)) • 90d \(formatted(score90)). \(maturityNarrative(maturity, progression: progression, daysSinceLatest: daysSinceLatest))"

        return HorizonIntelligence(
            maturity: maturity,
            bonus: bonus,
            summary: summary
        )
    }

    private func maturityNarrative(
        _ maturity: SignalMaturity,
        progression: ProgressionIntelligence,
        daysSinceLatest: Double
    ) -> String {
        switch maturity {
        case .earlyEmergence:
            return "Still early, with a short history and limited stage spread."
        case .advancing:
            return "Advancing through multiple cultural layers with visible follow-through."
        case .peaking:
            return "Peaking on sustained recent activity and broader stage reach."
        case .cooling:
            return "Cooling after stronger earlier activity; the recent curve is softer."
        case .stalled:
            return progression.stages.first == .discovery
                ? "Stalled in discovery without clear progression into the next layer."
                : "Stalled after early movement, with no fresh stage progression."
        }
    }

    private func classifyLifecycle(
        for signal: RawSignal,
        previous: SignalRunRecord?,
        runHistory: [SignalRunRecord],
        movement: SignalMovement
    ) -> LifecycleIntelligence {
        let history = runHistory.sorted { $0.runAt > $1.runAt }
        let priorScores = history.prefix(3).map(\.score)
        let averagePriorScore = priorScores.isEmpty ? signal.emergenceScore : priorScores.reduce(0, +) / Double(priorScores.count)
        let scoreDelta = previous.map { signal.emergenceScore - $0.score } ?? signal.emergenceScore
        let discoveryOnly = signal.progressionStages == [.discovery] || signal.progressionPattern == SourceClassification.discovery.label

        if discoveryOnly && (signal.maturity == .stalled || movement == .declining) && history.count >= 2 {
            return LifecycleIntelligence(
                state: .failed,
                summary: "Failed to progress after discovery. The entity stayed in discovery without a convincing next-stage move and the signal weakened instead of spreading."
            )
        }

        if movement == .declining || signal.maturity == .cooling {
            let decay = decayDescriptor(currentScore: signal.emergenceScore, previousScore: previous?.score, history: history)
            return LifecycleIntelligence(
                state: .cooling,
                summary: "\(decay) The entity is losing momentum after earlier support."
            )
        }

        if signal.maturity == .peaking && signal.emergenceScore >= averagePriorScore {
            return LifecycleIntelligence(
                state: .peaked,
                summary: "At or near peak visibility in the current observation window, with broader support than its earlier runs."
            )
        }

        if signal.maturity == .advancing || signal.progressionStages.count >= 2 {
            return LifecycleIntelligence(
                state: .advancing,
                summary: "Advancing through the system with evidence of progression beyond its initial source layer."
            )
        }

        if scoreDelta > 0 || movement == .new || movement == .rising {
            return LifecycleIntelligence(
                state: .emerging,
                summary: "Still emerging, with momentum building but the full lifecycle not written yet."
            )
        }

        return LifecycleIntelligence(
            state: .emerging,
            summary: "Emergence is still tentative, with enough support to watch but not enough to call a later lifecycle stage."
        )
    }

    private func classifyConversion(
        for signal: RawSignal,
        lifecycle: LifecycleIntelligence,
        outcomeConfirmations: [OutcomeConfirmationRecord],
        runHistory: [SignalRunRecord]
    ) -> ConversionIntelligence {
        let tiers = outcomeConfirmations
            .map(\.outcomeTier)
            .sorted { $0.rawValue < $1.rawValue }

        if !tiers.isEmpty {
            let labels = tiers.map(\.label).joined(separator: ", ")
            return ConversionIntelligence(
                state: .converted,
                outcomeTiers: tiers,
                summary: "Converted into downstream relevance via \(labels)."
            )
        }

        let historyDepth = runHistory.count
        if lifecycle.state == .failed || lifecycle.state == .disappeared {
            return ConversionIntelligence(
                state: .neverConverted,
                outcomeTiers: [],
                summary: "No downstream confirmation arrived before the signal faded out."
            )
        }

        if signal.maturity == .stalled || lifecycle.state == .cooling || historyDepth >= 2 {
            return ConversionIntelligence(
                state: .stalledBeforeConversion,
                outcomeTiers: [],
                summary: "Still lacks downstream confirmation and is stalling before a stronger conversion signal."
            )
        }

        return ConversionIntelligence(
            state: .pending,
            outcomeTiers: [],
            summary: "Too early to call conversion. The signal has not yet reached a stronger downstream tier."
        )
    }

    private func synthesizeAbsentSignals(
        activeCanonicalEntityIDs: Set<String>,
        runHistoryByName: [String: [SignalRunRecord]],
        now: Date
    ) -> [SignalCandidateRecord] {
        runHistoryByName.compactMap { key, history -> SignalCandidateRecord? in
            guard let previous = history.sorted(by: { $0.runAt > $1.runAt }).first else { return nil }
            let canonicalID = previous.canonicalEntityID.isEmpty ? key : previous.canonicalEntityID
            guard !activeCanonicalEntityIDs.contains(canonicalID) else { return nil }

            let daysSincePrevious = max(0, now.timeIntervalSince(previous.runAt) / 86_400)
            guard daysSincePrevious <= 45 else { return nil }

            let progressionStages = stages(from: previous.progressionPattern)
            let discoveryOnly = progressionStages == [.discovery] || previous.progressionPattern == SourceClassification.discovery.label
            let state: SignalLifecycleState = discoveryOnly ? .failed : .disappeared
            let maturity: SignalMaturity = discoveryOnly ? .stalled : .cooling
            let decayedScore = decayedMissingScore(previous.score, daysSincePrevious: daysSincePrevious)
            let summary: String = {
                if state == .failed {
                    return "Failed progression. It first surfaced in discovery, never built a stronger pathway, and now has no supporting sources in the current run."
                }
                return "Disappeared from the current run after previously showing support across \(previous.sourceCount) sources. All supporting sources fell away this pass."
            }()

            return SignalCandidateRecord(
                id: UUID().uuidString,
                canonicalEntityID: canonicalID,
                domain: previous.domain,
                canonicalName: previous.canonicalName,
                entityType: previous.entityType,
                firstSeenAt: previous.runAt,
                latestSeenAt: previous.runAt,
                sourceCount: 0,
                observationCount: 0,
                currentSourceCount: 0,
                currentSourceFamilyCount: 0,
                currentObservationCount: 0,
                historicalSourceCount: previous.historicalSourceCount,
                historicalObservationCount: previous.historicalObservationCount,
                growthScore: 0,
                diversityScore: 0,
                repeatAppearanceScore: 0,
                progressionScore: 0,
                saturationScore: 0,
                emergenceScore: decayedScore,
                confidence: max(0.2, min(0.75, previous.score / 20)),
                movement: .declining,
                maturity: maturity,
                lifecycleState: state,
                conversionState: previous.conversionState == .converted ? .converted : .neverConverted,
                outcomeTiers: previous.outcomeTiers,
                supportingSourceIDs: [],
                progressionStages: progressionStages,
                progressionPattern: previous.progressionPattern,
                movementSummary: disappearanceMovementSummary(previous: previous, daysSincePrevious: daysSincePrevious),
                maturitySummary: disappearanceMaturitySummary(state: state, daysSincePrevious: daysSincePrevious),
                lifecycleSummary: summary,
                conversionSummary: previous.conversionState == .converted
                    ? "Previously converted before dropping out of the current run."
                    : "Dropped out without recording a stronger downstream conversion.",
                pathwaySummary: "No new pathway evidence this run. Last known route was \(previous.progressionPattern.isEmpty ? "unclassified" : previous.progressionPattern).",
                sourceInfluenceSummary: previous.sourceInfluenceSummary.isEmpty
                    ? "No learned source influence summary was recorded before the signal dropped out."
                    : previous.sourceInfluenceSummary,
                progressionSummary: previous.progressionPattern.isEmpty
                    ? "No durable progression path was recorded before the signal dropped out."
                    : "Last known progression pattern: \(previous.progressionPattern).",
                evidenceSummary: "No current support. Last seen \(formattedGap(days: max(1, daysSincePrevious))) ago with \(previous.sourceCount) supporting sources."
            )
        }
    }

    private func disappearanceMovementSummary(previous: SignalRunRecord, daysSincePrevious: Double) -> String {
        "Dropped out after previously scoring \(formatted(previous.score)) across \(previous.sourceCount) sources. No supporting sources remained \(formattedGap(days: max(1, daysSincePrevious))) later."
    }

    private func disappearanceMaturitySummary(state: SignalLifecycleState, daysSincePrevious: Double) -> String {
        switch state {
        case .failed:
            return "No longer active after an early-stage run that never converted into broader progression."
        case .disappeared:
            return "The signal fell out of the current observation window after \(formattedGap(days: max(1, daysSincePrevious))) without refreshed support."
        default:
            return "The signal is no longer active in the current window."
        }
    }

    private func decayedMissingScore(_ previousScore: Double, daysSincePrevious: Double) -> Double {
        let multiplier: Double
        switch daysSincePrevious {
        case ..<3: multiplier = 0.65
        case 3..<10: multiplier = 0.45
        case 10..<21: multiplier = 0.3
        default: multiplier = 0.18
        }
        return max(0.5, previousScore * multiplier)
    }

    private func decayDescriptor(
        currentScore: Double,
        previousScore: Double?,
        history: [SignalRunRecord]
    ) -> String {
        guard let previousScore else {
            return "Momentum softened without building on its previous support."
        }

        let delta = currentScore - previousScore
        if delta <= -4 || currentScore <= previousScore * 0.55 {
            return "Sharp drop."
        }

        if history.count >= 2 {
            let secondPrevious = history[1].score
            if previousScore < secondPrevious && currentScore < previousScore {
                return "Slow fade across multiple runs."
            }
        }

        return delta < 0 ? "Slow fade." : "Momentum cooled after an earlier push."
    }

    private func stages(from progressionPattern: String) -> [SourceClassification] {
        progressionPattern
            .split(separator: ">")
            .map { $0.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { component in
                let normalized = component.replacingOccurrences(of: " ", with: "").lowercased()
                return SourceClassification.allCases.first {
                    $0.label.replacingOccurrences(of: " ", with: "").lowercased() == normalized
                }
            }
    }

    private func pathwayKey(pattern: String, domain: CulturalDomain) -> String {
        "\(domain.rawValue)::\(pattern)"
    }

    private func sourceInfluenceKey(scope: SourceInfluenceScope, scopeKey: String, domain: CulturalDomain) -> String {
        "\(scope.rawValue)::\(scopeKey)::\(domain.rawValue)"
    }

    private func deduplicatedRuns(from runHistoryByName: [String: [SignalRunRecord]]) -> [SignalRunRecord] {
        var seen = Set<String>()
        return runHistoryByName.values
            .flatMap { $0 }
            .filter { seen.insert($0.id).inserted }
    }

    private func pathwaySummary(
        pattern: String,
        sampleCount: Int,
        advancingCount: Int,
        peakedCount: Int,
        coolingCount: Int,
        failedCount: Int,
        disappearedCount: Int,
        conversionCount: Int,
        stalledConversionCount: Int,
        neverConvertedCount: Int,
        predictiveScore: Double
    ) -> String {
        let successes = advancingCount + peakedCount
        let failures = failedCount + disappearedCount
        let conversions = conversionCount
        if predictiveScore >= 1.25 {
            return "Historically predictive pathway. \(pattern) has produced \(conversions) downstream conversions and \(successes) stronger lifecycle outcomes versus \(failures) failures across \(sampleCount) observed runs."
        }
        if predictiveScore <= -0.75 {
            return "Historically fragile pathway. \(pattern) has \(neverConvertedCount) never-converted outcomes and \(failures) failures, outweighing \(conversions) downstream conversions across \(sampleCount) observed runs."
        }
        if stalledConversionCount > conversions && stalledConversionCount >= 2 {
            return "Mixed pathway so far. \(pattern) often stalls before real downstream conversion, with \(stalledConversionCount) stalled outcomes across \(sampleCount) observed runs."
        }
        if coolingCount > successes && coolingCount >= 2 {
            return "Mixed pathway so far. \(pattern) often cools before converting, with \(coolingCount) cooling outcomes across \(sampleCount) observed runs."
        }
        return "Early pathway evidence. \(pattern) has \(sampleCount) observed runs, with \(conversions) downstream conversions, \(successes) stronger lifecycle outcomes, and \(failures) failures so far."
    }

    private func learnedInfluenceBonus(
        sourceStats: [SourceInfluenceStatRecord],
        familyStats: [SourceInfluenceStatRecord]
    ) -> Double {
        let sourceAverage = sourceStats.isEmpty ? 0 : sourceStats.map(\.predictiveScore).reduce(0, +) / Double(sourceStats.count)
        let familyAverage = familyStats.isEmpty ? 0 : familyStats.map(\.predictiveScore).reduce(0, +) / Double(familyStats.count)
        return max(-2.2, min(3.0, sourceAverage * 0.45 + familyAverage * 0.75))
    }

    private func sourceInfluenceNarrative(
        sourceStats: [SourceInfluenceStatRecord],
        familyStats: [SourceInfluenceStatRecord]
    ) -> String {
        let bestFamily = familyStats.max { $0.predictiveScore < $1.predictiveScore }
        let weakestFamily = familyStats.min { $0.predictiveScore < $1.predictiveScore }
        let bestSource = sourceStats.max { $0.predictiveScore < $1.predictiveScore }

        if let bestFamily, bestFamily.predictiveScore >= 1.0 {
            let sourceLead = bestSource?.displayName ?? bestFamily.displayName
            return "Historically stronger support. \(bestFamily.displayName) has been a predictive \(bestFamily.scope.label.lowercased()) for this domain, with \(bestFamily.conversionCount) downstream conversions across \(bestFamily.sampleCount) tracked runs. \(sourceLead) is helping this signal more than a neutral source would."
        }

        if let weakestFamily, weakestFamily.predictiveScore <= -0.7 {
            return "Historically fragile support. \(weakestFamily.displayName) has produced more stalled or failed outcomes than conversions so far, so Malcome is discounting this evidence rather than taking it at face value."
        }

        if let bestSource, bestSource.sampleCount >= 2 {
            return "Early source learning. \(bestSource.displayName) has shown \(bestSource.advancingCount + bestSource.peakedCount) stronger outcomes across \(bestSource.sampleCount) tracked runs, so it modestly informs this score without dominating it."
        }

        return "No strong learned source edge yet. Malcome is mostly relying on current corroboration and pathway evidence here."
    }

    private func sourceInfluenceSummary(
        displayName: String,
        scope: SourceInfluenceScope,
        sampleCount: Int,
        advancingCount: Int,
        peakedCount: Int,
        failedCount: Int,
        disappearedCount: Int,
        conversionCount: Int,
        neverConvertedCount: Int,
        predictiveScore: Double
    ) -> String {
        let strongerOutcomes = advancingCount + peakedCount
        let failures = failedCount + disappearedCount
        if predictiveScore >= 1.1 {
            return "Historically predictive \(scope.label.lowercased()). \(displayName) has contributed to \(conversionCount) downstream conversions and \(strongerOutcomes) stronger lifecycle outcomes across \(sampleCount) tracked runs."
        }
        if predictiveScore <= -0.75 {
            return "Historically noisy \(scope.label.lowercased()). \(displayName) has produced \(neverConvertedCount) never-converted outcomes and \(failures) failures across \(sampleCount) tracked runs."
        }
        return "Early source evidence. \(displayName) has \(sampleCount) tracked runs so far, with \(conversionCount) downstream conversions and \(failures) failures."
    }

    private func firstCrossDomainDate(in observations: [ObservationRecord]) -> Date? {
        var seen = Set<CulturalDomain>()
        for observation in observations.sorted(by: { observationDate($0) < observationDate($1) }) {
            let domain = observation.domain
            guard domain != .generalCulture else { continue }
            seen.insert(domain)
            if seen.count >= 2 {
                return observationDate(observation)
            }
        }
        return nil
    }

    private func progressionPatternBonus(for stages: [SourceClassification]) -> Double {
        let labels = stages
        let sequence = labels.map(\.rawValue)

        if containsOrderedSubsequence([.discovery, .editorial, .venue, .institutional], in: labels) {
            return 6.0
        }
        if containsOrderedSubsequence([.discovery, .editorial, .venue], in: labels) {
            return 4.6
        }
        if containsOrderedSubsequence([.discovery, .community, .venue], in: labels) {
            return 4.2
        }
        if containsOrderedSubsequence([.editorial, .venue, .institutional], in: labels) {
            return 4.0
        }
        if containsOrderedSubsequence([.discovery, .venue], in: labels) {
            return 3.0
        }
        if containsOrderedSubsequence([.discovery, .editorial], in: labels) {
            return 2.8
        }
        if containsOrderedSubsequence([.community, .venue], in: labels) {
            return 2.4
        }
        if containsOrderedSubsequence([.venue, .institutional], in: labels) {
            return 2.3
        }
        if sequence.count >= 2 {
            return 1.2
        }
        return 0
    }

    private func containsOrderedSubsequence(
        _ target: [SourceClassification],
        in sequence: [SourceClassification]
    ) -> Bool {
        guard !target.isEmpty else { return true }
        var index = 0
        for value in sequence where value == target[index] {
            index += 1
            if index == target.count {
                return true
            }
        }
        return false
    }

    private func timeGapScore(days: Double) -> Double {
        switch days {
        case ..<0.25:
            return 0.3
        case 0.25..<7:
            return 0.9
        case 7..<30:
            return 1.1
        case 30..<120:
            return 0.6
        default:
            return 0.1
        }
    }

    private func formattedGap(days: Double) -> String {
        if days < 1 {
            let hours = max(1, Int((days * 24).rounded()))
            return "\(hours)h"
        }
        return "\(Int(days.rounded()))d"
    }

    private func highestStage(in stages: [SourceClassification]) -> SourceClassification? {
        stages.max { stageRank($0) < stageRank($1) }
    }

    private func stageRank(_ classification: SourceClassification) -> Int {
        switch classification {
        case .discovery: return 1
        case .community: return 2
        case .editorial: return 3
        case .venue: return 4
        case .institutional: return 5
        case .commercialScaling: return 6
        }
    }

    private func classifyMovement(
        for signal: RawSignal,
        previous: SignalRunRecord?,
        rank: Int
    ) -> SignalMovement {
        guard let previous else { return .new }

        let scoreDelta = signal.emergenceScore - previous.score
        let rankDelta = previous.rank - rank
        let sourceDelta = signal.sourceCount - previous.sourceCount
        let observationDelta = signal.observationCount - previous.observationCount

        if scoreDelta >= 2.0 || rankDelta >= 2 || sourceDelta > 0 || observationDelta >= 2 {
            return .rising
        }
        if scoreDelta <= -2.0 || rankDelta <= -2 {
            return .declining
        }
        return .stable
    }

    private func buildMovementSummary(
        for signal: RawSignal,
        previous: SignalRunRecord?,
        movement: SignalMovement,
        rank: Int,
        sourcesByID: [String: SourceRecord]
    ) -> String {
        let sourceNames = signal.supportingSourceIDs.compactMap { sourcesByID[$0]?.name }
        let sourcePhrase = sourceNames.isEmpty ? "current sources" : sourceNames.joined(separator: ", ")
        let corroborationPhrase = signal.supportingSourceFamilyCount <= 1
            ? "Support is still concentrated in one source family."
            : "Support spans \(signal.supportingSourceFamilyCount) independent source families."

        switch movement {
        case .new:
            return "New this run. First corroborated with \(signal.observationCount) observations across \(signal.sourceCount) sources, led by \(sourcePhrase). \(corroborationPhrase)"
        case .rising:
            guard let previous else {
                return "Rising on stronger corroboration from \(sourcePhrase). \(corroborationPhrase)"
            }
            let rankChange = previous.rank - rank
            return "Rising because score moved from \(formatted(previous.score)) to \(formatted(signal.emergenceScore)), support now reaches \(signal.sourceCount) sources, and the main contributors were \(sourcePhrase)\(rankChange > 0 ? ". Rank improved by \(rankChange)." : ".") \(corroborationPhrase)"
        case .stable:
            guard let previous else {
                return "Stable on repeated corroboration from \(sourcePhrase). \(corroborationPhrase)"
            }
            return "Stable because score stayed near \(formatted(previous.score)) to \(formatted(signal.emergenceScore)) and support held across \(signal.sourceCount) sources, including \(sourcePhrase). \(corroborationPhrase)"
        case .declining:
            guard let previous else {
                return "Declining after weaker support this run. \(corroborationPhrase)"
            }
            return "Declining because score eased from \(formatted(previous.score)) to \(formatted(signal.emergenceScore)) and the current support is narrower, with \(sourcePhrase) carrying most of the evidence. \(corroborationPhrase)"
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func latestRuns(from historyByName: [String: [SignalRunRecord]]) -> [String: SignalRunRecord] {
        historyByName.compactMapValues { runs in
            runs.sorted { $0.runAt > $1.runAt }.first
        }
    }

    private func mode<T: Hashable>(of values: [T]) -> T? {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
        .max { $0.value < $1.value }?
        .key
    }
}

private struct CanonicalResolution: Sendable {
    let entities: [CanonicalEntityRecord]
    let aliases: [EntityAliasRecord]
    let sourceRoles: [EntitySourceRoleRecord]
    let observationMappings: [String: String]
    let groupedObservations: [String: [ObservationRecord]]
    let displayNameByID: [String: String]
}

private struct MutableCanonicalEntity: Sendable {
    let id: String
    var displayName: String
    let domain: CulturalDomain
    let entityType: EntityType
    var mergeConfidence: Double
    var mergeSummary: String
    var sourceIDs: Set<String> = []
    var sourceClassifications: Set<SourceClassification> = []
    var firstSeenAt: Date?
    var lastSeenAt: Date?
    var aliases: Set<String> = []
    var normalizedAliases: Set<String> = []
    var relaxedAliases: Set<String> = []
}

private enum MergeMatchStrength: Sendable {
    case exact
    case relaxed
}

private struct MergeDecision: Sendable {
    let entityID: String
    let confidence: Double
    let summary: String
}

private struct AliasSighting: Sendable {
    let text: String
    let normalized: String
    let sourceID: String?
}

private struct RawSignal: Sendable {
    let canonicalEntityID: String
    let domain: CulturalDomain
    let canonicalName: String
    let entityType: EntityType
    let firstSeenAt: Date
    let latestSeenAt: Date
    let sourceCount: Int
    let observationCount: Int
    let currentSourceCount: Int
    let currentSourceFamilyCount: Int
    let currentObservationCount: Int
    let growthScore: Double
    let diversityScore: Double
    let repeatAppearanceScore: Double
    let progressionScore: Double
    let saturationScore: Double
    let emergenceScore: Double
    let confidence: Double
    let maturity: SignalMaturity
    let supportingSourceIDs: [String]
    let supportingSourceFamilyCount: Int
    let progressionStages: [SourceClassification]
    let progressionPattern: String
    let maturitySummary: String
    let pathwaySummary: String
    let sourceInfluenceSummary: String
    let progressionSummary: String
    let evidenceSummary: String
}

private struct ProgressionIntelligence: Sendable {
    let score: Double
    let stages: [SourceClassification]
    let pattern: String
    let summary: String
}

private struct StageTransition: Sendable {
    let from: SourceClassification
    let to: SourceClassification
    let gapDays: Double
}

private struct HorizonIntelligence: Sendable {
    let maturity: SignalMaturity
    let bonus: Double
    let summary: String
}

private struct LifecycleIntelligence: Sendable {
    let state: SignalLifecycleState
    let summary: String
}

private struct ConversionIntelligence: Sendable {
    let state: ConversionState
    let outcomeTiers: [DownstreamOutcomeTier]
    let summary: String
}
