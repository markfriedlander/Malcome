import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        List {
            Section("Sources") {
                ForEach(groupedStatuses, id: \.moduleID) { group in
                    DisclosureGroup {
                        ForEach(group.statuses) { status in
                            SourceSettingsRow(status: status) { enabled in
                                Task { await appModel.setSourceEnabled(sourceID: status.source.id, isEnabled: enabled) }
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.moduleName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MalcomePalette.primary)
                                Text("\(group.enabledCount)/\(group.statuses.count) enabled")
                                    .font(.caption2)
                                    .foregroundStyle(MalcomePalette.tertiary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { group.isAnyEnabled },
                                set: { enabled in
                                    Task { await appModel.setModuleEnabled(moduleID: group.moduleID, isEnabled: enabled) }
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            }

            Section("How Malcome Works") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("I watch a curated network of sources — the kinds of places that tend to notice things early. Record shops, not Billboard. College radio, not Spotify charts. The publications, platforms, and venues where cultural movement shows up before mainstream consensus forms.")
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.secondary)

                    Text("When I see the same name surface across genuinely independent sources — sources that are not talking to each other — I treat that as a signal. One source noticing something is a curiosity. Two independent sources arriving at the same conclusion is a pattern worth paying attention to.")
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.secondary)

                    Text("The watchlist is where names sit before they become signals. They have appeared somewhere interesting, but they have not crossed the corroboration line yet. I keep them visible because the best time to know a name is before everyone else figures it out.")
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    Task { await appModel.forceRefresh() }
                } label: {
                    HStack {
                        Text("Refresh now")
                            .foregroundStyle(Color.orange)
                        Spacer()
                        if appModel.isRefreshing {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(appModel.isRefreshing)
            }

            Section("About") {
                HStack {
                    Text("Last refresh")
                        .foregroundStyle(MalcomePalette.secondary)
                    Spacer()
                    Text(appModel.lastRefreshAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
                        .foregroundStyle(MalcomePalette.tertiary)
                }
                if let summary = appModel.refreshSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.tertiary)
                }
                if let warning = appModel.refreshWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.yellow.opacity(0.8))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [MalcomePalette.backgroundTop, MalcomePalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("Settings")
        .task {
            await appModel.bootstrapIfNeeded()
        }
    }

    private var groupedStatuses: [SettingsModuleGroup] {
        Dictionary(grouping: appModel.sourceStatuses, by: \.source.moduleID)
            .compactMap { moduleID, statuses in
                guard let first = statuses.first else { return nil }
                return SettingsModuleGroup(
                    moduleID: moduleID,
                    moduleName: first.source.moduleName,
                    statuses: statuses.sorted { $0.source.name < $1.source.name }
                )
            }
            .sorted { $0.moduleName < $1.moduleName }
    }
}

private struct SettingsModuleGroup {
    let moduleID: String
    let moduleName: String
    let statuses: [SourceStatusRecord]

    var enabledCount: Int {
        statuses.filter { $0.source.enabled }.count
    }

    var isAnyEnabled: Bool {
        enabledCount > 0
    }
}

// MARK: - Source Settings Row

struct SourceSettingsRow: View {
    let status: SourceStatusRecord
    let onToggle: (Bool) -> Void
    @State private var showDoctrine = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.source.name)
                        .font(.subheadline)
                        .foregroundStyle(MalcomePalette.primary)

                    HStack(spacing: 6) {
                        Text(status.source.tier.label)
                            .font(.caption2)
                            .foregroundStyle(MalcomePalette.tertiary)
                        Text(status.source.classification.label)
                            .font(.caption2)
                            .foregroundStyle(MalcomePalette.tertiary)
                        if let snapshot = status.latestSnapshot {
                            Text(snapshot.status.rawValue)
                                .font(.caption2)
                                .foregroundStyle(snapshotColor(snapshot.status))
                        }
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { status.source.enabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
            }

            // Collapsed doctrine profile
            if showDoctrine {
                VStack(alignment: .leading, spacing: 4) {
                    doctrineField("Why early", text: status.source.doctrineProfile.whyEarly)
                    doctrineField("Why selective", text: status.source.doctrineProfile.whySelective)
                    doctrineField("Corroboration role", text: status.source.doctrineProfile.corroborationRole)
                }
                .padding(.top, 4)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDoctrine.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showDoctrine ? "chevron.up" : "chevron.down")
                    Text(showDoctrine ? "Hide doctrine" : "Source doctrine")
                }
                .font(.caption2)
                .foregroundStyle(MalcomePalette.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func doctrineField(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(MalcomePalette.secondary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(MalcomePalette.tertiary)
        }
    }

    private func snapshotColor(_ status: SnapshotStatus) -> Color {
        switch status {
        case .success: return .green
        case .failed: return .red
        case .skipped: return .yellow
        case .running: return .blue
        }
    }
}
