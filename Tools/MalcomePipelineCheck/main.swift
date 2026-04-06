import Foundation

@main
struct MalcomePipelineCheck {
    static func main() async {
        do {
            let configuration = try Configuration(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
            let container = AppContainer.live(databaseURL: configuration.databaseURL)

            try await container.repository.seedSourcesIfNeeded(container.sourceRegistry.initialSeeds())

            for cycle in 1...configuration.cycles {
                print("== Cycle \(cycle) ==")
                let report = try await container.sourcePipeline.refreshEnabledSources()
                try await summarize(report: report, repository: container.repository)
                let observations = try await container.repository.fetchObservations(limit: 1_000)
                let sources = try await container.repository.fetchSources()
                let runHistory = try await container.repository.recentSignalRuns(limit: 400)
                let pathwayStats = try await container.repository.fetchPathwayStats(limit: 200)
                let runHistoryByName = Dictionary(grouping: runHistory) {
                    $0.canonicalEntityID.isEmpty ? $0.canonicalName : $0.canonicalEntityID
                }
                let pathwayStatsByPattern = Dictionary(uniqueKeysWithValues: pathwayStats.map { ("\($0.domain.rawValue)::\($0.pathwayPattern)", $0) })
                let sourceMap = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
                let computed = container.signalEngine.compute(
                    from: observations,
                    sourcesByID: sourceMap,
                    runHistoryByName: runHistoryByName,
                    pathwayStatsByPattern: pathwayStatsByPattern,
                    now: report.completedAt
                )
                try await container.repository.replaceCanonicalIdentityGraph(
                    entities: computed.canonicalEntities,
                    aliases: computed.aliases,
                    sourceRoles: computed.sourceRoles,
                    observationMappings: computed.observationMappings
                )
                try await container.repository.replaceEntityStageSnapshots(computed.stageSnapshots)
                try await container.repository.replaceEntityHistories(computed.entityHistories)
                try await container.repository.replaceSignalCandidates(Array(computed.signals.prefix(20)))
                try await container.repository.storeSignalRuns(Array(computed.runs.prefix(20)))
                try await container.repository.appendPathwayHistory(computed.pathwayHistories)
                try await container.repository.replacePathwayStats(computed.pathwayStats)
                try await container.repository.replaceSourceInfluenceStats(computed.sourceInfluenceStats)
                try await container.repository.replaceOutcomeConfirmations(computed.outcomeConfirmations)
                _ = try await container.briefComposer.composeBrief()
                if cycle < configuration.cycles {
                    try await Task.sleep(for: .seconds(configuration.pauseSeconds))
                }
            }

            let observations = try await container.repository.fetchObservations(limit: 1_000)
            let sources = try await container.repository.fetchSources()
            let sourceMap = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
            let signals = try await container.repository.fetchTopSignals(limit: 20)
            let ambiguousEntities = try await container.repository.fetchAmbiguousCanonicalEntities(limit: 10)
            let sourceInfluenceStats = try await container.repository.fetchSourceInfluenceStats(limit: 20)
            let brief = try await container.repository.fetchLatestBrief() ?? BriefRecord(
                id: UUID().uuidString,
                generatedAt: .now,
                title: "Malcome Brief Pending",
                body: "No brief has been generated yet.",
                citationsPayload: [],
                periodType: .daily
            )

            print("")
            print("== Storage ==")
            print("Observations stored: \(observations.count)")
            print("Signals generated: \(signals.count)")

            if configuration.debugTitles {
                print("")
                print("== Repeated Titles ==")
                let repeatedTitles = Dictionary(grouping: observations) { $0.canonicalEntityID }
                    .filter { $0.value.count > 1 }
                    .sorted { $0.value.count > $1.value.count }
                for (canonicalID, matches) in repeatedTitles.prefix(10) {
                    let title = signals.first(where: { $0.canonicalEntityID == canonicalID })?.canonicalName ?? canonicalID
                    print("- \(title) | \(matches.count) observations")
                }
            }

            print("")
            print("== Top Signals ==")
            if signals.isEmpty {
                print("No corroborated signals yet. Run another cycle or inspect source yields below.")
            } else {
                for signal in signals.prefix(5) {
                    print("- \(signal.canonicalName) | \(signal.movement.label.lowercased()) | \(signal.maturity.label.lowercased()) | \(signal.lifecycleState.label.lowercased()) | score \(format(signal.emergenceScore)) | \(signal.sourceCount) sources | \(signal.observationCount) observations")
                    print("  \(signal.movementSummary)")
                    print("  \(signal.maturitySummary)")
                    print("  \(signal.lifecycleSummary)")
                    print("  \(signal.conversionSummary)")
                    print("  \(signal.pathwaySummary)")
                    print("  \(signal.sourceInfluenceSummary)")
                    if !signal.progressionPattern.isEmpty {
                        print("  progression: \(signal.progressionPattern)")
                        print("  \(signal.progressionSummary)")
                    }
                }
            }

            let multiTierASignals = signals.filter { signal in
                let evidence = observations.filter { $0.canonicalEntityID == signal.canonicalEntityID }
                let tierASources = Set(evidence.compactMap { sourceMap[$0.sourceID]?.tier == .a ? $0.sourceID : nil })
                return tierASources.count >= 2
            }
            if !multiTierASignals.isEmpty {
                print("")
                print("== Tier A Crossovers ==")
                for signal in multiTierASignals.prefix(5) {
                    print("- \(signal.canonicalName) | \(signal.sourceCount) sources | score \(format(signal.emergenceScore))")
                }
            }

            if !ambiguousEntities.isEmpty {
                print("")
                print("== Identity Watchlist ==")
                for entity in ambiguousEntities.prefix(5) {
                    print("- \(entity.displayName) | confidence \(format(entity.mergeConfidence * 100))%")
                    print("  \(entity.mergeSummary)")
                }
            }

            let lifecycleReversals = signals.filter {
                [.cooling, .failed, .disappeared].contains($0.lifecycleState)
            }
            if !lifecycleReversals.isEmpty {
                print("")
                print("== Lifecycle Reversals ==")
                for signal in lifecycleReversals.prefix(5) {
                    print("- \(signal.canonicalName) | \(signal.lifecycleState.label.lowercased()) | score \(format(signal.emergenceScore))")
                    print("  \(signal.lifecycleSummary)")
                }
            }

            if !sourceInfluenceStats.isEmpty {
                let topFamilies = sourceInfluenceStats.filter { $0.scope == .family }.prefix(5)
                let fragileFamilies = sourceInfluenceStats
                    .filter { $0.scope == .family && $0.predictiveScore < 0 }
                    .sorted { $0.predictiveScore < $1.predictiveScore }
                    .prefix(3)

                if !topFamilies.isEmpty {
                    print("")
                    print("== Source Influence ==")
                    for stat in topFamilies {
                        print("- \(stat.displayName) | \(stat.scope.label.lowercased()) | score \(format(stat.predictiveScore)) | \(stat.sampleCount) runs")
                        print("  \(stat.summary)")
                    }
                }

                if !fragileFamilies.isEmpty {
                    print("")
                    print("== Fragile Source Families ==")
                    for stat in fragileFamilies {
                        print("- \(stat.displayName) | score \(format(stat.predictiveScore)) | \(stat.sampleCount) runs")
                        print("  \(stat.summary)")
                    }
                }
            }

            let doctrineSamples = Dictionary(grouping: sources.filter(\.enabled), by: \.moduleID)
                .compactMap { _, group in group.sorted { $0.name < $1.name }.first }
                .sorted { $0.moduleName < $1.moduleName }

            if !doctrineSamples.isEmpty {
                print("")
                print("== Source Doctrine Samples ==")
                for source in doctrineSamples.prefix(5) {
                    let doctrine = source.doctrineProfile
                    print("- \(source.name) | \(source.domain.label) | \(source.classification.label)")
                    print("  early: \(doctrine.whyEarly)")
                    print("  selective: \(doctrine.whySelective)")
                    print("  corroboration: \(doctrine.corroborationRole)")
                }
            }

            print("")
            print("== Brief ==")
            print(brief.title)
            print(brief.body.replacingOccurrences(of: "\n", with: "\n"))
            print("")
            print("Citations: \(brief.citationsPayload.count)")
        } catch {
            fputs("Malcome pipeline check failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func summarize(report: RefreshReport, repository: AppRepository) async throws {
        let sources = try await repository.fetchSources()
        let sourceNamesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.name) })
        let sourceByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

        let successes = report.snapshots.filter { $0.status == .success }
        let failures = report.snapshots.filter { $0.status == .failed }
        let skipped = report.snapshots.filter { $0.status == .skipped }
        let attemptedCount = successes.count + failures.count
        let items = successes.reduce(0) { $0 + $1.itemCount }

        if skipped.isEmpty {
            print("Sources healthy: \(successes.count)/\(attemptedCount)")
        } else {
            print("Sources healthy: \(successes.count)/\(attemptedCount) attempted (\(skipped.count) paused)")
        }
        print("Observations captured this cycle: \(items)")

        for snapshot in report.snapshots {
            let sourceName = sourceNamesByID[snapshot.sourceID] ?? snapshot.sourceID
            let tier = sourceByID[snapshot.sourceID]?.tier.rawValue ?? "?"
            switch snapshot.status {
            case .success:
                print("- [ok] [Tier \(tier)] \(sourceName): \(snapshot.itemCount) items")
            case .failed:
                let message = snapshot.errorMessage ?? "Unknown failure"
                print("- [fail] [Tier \(tier)] \(sourceName): \(message)")
            case .skipped:
                let message = snapshot.errorMessage ?? "Skipped by source policy"
                print("- [skip] [Tier \(tier)] \(sourceName): \(message)")
            case .running:
                print("- [run] [Tier \(tier)] \(sourceName)")
            }
        }

        if !failures.isEmpty {
            print("Failures were recorded, but the pipeline stayed live and continued with successful sources.")
        } else if !skipped.isEmpty {
            print("Some sources stayed in their politeness window, and the pipeline kept going with the ones that were ready.")
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct Configuration {
    let databaseURL: URL
    let cycles: Int
    let pauseSeconds: Double
    let debugTitles: Bool

    init(arguments: [String], environment: [String: String]) throws {
        let defaultDatabase: URL
        if let overridePath = environment["MALCOME_STORAGE_PATH"], !overridePath.isEmpty {
            defaultDatabase = URL(fileURLWithPath: overridePath)
        } else {
            defaultDatabase = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("malcome-pipeline-check.sqlite")
        }

        var databaseURL = defaultDatabase
        var cycles = 2
        var pauseSeconds = 0.2
        var debugTitles = false

        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--db":
                guard let path = iterator.next() else {
                    throw CLIError.invalidArguments("--db requires a path")
                }
                databaseURL = URL(fileURLWithPath: path)
            case "--cycles":
                guard let raw = iterator.next(), let value = Int(raw), value > 0 else {
                    throw CLIError.invalidArguments("--cycles requires a positive integer")
                }
                cycles = value
            case "--pause":
                guard let raw = iterator.next(), let value = Double(raw), value >= 0 else {
                    throw CLIError.invalidArguments("--pause requires a non-negative number")
                }
                pauseSeconds = value
            case "--debug-titles":
                debugTitles = true
            case "--help":
                throw CLIError.help
            default:
                throw CLIError.invalidArguments("Unknown argument: \(argument)")
            }
        }

        self.databaseURL = databaseURL
        self.cycles = cycles
        self.pauseSeconds = pauseSeconds
        self.debugTitles = debugTitles
    }
}

private enum CLIError: LocalizedError {
    case invalidArguments(String)
    case help

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message):
            return "\(message)\nUsage: malcome-pipeline-check [--db /path/to.sqlite] [--cycles 2] [--pause 0.2] [--debug-titles]"
        case .help:
            return "Usage: malcome-pipeline-check [--db /path/to.sqlite] [--cycles 2] [--pause 0.2] [--debug-titles]"
        }
    }
}
