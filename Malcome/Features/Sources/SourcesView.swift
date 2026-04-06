import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        List {
            ForEach(groupedStatuses, id: \.moduleID) { group in
                Section {
                    ForEach(group.statuses) { status in
                        SourceStatusRow(status: status) { enabled in
                            Task { await appModel.setSourceEnabled(sourceID: status.source.id, isEnabled: enabled) }
                        }
                    }
                } header: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.moduleName)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(MalcomePalette.primary)
                            Text("\(group.enabledCount)/\(group.statuses.count) enabled")
                                .font(.caption)
                                .foregroundStyle(MalcomePalette.secondary)
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
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [MalcomePalette.backgroundTop, MalcomePalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("Sources")
        .task {
            await appModel.bootstrapIfNeeded()
        }
    }

    private var groupedStatuses: [ModuleStatusGroup] {
        Dictionary(grouping: appModel.sourceStatuses, by: \.source.moduleID)
            .compactMap { moduleID, statuses in
                guard let first = statuses.first else { return nil }
                return ModuleStatusGroup(
                    moduleID: moduleID,
                    moduleName: first.source.moduleName,
                    statuses: statuses.sorted { $0.source.name < $1.source.name }
                )
            }
            .sorted { $0.moduleName < $1.moduleName }
    }
}

private struct ModuleStatusGroup {
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
