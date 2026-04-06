import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let errorMessage = appModel.errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                if let refreshWarning = appModel.refreshWarning {
                    InfoBanner(message: refreshWarning)
                }

                briefSection
                signalsSection
                identitySection
                citationsSection
            }
            .padding(20)
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
        .navigationTitle("Malcome")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await appModel.bootstrapIfNeeded()
        }
        .refreshable {
            await appModel.refreshAll()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Malcome")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(MalcomePalette.primary)

            Text("Local-first cultural signal hunting for Los Angeles.")
                .font(.subheadline)
                .foregroundStyle(MalcomePalette.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last refresh")
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.secondary)
                    Text(appModel.lastRefreshAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
                        .font(.headline)
                        .foregroundStyle(MalcomePalette.primary)
                    if let refreshSummary = appModel.refreshSummary {
                        Text(refreshSummary)
                            .font(.caption)
                            .foregroundStyle(MalcomePalette.secondary)
                    }
                }

                Spacer()

                Button {
                    Task { await appModel.refreshAll() }
                } label: {
                    HStack {
                        if appModel.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(appModel.isRefreshing ? "Refreshing" : "Refresh")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.88))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(appModel.isRefreshing)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(MalcomePalette.cardElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(MalcomePalette.stroke, lineWidth: 1)
        )
    }

    private var briefSection: some View {
        Group {
            if let brief = appModel.brief {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today’s Brief")
                        .sectionTitle()
                    Text(brief.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MalcomePalette.primary)
                    Text(brief.body)
                        .font(.body)
                        .foregroundStyle(MalcomePalette.primary.opacity(0.9))
                }
                .cardStyle()
            } else {
                PlaceholderCard(
                    title: "Today’s Brief",
                    message: "Refresh the source set to build the first narrative briefing."
                )
            }
        }
    }

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(signalsSectionTitle)
                .sectionTitle()

            if appModel.signals.isEmpty {
                if appModel.watchlist.isEmpty {
                    PlaceholderCard(
                        title: "Signals pending",
                        message: "Signals need corroboration. Run another refresh after the first pass so Malcome can compare repeated or cross-source appearances."
                    )
                } else {
                    ForEach(appModel.watchlist.prefix(6)) { candidate in
                        WatchlistRow(candidate: candidate, sourceName: sourceName(for: candidate))
                    }
                }
            } else {
                ForEach(appModel.signals.prefix(8)) { signal in
                    NavigationLink {
                        SignalDetailView(signal: signal)
                    } label: {
                        SignalRow(signal: signal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var signalsSectionTitle: String {
        if appModel.signals.isEmpty, !appModel.watchlist.isEmpty {
            return "Signals to Watch"
        }
        return "Top Emerging Signals"
    }

    private func sourceName(for candidate: WatchlistCandidate) -> String {
        let names = candidate.sourceIDs.compactMap(appModel.sourceName(for:))
        if names.count <= 2 {
            return names.joined(separator: ", ")
        }
        return "\(names.prefix(2).joined(separator: ", ")) + \(names.count - 2) more"
    }

    private var citationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source Evidence")
                .sectionTitle()

            if let brief = appModel.brief, !brief.citationsPayload.isEmpty {
                ForEach(brief.citationsPayload.prefix(6)) { citation in
                    CitationCard(citation: citation)
                }
            } else {
                PlaceholderCard(
                    title: "Evidence cards will land here",
                    message: "The brief stays inspectable: every narrative claim is tied back to concrete observations and outbound links."
                )
            }
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Identity Watchlist")
                .sectionTitle()

            if appModel.ambiguousEntities.isEmpty {
                PlaceholderCard(
                    title: "Identity confidence looks healthy",
                    message: "When Malcome sees risky canonical merges, they’ll appear here so you can inspect them directly."
                )
            } else {
                ForEach(appModel.ambiguousEntities.prefix(3)) { entity in
                    NavigationLink {
                        IdentityReviewView()
                    } label: {
                        IdentityReviewRow(entity: entity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
