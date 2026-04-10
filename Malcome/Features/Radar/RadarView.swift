import SwiftUI

struct RadarView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !appModel.signals.isEmpty {
                    Text("Signals")
                        .font(.headline)
                        .foregroundStyle(MalcomePalette.primary)
                        .padding(.horizontal, 20)

                    ForEach(appModel.signals.prefix(10)) { signal in
                        NavigationLink {
                            SignalDetailView(signal: signal)
                        } label: {
                            RadarSignalCard(signal: signal)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }
                }

                if !appModel.watchlist.isEmpty {
                    Text("Watchlist")
                        .font(.headline)
                        .foregroundStyle(MalcomePalette.primary)
                        .padding(.horizontal, 20)
                        .padding(.top, appModel.signals.isEmpty ? 0 : 8)

                    ForEach(appModel.watchlist.prefix(8)) { candidate in
                        RadarWatchlistCard(candidate: candidate, sourceName: sourceName(for: candidate))
                            .padding(.horizontal, 20)
                    }
                }

                if appModel.signals.isEmpty && appModel.watchlist.isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 40)
                        Text("The radar is still building corroboration.")
                            .font(.body)
                            .foregroundStyle(MalcomePalette.secondary)
                            .multilineTextAlignment(.center)
                        Text("Run another refresh so Malcome can compare sources.")
                            .font(.caption)
                            .foregroundStyle(MalcomePalette.tertiary)
                            .multilineTextAlignment(.center)
                        Spacer().frame(height: 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(
            LinearGradient(
                colors: [
                    MalcomePalette.backgroundTop,
                    Color(red: 0.07, green: 0.08, blue: 0.10),
                    MalcomePalette.backgroundBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Radar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sourceName(for candidate: WatchlistCandidate) -> String {
        let names = candidate.sourceIDs.compactMap(appModel.sourceName(for:))
        if names.count <= 2 {
            return names.joined(separator: ", ")
        }
        return "\(names.prefix(2).joined(separator: ", ")) + \(names.count - 2) more"
    }
}

// MARK: - Signal Card

struct RadarSignalCard: View {
    let signal: SignalCandidateRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(signal.canonicalName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MalcomePalette.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        movementBadge
                        Text(signal.domain.label)
                            .font(.caption2)
                            .foregroundStyle(MalcomePalette.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.tertiary)
            }

            // Stats row — abbreviated, never wrapping
            HStack(spacing: 16) {
                statItem(value: signal.sourceCount, label: "Sources")
                statItem(value: signal.currentSourceFamilyCount, label: "Families")
                statItem(value: signal.currentObservationCount, label: "Mentions")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MalcomePalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MalcomePalette.stroke, lineWidth: 0.5)
        )
    }

    private var movementBadge: some View {
        Text(signal.movement.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(movementColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(movementColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var movementColor: Color {
        switch signal.movement {
        case .new: return .green
        case .rising: return .orange
        case .stable: return .blue
        case .declining: return .gray
        }
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(MalcomePalette.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(MalcomePalette.tertiary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Watchlist Card

struct RadarWatchlistCard: View {
    let candidate: WatchlistCandidate
    let sourceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MalcomePalette.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        stageBadge
                        Text(candidate.domain.label)
                            .font(.caption2)
                            .foregroundStyle(MalcomePalette.tertiary)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    statItem(value: candidate.sourceFamilyCount, label: "Families")
                    statItem(value: candidate.observationCount, label: "Mentions")
                }
            }

            if !sourceName.isEmpty {
                Text(sourceName)
                    .font(.caption2)
                    .foregroundStyle(MalcomePalette.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MalcomePalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MalcomePalette.stroke, lineWidth: 0.5)
        )
    }

    private var stageBadge: some View {
        Text(candidate.stage.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(stageColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(stageColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var stageColor: Color {
        switch candidate.stage {
        case .early: return .gray
        case .forming: return .yellow
        case .corroborating: return .orange
        }
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(MalcomePalette.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(MalcomePalette.tertiary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
