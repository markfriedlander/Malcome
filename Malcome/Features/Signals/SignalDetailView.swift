import SwiftUI

struct SignalDetailView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let signal: SignalCandidateRecord

    @State private var evidence: [ObservationRecord] = []
    @State private var entityHistory: EntityHistoryRecord?
    @State private var runHistory: [SignalRunRecord] = []
    @State private var canonicalEntity: CanonicalEntityRecord?
    @State private var aliases: [EntityAliasRecord] = []
    @State private var sourceRoles: [EntitySourceRoleRecord] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(signal.canonicalName)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(MalcomePalette.primary)
                    Text(signal.evidenceSummary)
                        .foregroundStyle(MalcomePalette.secondary)
                    Text(condensed(signal.movementSummary))
                        .font(.headline)
                        .foregroundStyle(MalcomePalette.primary)
                }
                .cardStyle()

                overviewCard
                statusCard
                investigationCard
                scoreCard
                identityCard
                timelineCard

                VStack(alignment: .leading, spacing: 12) {
                    Text("Evidence")
                        .sectionTitle()

                    if isLoading && evidence.isEmpty {
                        ProgressView()
                    } else if evidence.isEmpty {
                        PlaceholderCard(
                            title: "No evidence yet",
                            message: "This signal exists in the scoring layer, but we don’t have cached evidence to show right now."
                        )
                    } else {
                        ForEach(evidence) { observation in
                            ObservationCard(
                                observation: observation,
                                sourceName: appModel.sourceName(for: observation.sourceID)
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Signal")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            LinearGradient(
                colors: [MalcomePalette.backgroundTop, MalcomePalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .task {
            guard evidence.isEmpty else { return }
            isLoading = true
            async let evidenceTask = appModel.evidence(for: signal)
            async let historyTask = appModel.entityHistory(for: signal)
            async let runsTask = appModel.signalRuns(for: signal)
            async let canonicalTask = appModel.canonicalEntity(for: signal.canonicalEntityID)
            async let aliasesTask = appModel.aliases(for: signal.canonicalEntityID)
            async let sourceRolesTask = appModel.sourceRoles(for: signal.canonicalEntityID)
            evidence = await evidenceTask
            entityHistory = await historyTask
            runHistory = await runsTask
            canonicalEntity = await canonicalTask
            aliases = await aliasesTask
            sourceRoles = await sourceRolesTask
            isLoading = false
        }
    }

    private var movementCard: some View {
        EmptyView()
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Read")
                .sectionTitle()

            HStack(spacing: 8) {
                badge(signal.movement.label, color: .blue)
                badge(signal.maturity.label, color: .indigo)
                badge(signal.entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, color: .orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Current read")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MalcomePalette.secondary)
                Text("\(signal.currentObservationCount) mention\(signal.currentObservationCount == 1 ? "" : "s") • \(signal.currentSourceCount) source\(signal.currentSourceCount == 1 ? "" : "s") • \(signal.currentSourceFamilyCount) \(signal.currentSourceFamilyCount == 1 ? "family" : "families")")
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Stored history")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MalcomePalette.secondary)
                Text("\(signal.historicalObservationCount) mention\(signal.historicalObservationCount == 1 ? "" : "s") • \(signal.historicalSourceCount) source\(signal.historicalSourceCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.secondary)
            }

            Text(signal.movementSummary)
                .foregroundStyle(MalcomePalette.secondary)

            if !signal.supportingSourceIDs.isEmpty {
                Text("Main sources: \(signal.supportingSourceIDs.map(appModel.sourceName(for:)).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.secondary)
            }
        }
        .cardStyle()
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("State of Play")
                .sectionTitle()
            statusRow(title: signal.maturity.label, summary: signal.maturitySummary)
            Divider()
            statusRow(title: signal.lifecycleState.label, summary: signal.lifecycleSummary)
            Divider()
            statusRow(title: signal.conversionState.label, summary: signal.conversionSummary)
        }
        .cardStyle()
    }

    private var investigationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Investigation Notes")
                .sectionTitle()

            if !signal.progressionPattern.isEmpty {
                Text("Progression")
                    .font(.headline)
                Text(signal.progressionSummary)
                    .foregroundStyle(.secondary)
                Divider()
            }

            Text("Pathway")
                .font(.headline)
            Text(signal.pathwaySummary)
                .foregroundStyle(.secondary)

            Divider()
            Text("Source Learning")
                .font(.headline)
            Text(signal.sourceInfluenceSummary)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Score Breakdown")
                .sectionTitle()
            ScoreRow(label: "Emergence", value: signal.emergenceScore)
            ScoreRow(label: "Growth", value: signal.growthScore)
            ScoreRow(label: "Diversity", value: signal.diversityScore)
            ScoreRow(label: "Repeat", value: signal.repeatAppearanceScore)
            ScoreRow(label: "Progression", value: signal.progressionScore)
            ScoreRow(label: "Saturation", value: signal.saturationScore)
            ScoreRow(label: "Confidence", value: signal.confidence * 10)
        }
        .cardStyle()
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timeline")
                .sectionTitle()

            if let entityHistory {
                Text("First seen: \(entityHistory.firstSeenAt.formatted(date: .abbreviated, time: .shortened))")
                Text("Last seen: \(entityHistory.lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                Text("Stored mentions: \(entityHistory.appearanceCount)")
                Text("Stored source diversity: \(entityHistory.sourceDiversity)")
            }

            if !runHistory.isEmpty {
                Divider()
                ForEach(runHistory.prefix(4)) { run in
                    HStack {
                        Text(run.runAt.formatted(date: .abbreviated, time: .shortened))
                        Spacer()
                        Text("#\(run.rank)")
                        Text(run.movement.label)
                        Text(run.lifecycleState.label)
                        Text(run.conversionState.label)
                        Text(run.score.formatted(.number.precision(.fractionLength(1))))
                            .font(.body.monospacedDigit())
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Identity Audit")
                .sectionTitle()

            if let canonicalEntity {
                HStack {
                    Text(canonicalEntity.displayName)
                        .font(.headline)
                    Spacer()
                    MergeConfidenceBadge(confidence: canonicalEntity.mergeConfidence)
                }

                Text(canonicalEntity.mergeSummary)
                    .foregroundStyle(MalcomePalette.secondary)

                if !aliases.isEmpty {
                    Divider()
                    Text("Aliases")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(aliases.prefix(6).map(\.aliasText).joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.secondary)
                }

                if !sourceRoles.isEmpty {
                    Divider()
                    Text("Role Evidence")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(sourceRoles.prefix(4)) { role in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(appModel.sourceName(for: role.sourceID))
                                Text(role.sourceClassification.label)
                                    .font(.caption)
                                    .foregroundStyle(MalcomePalette.secondary)
                            }
                            Spacer()
                            Text("\(role.appearanceCount)x")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(MalcomePalette.secondary)
                        }
                    }
                }
            } else {
                Text("Identity details are still loading.")
                    .foregroundStyle(MalcomePalette.secondary)
            }
        }
        .cardStyle()
    }

    private func statusRow(title: String, summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(summary)
                .foregroundStyle(MalcomePalette.secondary)
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func condensed(_ summary: String) -> String {
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
}
