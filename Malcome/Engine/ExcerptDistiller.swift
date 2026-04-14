import Foundation
import FoundationModels

/// Distills raw observation excerpts into entity-specific one-sentence context using AFM.
/// Each distillation uses a fresh LanguageModelSession, used once, discarded immediately.
enum ExcerptDistiller {

    private static let distillPrompt = """
    Extract the single most informative sentence about the named entity from the text below. The sentence must be about this specific entity and must describe something current or recent about them. No historical quotes about other people. No generic observations. One sentence only. If the text contains nothing specific and current about the entity, respond with just "NONE".

    Entity: ENTITY_NAME
    Text: EXCERPT_TEXT
    """

    /// Distill excerpts for observations that have raw excerpts but no distilled excerpt.
    /// Skips observations that already have distilled excerpts or have no raw excerpt.
    static func distillNewObservations(
        observations: [ObservationRecord],
        repository: AppRepository
    ) async {
        guard SystemLanguageModel.default.isAvailable else { return }

        let needsDistillation = observations.filter { obs in
            obs.distilledExcerpt == nil
                && obs.excerpt != nil
                && !obs.excerpt!.isEmpty
                && !obs.excerpt!.hasPrefix("Surfacing on ")
        }

        // Cap to avoid long ingest delays — distill the most recent observations first
        let batch = needsDistillation.prefix(30)

        for observation in batch {
            guard let excerpt = observation.excerpt else { continue }
            let entityName = observation.authorOrArtist ?? observation.normalizedEntityName

            let prompt = distillPrompt
                .replacingOccurrences(of: "ENTITY_NAME", with: entityName)
                .replacingOccurrences(of: "EXCERPT_TEXT", with: String(excerpt.prefix(500)))

            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                let distilled = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

                if !distilled.isEmpty && distilled != "NONE" && distilled.count > 10 {
                    try await repository.updateDistilledExcerpt(
                        observationID: observation.id,
                        distilledExcerpt: distilled
                    )
                }
            } catch {
                // AFM failure at ingest is not critical — skip and continue
                continue
            }
        }
    }
}
