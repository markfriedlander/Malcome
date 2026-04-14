import Foundation

/// Synthetic test harness for evaluating DraftComposer voice quality across diverse scenarios.
/// Uses real entity names with synthetic signal metadata and template-generated excerpts.
enum SyntheticHarness {

    // MARK: - Output Types

    struct ScenarioOutput: Codable {
        let scenarioID: String
        let description: String
        let title: String
        let briefBody: String
        let citationCount: Int
        let tokenEstimate: Int
        let generationSeconds: Double
        let wikipediaResolved: Bool
        let excerptSource: String
    }

    struct HarnessReport: Codable {
        let runAt: String
        let totalScenarios: Int
        let completedScenarios: Int
        let failedScenarios: Int
        let outputs: [ScenarioOutput]
    }

    // MARK: - Entity Pool

    private static let entities: [(name: String, domain: CulturalDomain, type: EntityType)] = [
        ("Thundercat", .music, .creator),
        ("Kim Gordon", .music, .creator),
        ("TV Girl", .music, .creator),
        ("Damaged Bug", .music, .creator),
        ("Lala Lala", .music, .creator),
        ("Flying Lotus", .music, .creator),
        ("Earl Sweatshirt", .music, .creator),
        ("Bill Orcutt", .music, .creator),
        ("Darkthrone", .music, .creator),
        ("Xylitol", .music, .creator),
    ]

    // MARK: - Source Pool

    private static let sourcePool: [(name: String, city: String, family: String)] = [
        ("Bandcamp Daily", "Global", "Bandcamp"),
        ("Bandcamp LA Discover", "Los Angeles", "Bandcamp"),
        ("The Quietus", "London", "thequietus.com"),
        ("Aquarium Drunkard", "Los Angeles", "aquariumdrunkard.com"),
        ("Crack Magazine", "London", "crackmagazine.net"),
        ("BrooklynVegan", "New York City", "brooklynvegan.com"),
        ("KXLU", "Los Angeles", "kxlu.com"),
        ("Artforum", "New York City", "artforum.com"),
        ("Film Comment", "New York City", "filmcomment.com"),
        ("Hyperallergic", "New York City", "hyperallergic.com"),
    ]

    // MARK: - Excerpt Templates

    private static let cleanExcerpts: [String] = [
        "A new collaboration that bridges the gap between experimental production and visceral live energy.",
        "The latest release builds on a decade of genre-defying work, pushing further into uncharted sonic territory.",
        "An artist who has been quietly reshaping their corner of the scene is finally getting the wider attention the work deserves.",
        "This is the kind of cross-pollination that produces something genuinely new rather than a predictable blend.",
        "A return to form that suggests the creative well is deeper than the commercial narrative implied.",
    ]

    private static let garbledExcerpts: [String] = [
        "Rabbot Ho • Los Angeles, California",
        "ThunderWave (feat. WILLOW) • Los Angeles, California",
        "New Arrivals From HBX • Hypebeast Staff",
    ]

    // MARK: - Scenario Generation

    static func allScenarios() -> [SyntheticScenario] {
        var scenarios: [SyntheticScenario] = []

        // Single signal (s01-s10)
        scenarios.append(scenario("s01", "1 signal, rising, music, strong (3 families), clean excerpt",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0])]))
        scenarios.append(scenario("s02", "1 signal, new, music, medium (2 families), no wiki entity",
            signals: [signal(entities[4], .new, .current, families: 2, excerpt: cleanExcerpts[1])]))
        scenarios.append(scenario("s03", "1 signal, stable, music, weak (2 families), garbled excerpt",
            signals: [signal(entities[3], .stable, .current, families: 2, excerpt: garbledExcerpts[0])]))
        scenarios.append(scenario("s04", "1 signal, declining, music, strong, clean excerpt",
            signals: [signal(entities[6], .declining, .current, families: 3, excerpt: cleanExcerpts[2])]))
        scenarios.append(scenario("s05", "1 signal, rising, music, historical tier",
            signals: [signal(entities[0], .rising, .historical, families: 2, excerpt: cleanExcerpts[3])]))
        scenarios.append(scenario("s06", "1 signal, new, no excerpt, no wiki",
            signals: [signal(entities[9], .new, .current, families: 2, excerpt: nil)]))
        scenarios.append(scenario("s07", "1 signal, stable, cross-city LA+London, clean excerpt",
            signals: [signal(entities[0], .stable, .current, families: 2, excerpt: cleanExcerpts[4],
                             sources: [sourcePool[3], sourcePool[2]])]))
        scenarios.append(scenario("s08", "1 signal, rising, same city, garbled excerpt",
            signals: [signal(entities[2], .rising, .current, families: 2, excerpt: garbledExcerpts[1],
                             sources: [sourcePool[0], sourcePool[1]])]))
        scenarios.append(scenario("s09", "1 signal + 2 watchlist",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0])],
            watchlist: [watch(entities[4], .corroborating), watch(entities[9], .early)]))
        scenarios.append(scenario("s10", "1 signal + full watchlist (4 items)",
            signals: [signal(entities[5], .new, .current, families: 2, excerpt: cleanExcerpts[1])],
            watchlist: [watch(entities[4], .corroborating), watch(entities[3], .forming),
                       watch(entities[9], .early), watch(entities[7], .early)]))

        // Multi-signal (s11-s20)
        scenarios.append(scenario("s11", "2 signals, both rising, music only",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0]),
                     signal(entities[1], .rising, .current, families: 2, excerpt: cleanExcerpts[1])]))
        scenarios.append(scenario("s12", "2 signals, mixed movement (rising + declining)",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0]),
                     signal(entities[6], .declining, .current, families: 2, excerpt: cleanExcerpts[2])]))
        scenarios.append(scenario("s13", "3 signals, all current tier, music",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0]),
                     signal(entities[1], .stable, .current, families: 2, excerpt: cleanExcerpts[1]),
                     signal(entities[5], .new, .current, families: 2, excerpt: cleanExcerpts[3])]))
        scenarios.append(scenario("s14", "3 signals, mixed tier (2 current + 1 historical)",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0]),
                     signal(entities[1], .stable, .current, families: 2, excerpt: cleanExcerpts[1]),
                     signal(entities[3], .rising, .historical, families: 2, excerpt: cleanExcerpts[4])]))
        scenarios.append(scenario("s15", "2 signals, cross-city LA+London",
            signals: [signal(entities[0], .rising, .current, families: 2, excerpt: cleanExcerpts[0],
                             sources: [sourcePool[3], sourcePool[2]]),
                     signal(entities[8], .new, .current, families: 2, excerpt: cleanExcerpts[3],
                             sources: [sourcePool[4], sourcePool[5]])]))
        scenarios.append(scenario("s16", "2 signals + 3 watchlist",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0]),
                     signal(entities[1], .stable, .current, families: 2, excerpt: cleanExcerpts[1])],
            watchlist: [watch(entities[4], .corroborating), watch(entities[3], .forming), watch(entities[9], .early)]))
        scenarios.append(scenario("s17", "3 signals with varying excerpt quality",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0]),
                     signal(entities[3], .stable, .current, families: 2, excerpt: garbledExcerpts[0]),
                     signal(entities[9], .new, .current, families: 2, excerpt: nil)]))
        scenarios.append(scenario("s18", "2 signals with varying Wikipedia (rich, absent)",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0]),
                     signal(entities[9], .new, .current, families: 2, excerpt: cleanExcerpts[1])]))
        scenarios.append(scenario("s19", "4 signals maximum",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0]),
                     signal(entities[1], .stable, .current, families: 2, excerpt: cleanExcerpts[1]),
                     signal(entities[5], .new, .current, families: 2, excerpt: cleanExcerpts[3]),
                     signal(entities[6], .declining, .current, families: 2, excerpt: cleanExcerpts[2])]))
        scenarios.append(scenario("s20", "2 signals, one with no excerpt at all",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0]),
                     signal(entities[4], .new, .current, families: 2, excerpt: nil)]))

        // Watchlist only (s21-s25)
        scenarios.append(scenario("s21", "0 signals, 3 watchlist all corroborating",
            watchlist: [watch(entities[0], .corroborating), watch(entities[1], .corroborating), watch(entities[5], .corroborating)]))
        scenarios.append(scenario("s22", "0 signals, 2 watchlist (forming + early)",
            watchlist: [watch(entities[3], .forming), watch(entities[9], .early)]))
        scenarios.append(scenario("s23", "0 signals, 4 watchlist mixed stages",
            watchlist: [watch(entities[0], .corroborating), watch(entities[1], .forming),
                       watch(entities[4], .early), watch(entities[9], .early)]))
        scenarios.append(scenario("s24", "0 signals, 1 watchlist only",
            watchlist: [watch(entities[2], .early)]))
        scenarios.append(scenario("s25", "0 signals, 0 watchlist — empty state"))

        // Empty/thin states (s26-s30)
        scenarios.append(scenario("s26", "Empty state level 1 — sparse data"))
        scenarios.append(scenario("s27", "Empty state level 2 — data exists no threshold"))
        scenarios.append(scenario("s28", "Empty state level 3 — near-misses close"))
        scenarios.append(scenario("s29", "1 signal single-family (should show but limited)",
            signals: [signal(entities[0], .rising, .current, families: 1, excerpt: cleanExcerpts[0])]))
        scenarios.append(scenario("s30", "All signals historical tier only",
            signals: [signal(entities[0], .rising, .historical, families: 2, excerpt: cleanExcerpts[0]),
                     signal(entities[1], .stable, .historical, families: 2, excerpt: cleanExcerpts[1])]))

        // Edge cases (s31-s40)
        scenarios.append(scenario("s31", "Entity with credit-string name",
            signals: [signal(("Earl Sweatshirt, MIKE & SURF GANG", .music, .creator), .new, .current, families: 2, excerpt: cleanExcerpts[0])]))
        scenarios.append(scenario("s32", "Entity with very long name",
            signals: [signal(("Tour News: Pixies, Coheed & Cambria, Hatebreed, New Pornographers", .music, .creator), .stable, .current, families: 2, excerpt: cleanExcerpts[1])]))
        scenarios.append(scenario("s33", "All sources same city LA",
            signals: [signal(entities[0], .rising, .current, families: 2, excerpt: cleanExcerpts[0],
                             sources: [sourcePool[1], sourcePool[3]])]))
        scenarios.append(scenario("s34", "Garbled Bandcamp metadata excerpt only",
            signals: [signal(entities[3], .rising, .current, families: 2, excerpt: garbledExcerpts[2])]))
        scenarios.append(scenario("s35", "Rich Wikipedia but no excerpt",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: nil)]))
        scenarios.append(scenario("s36", "Collective entity type",
            signals: [signal(("Tortoise", .music, .collective), .rising, .current, families: 2, excerpt: cleanExcerpts[3])]))
        scenarios.append(scenario("s37", "Venue entity type",
            signals: [signal(("The Smell", .music, .venue), .stable, .current, families: 2, excerpt: cleanExcerpts[4])]))
        scenarios.append(scenario("s38", "Event entity type",
            signals: [signal(("Coachella 2026", .music, .event), .new, .current, families: 3, excerpt: cleanExcerpts[0])]))
        scenarios.append(scenario("s39", "Scene entity type",
            signals: [signal(("LA Beat Scene", .music, .scene), .rising, .current, families: 2, excerpt: cleanExcerpts[3])]))
        scenarios.append(scenario("s40", "Film domain signal",
            signals: [signal(("Sean Baker", .film, .creator), .rising, .current, families: 2, excerpt: "Baker's latest is a raw, empathetic portrait of survival on the margins of American life.")]))

        // Sentiment variations (s41-s50)
        scenarios.append(scenario("s41", "Strong positive — clear momentum",
            signals: [signal(entities[0], .rising, .current, families: 4, excerpt: cleanExcerpts[0])]))
        scenarios.append(scenario("s42", "Skeptical — declining + thin support",
            signals: [signal(entities[6], .declining, .current, families: 2, excerpt: cleanExcerpts[2])]))
        scenarios.append(scenario("s43", "Neutral — multiple signals no clear leader",
            signals: [signal(entities[0], .stable, .current, families: 2, excerpt: cleanExcerpts[0]),
                     signal(entities[1], .stable, .current, families: 2, excerpt: cleanExcerpts[1])]))
        scenarios.append(scenario("s44", "Mixed — 1 rising + 1 declining",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0]),
                     signal(entities[6], .declining, .current, families: 2, excerpt: cleanExcerpts[2])]))
        scenarios.append(scenario("s45", "Completely new — no history",
            signals: [signal(entities[9], .new, .current, families: 2, excerpt: nil)]))
        scenarios.append(scenario("s46", "Strong historical, quiet current",
            signals: [signal(entities[0], .stable, .historical, families: 3, excerpt: cleanExcerpts[4])]))
        scenarios.append(scenario("s47", "Cross-city agreement LA+London (strongest positive)",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0],
                             sources: [sourcePool[3], sourcePool[2], sourcePool[4]])]))
        scenarios.append(scenario("s48", "Single-family near-miss",
            signals: [signal(entities[0], .rising, .current, families: 1, excerpt: cleanExcerpts[0])]))
        scenarios.append(scenario("s49", "Large watchlist no signals — anticipation",
            watchlist: [watch(entities[0], .corroborating), watch(entities[1], .corroborating),
                       watch(entities[5], .forming), watch(entities[4], .early)]))
        scenarios.append(scenario("s50", "Maximum data — 3 signals, 4 watchlist, mixed tiers",
            signals: [signal(entities[0], .rising, .current, families: 3, excerpt: cleanExcerpts[0]),
                     signal(entities[1], .stable, .current, families: 2, excerpt: cleanExcerpts[1]),
                     signal(entities[8], .new, .historical, families: 2, excerpt: cleanExcerpts[3])],
            watchlist: [watch(entities[4], .corroborating), watch(entities[3], .forming),
                       watch(entities[9], .early), watch(entities[7], .early)]))

        return scenarios
    }

    // MARK: - Run

    static func run() async -> HarnessReport {
        let scenarios = allScenarios()
        var outputs: [ScenarioOutput] = []
        var failedCount = 0

        for scenario in scenarios {
            let start = Date()
            do {
                let input = scenario.toBriefingInput()
                let generator = MalcomeBriefGenerator()
                let brief = try await generator.generateBrief(from: input)
                let elapsed = Date().timeIntervalSince(start)

                let wikiResolved = !brief.body.contains("Something is happening — I do not have the full picture")
                    && !brief.body.contains("is the one right now.") // bare name = no wiki
                    && brief.body.contains(" — ") // appositive structure = wiki resolved

                let excerptSource: String
                if brief.body.contains("Something is happening — I do not have the full picture") {
                    excerptSource = "none"
                } else if scenario.signals.first?.excerpt == nil {
                    excerptSource = brief.body.contains("Something is happening") ? "none" : "fallback"
                } else if scenario.signals.first?.excerpt?.contains("•") == true || scenario.signals.first?.excerpt?.contains("Los Angeles, California") == true {
                    excerptSource = "bandcamp_metadata"
                } else {
                    excerptSource = "editorial"
                }

                outputs.append(ScenarioOutput(
                    scenarioID: scenario.id,
                    description: scenario.description,
                    title: brief.title,
                    briefBody: brief.body,
                    citationCount: brief.citationsPayload.count,
                    tokenEstimate: MalcomeTokenEstimator.estimateTokens(from: brief.body),
                    generationSeconds: elapsed,
                    wikipediaResolved: wikiResolved,
                    excerptSource: excerptSource
                ))
            } catch {
                failedCount += 1
                outputs.append(ScenarioOutput(
                    scenarioID: scenario.id,
                    description: scenario.description,
                    title: "FAILED",
                    briefBody: "Error: \(error.localizedDescription)",
                    citationCount: 0,
                    tokenEstimate: 0,
                    generationSeconds: Date().timeIntervalSince(start),
                    wikipediaResolved: false,
                    excerptSource: "none"
                ))
            }
        }

        return HarnessReport(
            runAt: ISO8601DateFormatter().string(from: Date()),
            totalScenarios: scenarios.count,
            completedScenarios: outputs.count - failedCount,
            failedScenarios: failedCount,
            outputs: outputs
        )
    }

    // MARK: - Scenario Builders

    private static func scenario(
        _ id: String,
        _ description: String,
        signals: [SyntheticSignal] = [],
        watchlist: [SyntheticWatchlistItem] = []
    ) -> SyntheticScenario {
        SyntheticScenario(id: id, description: description, signals: signals, watchlist: watchlist)
    }

    private static func signal(
        _ entity: (name: String, domain: CulturalDomain, type: EntityType),
        _ movement: SignalMovement,
        _ tier: SignalTier,
        families: Int,
        excerpt: String?,
        sources: [(name: String, city: String, family: String)]? = nil
    ) -> SyntheticSignal {
        let resolvedSources = sources ?? Array(sourcePool.prefix(max(2, families)))
        return SyntheticSignal(
            entityName: entity.name,
            domain: entity.domain,
            entityType: entity.type,
            movement: movement,
            signalTier: tier,
            sourceNames: resolvedSources.map(\.name),
            sourceCities: resolvedSources.map(\.city),
            sourceFamilyCount: families,
            observationCount: families * 3,
            excerpt: excerpt,
            evidenceSummary: "Corroborated across \(families) independent source families."
        )
    }

    private static func watch(
        _ entity: (name: String, domain: CulturalDomain, type: EntityType),
        _ stage: WatchlistStage
    ) -> SyntheticWatchlistItem {
        SyntheticWatchlistItem(
            entityName: entity.name,
            domain: entity.domain,
            entityType: entity.type,
            stage: stage,
            sourceFamilyCount: stage == .corroborating ? 2 : 1,
            observationCount: stage == .corroborating ? 4 : 2,
            whyNow: stage == .corroborating
                ? "Repeating across editorial and discovery lanes."
                : "First appearance in the current cycle."
        )
    }
}

// MARK: - Synthetic Data Types

struct SyntheticScenario {
    let id: String
    let description: String
    let signals: [SyntheticSignal]
    let watchlist: [SyntheticWatchlistItem]

    func toBriefingInput() -> BriefingInput {
        let packets = signals.map { signal -> BriefingInput.SignalPacket in
            let obs: [ObservationRecord] = signal.excerpt.map { excerpt in
                [ObservationRecord(
                    id: UUID().uuidString, sourceID: "synthetic", snapshotID: "synthetic",
                    canonicalEntityID: "", domain: signal.domain, entityType: signal.entityType,
                    externalIDOrHash: "", title: signal.entityName, subtitle: signal.sourceNames.first,
                    url: "", authorOrArtist: signal.entityName, tags: ["editorial"],
                    location: signal.sourceCities.first, publishedAt: nil,
                    scrapedAt: .now, excerpt: excerpt, distilledExcerpt: nil,
                    normalizedEntityName: signal.entityName.lowercased(), rawPayload: ""
                )]
            } ?? []

            return BriefingInput.SignalPacket(
                signal: SignalCandidateRecord(
                    id: UUID().uuidString,
                    canonicalEntityID: "\(signal.domain.rawValue)::\(signal.entityType.rawValue)::\(signal.entityName.lowercased().replacingOccurrences(of: " ", with: ""))",
                    domain: signal.domain,
                    canonicalName: signal.entityName,
                    entityType: signal.entityType,
                    firstSeenAt: .now.addingTimeInterval(-86400 * 7),
                    latestSeenAt: .now,
                    sourceCount: signal.sourceNames.count,
                    observationCount: signal.observationCount,
                    currentSourceCount: signal.sourceNames.count,
                    currentSourceFamilyCount: signal.sourceFamilyCount,
                    currentObservationCount: signal.observationCount,
                    historicalSourceCount: signal.sourceNames.count,
                    historicalObservationCount: signal.observationCount + 5,
                    growthScore: 8.0, diversityScore: Double(signal.sourceFamilyCount) * 3.0,
                    repeatAppearanceScore: 4.0, progressionScore: 3.0,
                    saturationScore: 0.5, emergenceScore: 12.0,
                    confidence: 0.8,
                    movement: signal.movement,
                    maturity: .advancing,
                    lifecycleState: .emerging,
                    conversionState: .pending,
                    outcomeTiers: [],
                    supportingSourceIDs: [],
                    progressionStages: [.discovery, .editorial],
                    progressionPattern: "discovery → editorial",
                    movementSummary: "\(signal.entityName) is \(signal.movement.rawValue).",
                    maturitySummary: "Advancing.",
                    lifecycleSummary: "Emerging.",
                    conversionSummary: "Pending.",
                    pathwaySummary: "Standard progression.",
                    sourceInfluenceSummary: "",
                    progressionSummary: "Discovery to editorial.",
                    evidenceSummary: signal.evidenceSummary,
                    signalTier: signal.signalTier
                ),
                observations: obs,
                sourceNames: signal.sourceNames,
                sourceCities: signal.sourceCities,
                priorMentions: 2,
                recentMentions: signal.observationCount
            )
        }

        let watchlistItems = watchlist.map { item -> WatchlistCandidate in
            WatchlistCandidate(
                id: UUID().uuidString,
                canonicalEntityID: "\(item.domain.rawValue)::\(item.entityType.rawValue)::\(item.entityName.lowercased())",
                title: item.entityName,
                domain: item.domain,
                entityType: item.entityType,
                stage: item.stage,
                sourceIDs: [],
                sourceFamilyCount: item.sourceFamilyCount,
                observationCount: item.observationCount,
                historicalMentionCount: item.observationCount + 2,
                historicalSourceDiversity: item.sourceFamilyCount,
                latestSeenAt: .now,
                summary: "Watch item.",
                note: "",
                whyNow: item.whyNow,
                upgradeTrigger: "One more independent source family.",
                score: 3.0
            )
        }

        let domains = Array(Set(
            packets.map(\.signal.domain.label) + watchlistItems.map(\.domain.label)
        )).sorted()

        return BriefingInput(
            generatedAt: .now,
            signals: packets,
            watchlistCandidates: watchlistItems,
            domainMix: domains,
            sourceInfluenceHighlights: []
        )
    }
}

struct SyntheticSignal {
    let entityName: String
    let domain: CulturalDomain
    let entityType: EntityType
    let movement: SignalMovement
    let signalTier: SignalTier
    let sourceNames: [String]
    let sourceCities: [String]
    let sourceFamilyCount: Int
    let observationCount: Int
    let excerpt: String?
    let evidenceSummary: String
}

struct SyntheticWatchlistItem {
    let entityName: String
    let domain: CulturalDomain
    let entityType: EntityType
    let stage: WatchlistStage
    let sourceFamilyCount: Int
    let observationCount: Int
    let whyNow: String
}
