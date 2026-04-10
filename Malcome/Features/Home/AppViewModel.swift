import Foundation
import Combine
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var brief: BriefRecord?
    @Published private(set) var signals: [SignalCandidateRecord] = []
    @Published private(set) var watchlist: [WatchlistCandidate] = []
    @Published private(set) var ambiguousEntities: [CanonicalEntityRecord] = []
    @Published private(set) var sourceInfluenceStats: [SourceInfluenceStatRecord] = []
    @Published private(set) var sourceStatuses: [SourceStatusRecord] = []
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshSummary: String?
    @Published private(set) var refreshWarning: String?
    @Published var errorMessage: String?
    @Published private(set) var isFirstLaunch = false

    let container: AppContainer
    let loadingMessages = LoadingMessageProvider()

    init(container: AppContainer) {
        self.container = container
    }

    func bootstrapIfNeeded() async {
        do {
            // Detect first launch from seed
            if UserDefaults.standard.bool(forKey: "malcome_seeded_from_bundle"),
               !UserDefaults.standard.bool(forKey: "malcome_first_launch_complete") {
                isFirstLaunch = true
            }

            try await container.repository.seedSourcesIfNeeded(container.sourceRegistry.initialSeeds())
            try await reload()

            if brief == nil {
                await refreshAll()
            }

            if isFirstLaunch {
                UserDefaults.standard.set(true, forKey: "malcome_first_launch_complete")
                isFirstLaunch = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async throws {
        async let briefTask = container.repository.fetchLatestBrief()
        async let signalsTask = container.repository.fetchTopSignals(limit: 12)
        async let watchlistTask = container.briefComposer.watchlistCandidates(limit: 8)
        async let ambiguousTask = container.repository.fetchAmbiguousCanonicalEntities(limit: 16)
        async let sourceInfluenceTask = container.repository.fetchSourceInfluenceStats(limit: 16)
        async let statusTask = container.repository.sourceStatuses()
        async let lastRefreshTask = container.repository.latestSuccessfulRefreshDate()

        brief = try await briefTask
        signals = try await signalsTask
        watchlist = try await watchlistTask
        ambiguousEntities = try await ambiguousTask
        sourceInfluenceStats = try await sourceInfluenceTask
        sourceStatuses = try await statusTask
        lastRefreshAt = try await lastRefreshTask
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        refreshWarning = nil
        let activeDomains = Set(sourceStatuses.filter(\.source.enabled).map(\.source.domain))
        loadingMessages.start(activeDomains: activeDomains)

        do {
            try await container.repository.seedSourcesIfNeeded(container.sourceRegistry.initialSeeds())
            let report = try await container.sourcePipeline.refreshEnabledSources()
            let observations = try await container.repository.fetchObservations(limit: 500)
            await ExcerptDistiller.distillNewObservations(
                observations: observations,
                repository: container.repository
            )
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
            try await reload()
            applyRefreshSummary(report: report)
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
        loadingMessages.stop()
    }

    func setSourceEnabled(sourceID: String, isEnabled: Bool) async {
        do {
            try await container.repository.setSourceEnabled(sourceID: sourceID, isEnabled: isEnabled)
            sourceStatuses = try await container.repository.sourceStatuses()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setModuleEnabled(moduleID: String, isEnabled: Bool) async {
        do {
            try await container.repository.setModuleEnabled(moduleID: moduleID, isEnabled: isEnabled)
            sourceStatuses = try await container.repository.sourceStatuses()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func evidence(for signal: SignalCandidateRecord) async -> [ObservationRecord] {
        (try? await container.repository.observations(forCanonicalEntityID: signal.canonicalEntityID, limit: 12)) ?? []
    }

    func entityHistory(for signal: SignalCandidateRecord) async -> EntityHistoryRecord? {
        try? await container.repository.entityHistory(forCanonicalName: signal.canonicalEntityID)
    }

    func signalRuns(for signal: SignalCandidateRecord) async -> [SignalRunRecord] {
        (try? await container.repository.signalRuns(forCanonicalName: signal.canonicalEntityID, limit: 8)) ?? []
    }

    func canonicalEntity(for canonicalEntityID: String) async -> CanonicalEntityRecord? {
        try? await container.repository.canonicalEntity(id: canonicalEntityID)
    }

    func aliases(for canonicalEntityID: String) async -> [EntityAliasRecord] {
        (try? await container.repository.entityAliases(forCanonicalEntityID: canonicalEntityID)) ?? []
    }

    func sourceRoles(for canonicalEntityID: String) async -> [EntitySourceRoleRecord] {
        (try? await container.repository.entitySourceRoles(forCanonicalEntityID: canonicalEntityID)) ?? []
    }

    func sourceName(for sourceID: String) -> String {
        sourceStatuses.first(where: { $0.source.id == sourceID })?.source.name ?? "Unknown Source"
    }

    private func applyRefreshSummary(report: RefreshReport) {
        let successes = report.snapshots.filter { $0.status == .success }
        let failures = report.snapshots.filter { $0.status == .failed }
        let skipped = report.snapshots.filter { $0.status == .skipped }
        let attemptedCount = successes.count + failures.count
        let itemTotal = successes.reduce(0) { $0 + $1.itemCount }

        let summaryCore = attemptedCount == 0
            ? "No sources attempted • \(itemTotal) observations stored"
            : "\(successes.count)/\(attemptedCount) attempted sources healthy • \(itemTotal) observations stored"
        refreshSummary = skipped.isEmpty ? summaryCore : "\(summaryCore) • \(skipped.count) paused"

        if failures.isEmpty && skipped.isEmpty {
            refreshWarning = nil
        } else if failures.isEmpty {
            refreshWarning = "\(skipped.count) source\(skipped.count == 1 ? "" : "s") stayed in a polite cooldown window this pass. Malcome kept building today's read from the sources that were ready."
        } else if skipped.isEmpty {
            refreshWarning = "\(failures.count) source\(failures.count == 1 ? "" : "s") did not come through this pass. Malcome kept building today's read from the sources that did."
        } else {
            refreshWarning = "\(failures.count) source\(failures.count == 1 ? "" : "s") did not come through, and \(skipped.count) stayed in a polite cooldown window. Malcome kept building today's read from the sources that were ready."
        }
    }
}
