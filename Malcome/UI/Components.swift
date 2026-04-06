import SwiftUI

enum MalcomePalette {
    static let backgroundTop = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let backgroundBottom = Color(red: 0.03, green: 0.04, blue: 0.05)
    static let card = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let cardElevated = Color(red: 0.16, green: 0.17, blue: 0.20)
    static let stroke = Color.white.opacity(0.08)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.72)
    static let tertiary = Color.white.opacity(0.52)
}

struct PlaceholderCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(MalcomePalette.primary)
            Text(message)
                .foregroundStyle(MalcomePalette.secondary)
        }
        .cardStyle()
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.red.opacity(0.95))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.red.opacity(0.24), lineWidth: 1)
            )
    }
}

struct InfoBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.orange.opacity(0.95))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.orange.opacity(0.24), lineWidth: 1)
            )
    }
}

struct SignalRow: View {
    let signal: SignalCandidateRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(signal.canonicalName)
                    .font(.headline)
                    .foregroundStyle(MalcomePalette.primary)
                Spacer()
                HStack(spacing: 6) {
                    Text(signal.movement.label)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(movementColor(signal.movement).opacity(0.16), in: Capsule())
                    Text(signal.maturity.label)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.14), in: Capsule())
                    Text(signal.entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
            }

            Text(signal.evidenceSummary)
                .font(.subheadline)
                .foregroundStyle(MalcomePalette.secondary)
                .lineLimit(2)

            Text(condensed(signal.movementSummary))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MalcomePalette.secondary)
                .lineLimit(3)

            if !signal.progressionPattern.isEmpty {
                Text("Pattern: \(signal.progressionPattern)")
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.secondary)
                    .lineLimit(1)
            }

            Text(condensed(signal.lifecycleSummary))
                .font(.caption)
                .foregroundStyle(MalcomePalette.secondary)
                .lineLimit(2)

            HStack {
                Label("\(signal.currentSourceCount) current source\(signal.currentSourceCount == 1 ? "" : "s")", systemImage: "square.stack.3d.up")
                Label("\(signal.currentSourceFamilyCount) current \(signal.currentSourceFamilyCount == 1 ? "family" : "families")", systemImage: "square.split.bottomrightquarter")
                Label("\(signal.currentObservationCount) current mention\(signal.currentObservationCount == 1 ? "" : "s")", systemImage: "waveform")
                Text(signal.lifecycleState.label)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(lifecycleColor(signal.lifecycleState).opacity(0.14), in: Capsule())
                Spacer()
                Text(signal.emergenceScore.formatted(.number.precision(.fractionLength(1))))
                    .font(.headline.monospacedDigit())
            }
            .font(.caption)
            .foregroundStyle(MalcomePalette.secondary)

            Text("Stored history: \(signal.historicalObservationCount) mentions across \(signal.historicalSourceCount) source\(signal.historicalSourceCount == 1 ? "" : "s").")
                .font(.caption)
                .foregroundStyle(MalcomePalette.tertiary)
        }
        .cardStyle()
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

    private func movementColor(_ movement: SignalMovement) -> Color {
        switch movement {
        case .new:
            return .blue
        case .rising:
            return .green
        case .stable:
            return .orange
        case .declining:
            return .red
        }
    }

    private func lifecycleColor(_ lifecycle: SignalLifecycleState) -> Color {
        switch lifecycle {
        case .emerging:
            return .blue
        case .advancing:
            return .green
        case .peaked:
            return .purple
        case .cooling:
            return .orange
        case .failed, .disappeared:
            return .red
        }
    }
}

struct WatchlistRow: View {
    let candidate: WatchlistCandidate
    let sourceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(candidate.title)
                    .font(.headline)
                    .foregroundStyle(MalcomePalette.primary)
                Spacer()
                HStack(spacing: 6) {
                    Text(candidate.stage.label)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(stageColor.opacity(0.14), in: Capsule())
                    Text(candidate.entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Why watch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MalcomePalette.secondary)
                Text(candidate.whyNow)
                    .font(.subheadline)
                    .foregroundStyle(MalcomePalette.primary.opacity(0.92))
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("What would make it real")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MalcomePalette.secondary)
                Text(candidate.upgradeTrigger)
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.secondary)
                    .lineLimit(3)
            }

            HStack {
                Text(candidate.domain.label)
                Text("•")
                Text(sourceName)
                Spacer()
                Text("\(candidate.observationCount) current mention\(candidate.observationCount == 1 ? "" : "s")")
                Text("•")
                Text("\(candidate.sourceFamilyCount) \(candidate.sourceFamilyCount == 1 ? "family" : "families")")
            }
            .font(.caption)
            .foregroundStyle(MalcomePalette.secondary)

            HStack {
                Text("\(candidate.historicalMentionCount) historical mention\(candidate.historicalMentionCount == 1 ? "" : "s")")
                Text("•")
                Text("\(candidate.historicalSourceDiversity) lifetime source\(candidate.historicalSourceDiversity == 1 ? "" : "s")")
            }
            .font(.caption)
            .foregroundStyle(MalcomePalette.tertiary)
        }
        .cardStyle()
    }

    private var stageColor: Color {
        switch candidate.stage {
        case .early:
            return .orange
        case .forming:
            return .blue
        case .corroborating:
            return .green
        }
    }
}

struct MergeConfidenceBadge: View {
    let confidence: Double

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        "Merge \(Int((confidence * 100).rounded()))%"
    }

    private var color: Color {
        switch confidence {
        case ..<0.8: return .red
        case 0.8..<0.9: return .orange
        default: return .green
        }
    }
}

struct IdentityReviewRow: View {
    let entity: CanonicalEntityRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entity.displayName)
                        .font(.headline)
                        .foregroundStyle(MalcomePalette.primary)
                    Text("\(entity.domain.label) • \(entity.entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)")
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.secondary)
                }
                Spacer()
                MergeConfidenceBadge(confidence: entity.mergeConfidence)
            }

            Text(entity.mergeSummary)
                .font(.caption)
                .foregroundStyle(MalcomePalette.secondary)
                .lineLimit(3)

            if !entity.aliases.isEmpty {
                Text(entity.aliases.prefix(4).joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.secondary)
                    .lineLimit(2)
            }
        }
        .cardStyle()
    }
}

struct SourceInfluenceRow: View {
    let stat: SourceInfluenceStatRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.displayName)
                        .font(.headline)
                        .foregroundStyle(MalcomePalette.primary)
                    Text("\(stat.domain.label) • \(stat.scope.label)")
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.secondary)
                }
                Spacer()
                Text(scoreLabel)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(scoreColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(scoreColor)
            }

            Text(stat.summary)
                .font(.caption)
                .foregroundStyle(MalcomePalette.secondary)

            HStack {
                Text("\(stat.sampleCount) runs")
                Text("•")
                Text("\(stat.conversionCount) conversions")
                Text("•")
                Text("\(stat.failedCount + stat.disappearedCount) failures")
                Spacer()
                Text("avg \(stat.averageSignalScore.formatted(.number.precision(.fractionLength(1))))")
                    .font(.caption.monospacedDigit())
            }
            .font(.caption)
            .foregroundStyle(MalcomePalette.secondary)
        }
        .cardStyle()
    }

    private var scoreLabel: String {
        "\(stat.predictiveScore >= 0 ? "+" : "")\(stat.predictiveScore.formatted(.number.precision(.fractionLength(1))))"
    }

    private var scoreColor: Color {
        switch stat.predictiveScore {
        case ..<0:
            return .red
        case 0..<1:
            return .orange
        default:
            return .green
        }
    }
}

struct CitationCard: View {
    let citation: BriefCitation

    var body: some View {
        Link(destination: URL(string: citation.url) ?? URL(string: "https://example.com")!) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(citation.signalName.capitalized)
                        .font(.headline)
                        .foregroundStyle(MalcomePalette.primary)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MalcomePalette.tertiary)
                }
                Text(citation.observationTitle)
                    .foregroundStyle(MalcomePalette.primary.opacity(0.88))
                Text(citation.sourceName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MalcomePalette.secondary)
                Text(citation.note)
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

struct ObservationCard: View {
    let observation: ObservationRecord
    let sourceName: String

    var body: some View {
        Link(destination: URL(string: observation.url) ?? URL(string: "https://example.com")!) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(observation.title)
                        .font(.headline)
                        .foregroundStyle(MalcomePalette.primary)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MalcomePalette.tertiary)
                }
                if let subtitle = observation.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(MalcomePalette.secondary)
                }
                Text(sourceName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MalcomePalette.secondary)
                if let excerpt = observation.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

struct SourceStatusRow: View {
    let status: SourceStatusRecord
    let onToggle: (Bool) -> Void

    var body: some View {
        let doctrine = status.source.doctrineProfile

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(status.source.name)
                            .font(.headline)
                            .foregroundStyle(MalcomePalette.primary)
                        Text(status.source.tier.label)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tierColor(status.source.tier).opacity(0.14), in: Capsule())
                    }
                    Text("\(status.source.domain.label) • \(status.source.classification.label)")
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { status.source.enabled },
                    set: onToggle
                ))
                .labelsHidden()
            }

            if let snapshot = status.latestSnapshot {
                HStack {
                    Text(statusLabel(snapshot.status))
                    Text("•")
                    Text("\(snapshot.itemCount) items")
                    if let completedAt = snapshot.completedAt {
                        Text("•")
                        Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                    .font(.caption)
                    .foregroundStyle(statusColor(snapshot.status))

                if let errorMessage = snapshot.errorMessage, !errorMessage.isEmpty, snapshot.status != .success {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(statusColor(snapshot.status))
                }
            } else {
                Text("No refresh yet")
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.secondary)
            }

            Text(status.source.justification)
                .font(.caption)
                .foregroundStyle(MalcomePalette.secondary)

            VStack(alignment: .leading, spacing: 8) {
                doctrineLine(title: "Why early", text: doctrine.whyEarly)
                doctrineLine(title: "Why selective", text: doctrine.whySelective)
                doctrineLine(title: "Corroboration role", text: doctrine.corroborationRole)
            }
            .padding(12)
            .background(MalcomePalette.cardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MalcomePalette.stroke, lineWidth: 1)
            )
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func doctrineLine(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MalcomePalette.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(MalcomePalette.secondary)
        }
    }

    private func tierColor(_ tier: SourceTier) -> Color {
        switch tier {
        case .a:
            return .orange
        case .b:
            return .blue
        case .c:
            return .gray
        }
    }

    private func statusLabel(_ status: SnapshotStatus) -> String {
        switch status {
        case .running: return "Running"
        case .success: return "Success"
        case .failed: return "Failed"
        case .skipped: return "Paused"
        }
    }

    private func statusColor(_ status: SnapshotStatus) -> Color {
        switch status {
        case .failed:
            return .red
        case .skipped:
            return .orange
        case .running, .success:
            return .secondary
        }
    }
}

struct ScoreRow: View {
    let label: String
    let value: Double

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.formatted(.number.precision(.fractionLength(1))))
                .font(.body.monospacedDigit())
        }
    }
}

struct SourceRoleCard: View {
    let role: EntitySourceRoleRecord
    let sourceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sourceName)
                    .font(.headline)
                    .foregroundStyle(MalcomePalette.primary)
                Spacer()
                Text(role.sourceClassification.label)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.14), in: Capsule())
            }
            Text("First seen: \(role.firstSeenAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(MalcomePalette.secondary)
            Text("Last seen: \(role.lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(MalcomePalette.secondary)
            Text("\(role.appearanceCount) appearance\(role.appearanceCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(MalcomePalette.secondary)
        }
        .cardStyle()
    }
}

extension View {
    func cardStyle() -> some View {
        self
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(MalcomePalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(MalcomePalette.stroke, lineWidth: 1)
            )
    }
}

extension Text {
    func sectionTitle() -> some View {
        self
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(MalcomePalette.tertiary)
    }
}
