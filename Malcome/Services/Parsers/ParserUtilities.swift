import Foundation

/// Shared utility for deduplicating observation drafts by external ID.
/// Used by all parsers after generating draft observations.
nonisolated func dedupeObservationDrafts(_ drafts: [ObservationDraft]) -> [ObservationDraft] {
    var seen = Set<String>()
    var unique: [ObservationDraft] = []
    for draft in drafts where seen.insert(draft.externalIDOrHash).inserted {
        unique.append(draft)
    }
    return unique
}
