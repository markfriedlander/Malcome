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
    @State private var showDevDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    Text(signal.canonicalName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MalcomePalette.primary)

                    HStack(spacing: 8) {
                        badge(signal.movement.label, color: movementColor)
                        badge(signal.domain.label, color: .orange)
                        badge(signal.entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, color: .indigo)
                    }
                }
                .cardStyle()

                // Plain language summary
                VStack(alignment: .leading, spacing: 12) {
                    Text("What I'm seeing")
                        .sectionTitle()

                    Text(plainLanguageSummary)
                        .font(.subheadline)
                        .foregroundStyle(MalcomePalette.primary.opacity(0.9))

                    if !signal.supportingSourceIDs.isEmpty {
                        Text("Sources: \(signal.supportingSourceIDs.map(appModel.sourceName(for:)).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(MalcomePalette.tertiary)
                    }
                }
                .cardStyle()

                // Trajectory
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trajectory")
                        .sectionTitle()
                    trajectoryRow(label: signal.maturity.label, text: plainMaturity)
                    Divider().background(MalcomePalette.stroke)
                    trajectoryRow(label: signal.lifecycleState.label, text: plainLifecycle)
                }
                .cardStyle()

                // Evidence
                VStack(alignment: .leading, spacing: 12) {
                    Text("Evidence")
                        .sectionTitle()

                    if isLoading && evidence.isEmpty {
                        ProgressView()
                    } else if evidence.isEmpty {
                        Text("No cached evidence to show right now.")
                            .font(.caption)
                            .foregroundStyle(MalcomePalette.tertiary)
                    } else {
                        ForEach(evidence) { observation in
                            ObservationCard(
                                observation: observation,
                                sourceName: appModel.sourceName(for: observation.sourceID)
                            )
                        }
                    }
                }

                // Timeline
                if let history = entityHistory {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timeline")
                            .sectionTitle()
                        Text("First seen \(history.firstSeenAt.formatted(date: .abbreviated, time: .omitted)), last seen \(history.lastSeenAt.formatted(date: .abbreviated, time: .omitted)). \(history.appearanceCount) total mentions across \(history.sourceDiversity) sources.")
                            .font(.caption)
                            .foregroundStyle(MalcomePalette.secondary)
                    }
                    .cardStyle()
                }

                // Developer details — collapsed
                DisclosureGroup("Developer details", isExpanded: $showDevDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        devRow("Emergence", signal.emergenceScore)
                        devRow("Growth", signal.growthScore)
                        devRow("Diversity", signal.diversityScore)
                        devRow("Repeat", signal.repeatAppearanceScore)
                        devRow("Progression", signal.progressionScore)
                        devRow("Saturation", signal.saturationScore)
                        devRow("Confidence", signal.confidence * 10)
                        Divider().background(MalcomePalette.stroke)
                        Text("Current: \(signal.currentObservationCount) mentions, \(signal.currentSourceCount) sources, \(signal.currentSourceFamilyCount) families")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(MalcomePalette.tertiary)
                        Text("Historical: \(signal.historicalObservationCount) mentions, \(signal.historicalSourceCount) sources")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(MalcomePalette.tertiary)
                    }
                    .padding(.top, 8)
                }
                .font(.caption)
                .foregroundStyle(MalcomePalette.tertiary)
                .cardStyle()
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

    // MARK: - Plain Language

    private var plainLanguageSummary: String {
        let sources = signal.sourceCount
        let families = signal.currentSourceFamilyCount

        var parts: [String] = []

        switch signal.movement {
        case .new:
            parts.append("This is a new appearance on the radar.")
        case .rising:
            parts.append("This has been building across multiple sources.")
        case .stable:
            parts.append("This has held steady across refreshes.")
        case .declining:
            parts.append("This was stronger in previous cycles. The support has thinned out.")
        }

        if families >= 2 {
            parts.append("Two genuinely different parts of the \(signal.domain.label.lowercased()) scene noticed this independently — that kind of agreement is hard to fake.")
        } else if sources > 1 {
            parts.append("Mentioned by \(sources) sources, though still within one source family.")
        } else {
            parts.append("Mentioned once in the latest refresh. Still early.")
        }

        return parts.joined(separator: " ")
    }

    private var plainMaturity: String {
        switch signal.maturity {
        case .earlyEmergence: return "Just starting to appear. Not enough history to say more yet."
        case .advancing: return "Building consistently over multiple refresh cycles."
        case .peaking: return "At its strongest visibility right now."
        case .cooling: return "Was stronger recently. The attention is fading."
        case .stalled: return "Stopped progressing. The pattern has flattened."
        }
    }

    private var plainLifecycle: String {
        switch signal.lifecycleState {
        case .emerging: return "Still emerging. The pattern is forming."
        case .advancing: return "Moving through the system. Picking up more sources."
        case .peaked: return "Hit the high point. May still hold or may start to cool."
        case .cooling: return "Losing sources. The initial momentum has passed."
        case .failed: return "Did not sustain. The early signal did not convert."
        case .disappeared: return "No longer showing up in the source network."
        }
    }

    private var movementColor: Color {
        switch signal.movement {
        case .new: return .green
        case .rising: return .orange
        case .stable: return .blue
        case .declining: return .gray
        }
    }

    // MARK: - Components

    private func trajectoryRow(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MalcomePalette.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(MalcomePalette.primary.opacity(0.85))
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func devRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(MalcomePalette.tertiary)
            Spacer()
            Text(value.formatted(.number.precision(.fractionLength(1))))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(MalcomePalette.tertiary)
        }
    }
}
