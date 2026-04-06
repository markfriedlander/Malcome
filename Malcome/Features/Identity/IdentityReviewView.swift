import SwiftUI

struct IdentityReviewView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Identity Review")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(MalcomePalette.primary)
                    Text("Audit low-confidence canonical entities, risky aliases, and the evidence behind each merge.")
                        .font(.subheadline)
                        .foregroundStyle(MalcomePalette.secondary)
                }
                .cardStyle()

                if !appModel.sourceInfluenceStats.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Learned Source Trust")
                            .sectionTitle()

                        ForEach(appModel.sourceInfluenceStats.prefix(6)) { stat in
                            SourceInfluenceRow(stat: stat)
                        }
                    }
                }

                if appModel.ambiguousEntities.isEmpty {
                    PlaceholderCard(
                        title: "No ambiguous identities right now",
                        message: "Canonical merges are currently above the review threshold. When risky historical clusters show up, they’ll land here."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Watchlist")
                            .sectionTitle()

                        ForEach(appModel.ambiguousEntities) { entity in
                            NavigationLink {
                                IdentityDetailView(entityID: entity.id)
                            } label: {
                                IdentityReviewRow(entity: entity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [MalcomePalette.backgroundTop, MalcomePalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Identity")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct IdentityDetailView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let entityID: String

    @State private var entity: CanonicalEntityRecord?
    @State private var aliases: [EntityAliasRecord] = []
    @State private var roles: [EntitySourceRoleRecord] = []
    @State private var evidence: [ObservationRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let entity {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entity.displayName)
                                    .font(.system(size: 28, weight: .black, design: .rounded))
                                    .foregroundStyle(MalcomePalette.primary)
                                Text("\(entity.domain.label) • \(entity.entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)")
                                    .font(.subheadline)
                                    .foregroundStyle(MalcomePalette.secondary)
                            }
                            Spacer()
                            MergeConfidenceBadge(confidence: entity.mergeConfidence)
                        }
                        Text(entity.mergeSummary)
                            .foregroundStyle(MalcomePalette.secondary)
                    }
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Aliases")
                        .sectionTitle()

                    if aliases.isEmpty {
                        PlaceholderCard(
                            title: "No aliases stored",
                            message: "This identity currently relies on a narrow alias set."
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(aliases) { alias in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(alias.aliasText)
                                        .font(.headline)
                                    Text(alias.normalizedAlias)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let sourceID = alias.sourceID {
                                        Text(appModel.sourceName(for: sourceID))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .cardStyle()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Source Roles")
                        .sectionTitle()

                    if roles.isEmpty {
                        PlaceholderCard(
                            title: "No source-role evidence",
                            message: "Malcome has not yet recorded source-role history for this entity."
                        )
                    } else {
                        ForEach(roles) { role in
                            SourceRoleCard(role: role, sourceName: appModel.sourceName(for: role.sourceID))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Evidence")
                        .sectionTitle()

                    if evidence.isEmpty {
                        PlaceholderCard(
                            title: "No evidence cached",
                            message: "Malcome has not retained local observations for this entity yet."
                        )
                    } else {
                        ForEach(evidence) { observation in
                            ObservationCard(observation: observation, sourceName: appModel.sourceName(for: observation.sourceID))
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [MalcomePalette.backgroundTop, MalcomePalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Identity Audit")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let entityTask = appModel.canonicalEntity(for: entityID)
            async let aliasesTask = appModel.aliases(for: entityID)
            async let rolesTask = appModel.sourceRoles(for: entityID)
            async let evidenceTask = appModel.container.repository.observations(forCanonicalEntityID: entityID, limit: 12)

            entity = await entityTask
            aliases = await aliasesTask
            roles = await rolesTask
            evidence = (try? await evidenceTask) ?? []
        }
    }
}
