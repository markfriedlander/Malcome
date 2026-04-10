import Foundation
import FoundationModels

/// Extracts multiple cultural entities from roundup articles using AFM.
/// Each extracted entity becomes a separate ObservationDraft.
/// Follows the ExcerptDistiller pattern: fresh session per call, discarded immediately.
enum RoundupExtractor {

    struct ExtractedEntity {
        let name: String
        let entityType: EntityType
        let context: String
    }

    private static let maxEntitiesPerRoundup = 8

    private static let extractionPrompt = """
    List the cultural entities (artists, bands, filmmakers, designers, collectives, exhibitions) mentioned in this article. Return JSON only: [{"name":"...","type":"creator","context":"one sentence"}]. Type must be one of: creator, collective, event, venue. Only real cultural entities, not publications, generic terms, or the article author. Maximum 8 entities.

    Title: TITLE_PLACEHOLDER
    Text: EXCERPT_PLACEHOLDER
    """

    /// Extract cultural entities from a roundup article.
    /// Returns an empty array if AFM is unavailable, returns malformed JSON, or no entities are found.
    static func extractEntities(title: String, excerpt: String) async -> [ExtractedEntity] {
        guard SystemLanguageModel.default.isAvailable else { return [] }

        let cappedExcerpt = String(excerpt.prefix(700))
        let prompt = extractionPrompt
            .replacingOccurrences(of: "TITLE_PLACEHOLDER", with: title)
            .replacingOccurrences(of: "EXCERPT_PLACEHOLDER", with: cappedExcerpt)

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return parseEntities(from: text)
        } catch {
            return []
        }
    }

    /// Defensively parse the JSON response from AFM.
    private static func parseEntities(from text: String) -> [ExtractedEntity] {
        // Strip markdown code fences if present (AFM often wraps JSON in ```json ... ```)
        var cleaned = text
        if cleaned.contains("```") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Find the JSON array
        guard let arrayStart = cleaned.firstIndex(of: "["),
              let arrayEnd = cleaned.lastIndex(of: "]") else {
            return []
        }

        let jsonString = String(cleaned[arrayStart...arrayEnd])
        guard let data = jsonString.data(using: .utf8) else { return [] }

        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var entities: [ExtractedEntity] = []
        for item in array.prefix(maxEntitiesPerRoundup) {
            guard let name = item["name"] as? String, !name.isEmpty else { continue }

            let typeString = (item["type"] as? String) ?? "creator"
            let entityType: EntityType
            switch typeString.lowercased() {
            case "creator": entityType = .creator
            case "collective": entityType = .collective
            case "event": entityType = .event
            case "venue": entityType = .venue
            default: entityType = .creator
            }

            let context = (item["context"] as? String) ?? ""

            // Skip entities that look like publication names or generic terms
            let normalized = HTMLSupport.normalizedAlias(name)
            guard HTMLSupport.isMeaningfulEntityName(normalized) else { continue }
            guard !HTMLSupport.isPotentialTitleCollisionAlias(name) else { continue }

            entities.append(ExtractedEntity(
                name: name,
                entityType: entityType,
                context: context
            ))
        }

        return entities
    }

    /// Create ObservationDrafts from extracted entities, using the original article's metadata.
    static func draftsFromExtraction(
        entities: [ExtractedEntity],
        originalTitle: String,
        originalURL: String,
        originalExcerpt: String,
        source: SourceRecord,
        fetchedAt: Date,
        publishedAt: Date?,
        tags: [String]
    ) -> [ObservationDraft] {
        entities.map { entity in
            let entityTags = tags.filter { $0 != "roundup" } + ["extracted_from_roundup"]
            let excerpt = entity.context.isEmpty
                ? "Mentioned in: \(originalTitle)"
                : entity.context

            // Use an anchor fragment in the URL so deduplication doesn't collide with the original article
            let entityAnchor = entity.name.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? entity.name
            let entityURL = "\(originalURL)#entity-\(entityAnchor)"

            return ObservationDraft(
                domain: source.domain,
                entityType: entity.entityType,
                externalIDOrHash: HTMLSupport.hash(entityURL),
                title: entity.name,
                subtitle: source.name,
                url: entityURL,
                authorOrArtist: entity.name,
                tags: entityTags,
                location: source.city == .global ? nil : source.city.displayName,
                publishedAt: publishedAt,
                scrapedAt: fetchedAt,
                excerpt: excerpt,
                normalizedEntityName: HTMLSupport.normalizedEntityName(
                    title: entity.name,
                    author: entity.name,
                    fallbackURL: originalURL
                ),
                rawPayload: "{\"extracted_from\":\"\(originalURL)\",\"entity\":\"\(entity.name)\"}"
            )
        }
    }
}
