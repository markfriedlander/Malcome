import Foundation
import FoundationModels

// MARK: - Heuristic Caps

enum BriefCaps {
    static let maxSignals = 3
    static let maxWatchlistItems = 4
    static let maxObservationsPerSignal = 2
    static let maxSourceNamesPerSignal = 3
    static let maxSourceNamesTotal = 8
    static let maxEvidenceSummaryChars = 200
    static let maxMovementSummaryChars = 150
    static let maxSourceInfluenceSummaryChars = 150
    static let maxWhyNowChars = 200
    static let maxUpgradeTriggerChars = 150
    static let maxInfluenceHighlights = 2
}

// MARK: - MalcomeBriefGenerator

struct MalcomeBriefGenerator: BriefGenerating {

    private static let polishPrompt = """
    Lightly edit the text below for natural flow. Change as little as possible. Keep the first-person voice, the short sentences, and the calm tone exactly as they are. Keep all citation markers like [1] and [2] exactly where they are. Do not add new words like "standout", "intriguing", "promising", "traction", "waves", "buzzing", "exciting", or "undeniable." Output the edited text only, nothing else.

    TEXT:
    """

    func generateBrief(from input: BriefingInput) async throws -> BriefRecord {
        let capped = capInput(input)
        // Pass observation and near-miss context for empty state messages
        let totalObs = input.signals.reduce(0) { $0 + $1.signal.observationCount }
            + input.watchlistCandidates.reduce(0) { $0 + $1.observationCount }
        let nearMisses = input.watchlistCandidates.filter { $0.sourceFamilyCount == 1 && $0.observationCount >= 2 }.count
        let draftResult = await DraftComposer.compose(from: capped, observationCount: max(totalObs, 100), nearMissCount: nearMisses)
        // Skip AFM polish for empty/thin states — the draft is already the final text
        let body = draftResult.sourceReferences.isEmpty
            ? draftResult.text
            : await polishWithAFM(draftResult.text)
        let title = await briefTitle(from: capped, briefBody: body)

        let citations = draftResult.sourceReferences.enumerated().map { index, ref in
            BriefCitation(
                id: "cite-\(index)",
                signalName: "",
                sourceName: ref.sourceName,
                observationTitle: ref.observationTitle,
                url: ref.url,
                note: ref.excerpt
            )
        }

        return BriefRecord(
            id: UUID().uuidString,
            generatedAt: input.generatedAt,
            title: title,
            body: body,
            citationsPayload: citations,
            periodType: .daily
        )
    }

    // MARK: - Capping

    private func capInput(_ input: BriefingInput) -> BriefingInput {
        let cappedSignals = input.signals.prefix(BriefCaps.maxSignals).map { packet in
            BriefingInput.SignalPacket(
                signal: packet.signal,
                observations: Array(packet.observations.prefix(BriefCaps.maxObservationsPerSignal)),
                sourceNames: Array(packet.sourceNames.prefix(BriefCaps.maxSourceNamesPerSignal)),
                priorMentions: packet.priorMentions,
                recentMentions: packet.recentMentions
            )
        }

        let cappedWatchlist = Array(input.watchlistCandidates.prefix(BriefCaps.maxWatchlistItems))
        let cappedHighlights = Array(input.sourceInfluenceHighlights.prefix(BriefCaps.maxInfluenceHighlights))

        return BriefingInput(
            generatedAt: input.generatedAt,
            signals: Array(cappedSignals),
            watchlistCandidates: cappedWatchlist,
            domainMix: input.domainMix,
            sourceInfluenceHighlights: cappedHighlights
        )
    }

    // MARK: - AFM Polish

    private func polishWithAFM(_ draft: String) async -> String {
        guard SystemLanguageModel.default.isAvailable else {
            return draft
        }

        let prompt = Self.polishPrompt + "\n" + draft

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let polished = response.content
            if polished.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return draft
            }
            return polished
        } catch {
            return draft
        }
    }

    // MARK: - Title

    private func briefTitle(from input: BriefingInput, briefBody: String) async -> String {
        if let lead = input.signals.first {
            if let afmTitle = await generateTitle(leadName: lead.signal.canonicalName, movement: lead.signal.movement, domain: lead.signal.domain) {
                return afmTitle
            }
            return templateTitle(leadName: lead.signal.canonicalName, movement: lead.signal.movement)
        }
        if let lead = input.watchlistCandidates.first {
            return "Watching \(lead.title)"
        }
        return "Malcome Radar"
    }

    private func generateTitle(leadName: String, movement: SignalMovement, domain: CulturalDomain) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let movementHint: String
        switch movement {
        case .new: movementHint = "just appeared on the radar"
        case .rising: movementHint = "is building momentum"
        case .stable: movementHint = "keeps showing up consistently"
        case .declining: movementHint = "is losing momentum"
        }

        let prompt = "Write a title for a cultural brief. Maximum 6 words. Calm and specific. No adjectives like 'sonic', 'remarkable', 'cultural'. No words like 'phenomenon', 'renaissance', 'unfolds', 'journey', 'explores'. Just say what is happening. Example: 'Thundercat Is Moving Again'. Subject: \(leadName) \(movementHint) in \(domain.label.lowercased()). Title:"

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let title = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "\n", with: " ")
            let wordCount = title.split(separator: " ").count
            if title.count >= 5 && title.count <= 60 && wordCount <= 8 {
                return title
            }
        } catch {}

        return nil
    }

    private func templateTitle(leadName: String, movement: SignalMovement) -> String {
        switch movement {
        case .new: return "\(leadName) Just Showed Up"
        case .rising: return "\(leadName) Is Building"
        case .stable: return "The Scene Keeps Noticing \(leadName)"
        case .declining: return "\(leadName) Is Cooling"
        }
    }

    // Citations are now built from DraftResult.sourceReferences in generateBrief()
}

// MARK: - Draft Result

struct DraftResult {
    let text: String
    let sourceReferences: [SourceReference]

    struct SourceReference {
        let sourceName: String
        let observationTitle: String
        let url: String
        let excerpt: String
    }
}

// MARK: - DraftComposer

enum DraftComposer {

    /// Tracks used phrases within a single brief to prevent repetition.
    private static var usedPhrases: Set<String> = []

    private static func pickPhrase(from variants: [String]) -> String {
        if let unused = variants.first(where: { !usedPhrases.contains($0) }) {
            usedPhrases.insert(unused)
            return unused
        }
        return variants.first ?? ""
    }

    static func compose(from input: BriefingInput, observationCount: Int = 0, nearMissCount: Int = 0) async -> DraftResult {
        usedPhrases.removeAll()
        var tracker = SourceTracker()
        let text: String
        if input.signals.isEmpty && input.watchlistCandidates.isEmpty {
            text = composeEmptyState(observationCount: observationCount, nearMissCount: nearMissCount)
        } else if input.signals.isEmpty {
            text = composeWatchlistOnly(input, tracker: &tracker)
        } else {
            text = await composeFullBrief(input, tracker: &tracker)
        }
        return DraftResult(text: text, sourceReferences: tracker.references)
    }

    private struct SourceTracker {
        private(set) var references: [DraftResult.SourceReference] = []
        private var seenURLs: Set<String> = []
        private var seenSourceNames: [String: Int] = [:]  // sourceName → citation index

        mutating func cite(sourceName: String, observation: ObservationRecord?) -> String {
            // Deduplicate by source name across the full brief
            if let existingIndex = seenSourceNames[sourceName] {
                return "[\(existingIndex)]"
            }

            let url = observation?.url ?? ""
            if !url.isEmpty, seenURLs.contains(url) {
                if let idx = references.firstIndex(where: { $0.url == url }) {
                    seenSourceNames[sourceName] = idx + 1
                    return "[\(idx + 1)]"
                }
            }

            let ref = DraftResult.SourceReference(
                sourceName: sourceName,
                observationTitle: observation?.title ?? "",
                url: url,
                excerpt: observation?.distilledExcerpt ?? observation?.excerpt ?? ""
            )
            references.append(ref)
            if !url.isEmpty { seenURLs.insert(url) }
            let index = references.count
            seenSourceNames[sourceName] = index
            return "[\(index)]"
        }
    }

    // This old signature is replaced by compose(from:) -> DraftResult above

    // MARK: - Full Brief (signals + watchlist)

    private static func composeFullBrief(_ input: BriefingInput, tracker: inout SourceTracker) async -> String {
        var paragraphs: [String] = []

        let currentSignals = input.signals.filter { $0.signal.signalTier == .current }
        let historicalSignals = input.signals.filter { $0.signal.signalTier == .historical }

        // Tier 1: current signals lead the brief
        if let lead = currentSignals.first {
            paragraphs.append(await composeLeadSignal(lead, tracker: &tracker))
        }
        for packet in currentSignals.dropFirst() {
            paragraphs.append(await composeSecondarySignal(packet, tracker: &tracker))
        }

        // Tier 2: historical signals — "I've been sitting on this"
        if !historicalSignals.isEmpty {
            if !paragraphs.isEmpty {
                paragraphs[paragraphs.count - 1] += " There is also something I have been sitting on."
            }
            for packet in historicalSignals {
                let name = packet.signal.canonicalName
                let domain = packet.signal.domain.label.lowercased()
                let sources = packet.sourceNames.prefix(3).joined(separator: " and ")
                paragraphs.append("\(name) has been building quietly in \(domain). I have been watching this for a while — \(sources) have both noticed independently, and the pattern has held. This is not new news, but it is durable, which is often more interesting.")
            }
        }

        // If no current signals at all, use historical as lead
        if currentSignals.isEmpty, let lead = historicalSignals.first, paragraphs.isEmpty {
            paragraphs.append(await composeLeadSignal(lead, tracker: &tracker))
            for packet in historicalSignals.dropFirst() {
                paragraphs.append(await composeSecondarySignal(packet, tracker: &tracker))
            }
        }

        // Watchlist
        if !input.watchlistCandidates.isEmpty {
            if !paragraphs.isEmpty {
                paragraphs[paragraphs.count - 1] += " The rest of today's radar is earlier — names that are showing up but have not crossed the corroboration line yet."
            }
            paragraphs.append(composeWatchlistParagraph(input.watchlistCandidates))
        } else if input.signals.count == 1 {
            let lead = input.signals[0]
            let domain = lead.signal.domain.label.lowercased()
            if lead.recentMentions > 0 && lead.priorMentions > 0 {
                paragraphs.append("This is not a one-off sighting. The current evidence is fresh, but there is stored history behind it too. That combination — live corroboration plus a prior track record — is what separates a real signal from noise.")
            } else {
                paragraphs.append("The \(domain) radar is thin right now. One signal does not make a pattern. But when the corroboration is this clean, it is worth leading with even if the rest of the surface is still quiet.")
            }
        }

        if let highlight = input.sourceInfluenceHighlights.first {
            let lastIndex = paragraphs.count - 1
            if lastIndex >= 0 {
                paragraphs[lastIndex] += " " + cleanEvidence(highlight)
            }
        }

        return paragraphs.joined(separator: "\n\n")
    }

    // MARK: - Lead Signal

    private static func composeLeadSignal(_ packet: BriefingInput.SignalPacket, tracker: inout SourceTracker) async -> String {
        let name = packet.signal.canonicalName
        let sources = packet.sourceNames
        let domain = packet.signal.domain.label.lowercased()
        let entityType = packet.signal.entityType

        // Wikipedia context first, then distilled excerpt, then entity type phrase
        let wikiContext = await wikiContextPhrase(for: name)
        let excerptContext = bestExcerptContext(from: packet.observations)

        var sentences: [String] = []

        if let wiki = wikiContext {
            // Weave Wikipedia context into the opening: "Flying Lotus — producer, rapper out of LA —"
            sentences.append("\(name) — \(wiki) — is the one right now.")
        } else {
            sentences.append("\(name) is the one right now.")
            if let context = excerptContext {
                sentences.append(context)
            } else {
                let typePhrase = entityTypePhrase(entityType)
                if !typePhrase.isEmpty {
                    sentences.append(typePhrase)
                }
            }
        }

        // Build source list with inline citations — pair each source with its observation
        let citedSources = sources.prefix(3).enumerated().map { index, sourceName -> String in
            let obs = index < packet.observations.count ? packet.observations[index] : packet.observations.first
            let marker = tracker.cite(sourceName: sourceName, observation: obs)
            return "\(sourceName)\(marker)"
        }

        if citedSources.count >= 3 {
            let sourceList = citedSources.joined(separator: ", ")
            sentences.append("When \(sourceList) are all noticing the same name independently across different parts of the \(domain) surface, that kind of agreement is hard to fake.")
        } else if citedSources.count == 2 {
            let sourceList = citedSources.joined(separator: " and ")
            sentences.append("\(sourceList) are both picking up on this independently — two different lanes in \(domain) arriving at the same conclusion.")
        } else if let source = citedSources.first {
            sentences.append("The signal is coming through \(source), which has a track record of being right early in \(domain).")
        }

        return sentences.joined(separator: " ")
    }

    // MARK: - Secondary Signals

    private static func composeSecondarySignal(_ packet: BriefingInput.SignalPacket, tracker: inout SourceTracker) async -> String {
        let name = packet.signal.canonicalName
        let sources = packet.sourceNames
        let domain = packet.signal.domain.label.lowercased()
        let movement = packet.signal.movement
        let wikiContext = await wikiContextPhrase(for: name)
        let context = wikiContext ?? bestExcerptContext(from: packet.observations)

        let citedSources = sources.prefix(3).enumerated().map { index, sourceName -> String in
            let obs = index < packet.observations.count ? packet.observations[index] : packet.observations.first
            let marker = tracker.cite(sourceName: sourceName, observation: obs)
            return "\(sourceName)\(marker)"
        }

        var sentences: [String] = []

        switch movement {
        case .new:
            sentences.append("\(name) caught my attention for a different reason.")
            if let context {
                sentences.append(context)
            }
            if citedSources.count >= 2 {
                let sourceList = citedSources.joined(separator: " and ")
                sentences.append("\(sourceList) — both picking up the same name in the same cycle. I have learned to pay attention when that happens in \(domain).")
            }

        case .rising:
            sentences.append("\(name) has been building.")
            if let context {
                sentences.append(context)
            }
            if citedSources.count >= 2 {
                sentences.append("The support is coming from \(citedSources.joined(separator: " and ")), which is the right kind of spread across \(domain).")
            }

        case .stable:
            sentences.append("\(name) is still here.")
            if let context {
                sentences.append(context)
            }
            sentences.append(pickPhrase(from: [
                "Consistency at this stage in \(domain) usually means something real underneath.",
                "When something keeps showing up in \(domain) without fading, that tells me it has weight.",
                "The fact that \(domain) sources keep returning to this is worth paying attention to.",
                "Staying power at this stage in \(domain) is more interesting than a loud entrance.",
            ]))

        case .declining:
            sentences.append("I had \(name) on the radar last cycle.")
            sentences.append("The pattern has thinned out — fewer sources, less independent agreement.")
            sentences.append("It has not disappeared but the momentum that put it here is not holding. I am keeping it in view but not leading with it.")
        }

        return sentences.joined(separator: " ")
    }

    // MARK: - Watchlist Paragraph

    private static func composeWatchlistParagraph(_ candidates: [WatchlistCandidate]) -> String {
        var parts: [String] = []

        for (index, candidate) in candidates.enumerated() {
            let name = candidate.title
            let domain = candidate.domain.label.lowercased()
            let whyNow = cleanEvidence(MalcomeTokenEstimator.truncateAtSentenceBoundary(
                candidate.whyNow, maxChars: BriefCaps.maxWhyNowChars
            ))

            switch candidate.stage {
            case .corroborating:
                if index == 0 {
                    parts.append("\(name) keeps turning up across different \(domain) lanes, which is the right kind of pattern.")
                } else {
                    parts.append("\(name) is corroborating across \(candidate.sourceFamilyCount) independent source families in \(domain).")
                }
                parts.append("One more independent confirmation and this moves from watch to signal.")

            case .forming:
                parts.append("\(name) keeps showing up in \(domain) but only in \(candidate.sourceFamilyCount) lane\(candidate.sourceFamilyCount == 1 ? "" : "s") so far.")
                if !whyNow.isEmpty {
                    parts.append(whyNow)
                }

            case .early:
                if index == candidates.count - 1 || candidates.count <= 2 {
                    parts.append("And I want you to know the name \(name).")
                } else {
                    parts.append("\(name) just registered for the first time in \(domain).")
                }
                if !whyNow.isEmpty {
                    parts.append(whyNow)
                } else {
                    parts.append("Too early to call but I am paying attention.")
                }
            }
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Watchlist-Only Brief

    private static func composeWatchlistOnly(_ input: BriefingInput, tracker: inout SourceTracker) -> String {
        if input.watchlistCandidates.isEmpty {
            return composeEmptyState()
        }

        var paragraphs: [String] = []

        let domainPhrase = input.domainMix.isEmpty
            ? "today's source mix"
            : input.domainMix.joined(separator: " and ").lowercased()

        paragraphs.append("No name has crossed the corroboration line yet, but I have been watching the \(domainPhrase) surface and there are patterns forming.")

        paragraphs.append(composeWatchlistParagraph(input.watchlistCandidates))

        paragraphs.append("None of this is a signal yet. That is the honest read. But these are the names I would want to know if I were you, and I will tell you the moment one of them breaks through.")

        if let highlight = input.sourceInfluenceHighlights.first {
            paragraphs[paragraphs.count - 1] += " " + cleanEvidence(highlight)
        }

        return paragraphs.joined(separator: "\n\n")
    }

    // MARK: - Empty State

    private static func composeEmptyState() -> String {
        composeEmptyState(observationCount: 0, nearMissCount: 0)
    }

    static func composeEmptyState(observationCount: Int, nearMissCount: Int) -> String {
        if nearMissCount > 0 {
            // Level 3: something is close
            let messages = [
                "Something is almost there. I can feel it forming but I will not say the name until I am sure.",
                "A couple of things are close. Give it another cycle.",
                "I have got names I am sitting on. Not ready yet.",
                "Something is building. Check back tomorrow.",
            ]
            return messages.randomElement()!
        }

        if observationCount >= 100 {
            // Level 2: data exists but nothing crossed
            let messages = [
                "Quiet out there right now. Things are moving but nothing has crossed the line yet.",
                "Nothing I am ready to call. That is not nothing — it means the scene is between moments.",
                "I am watching a few things. Not ready to say the names yet.",
                "The scene is between moments. Give it another day.",
            ]
            return messages.randomElement()!
        }

        // Level 1: genuinely sparse
        let messages = [
            "Still getting my bearings. Give me a few more days.",
            "The network is warming up. Check back soon.",
        ]
        return messages.randomElement()!
    }

    // MARK: - Wikipedia Context

    /// Fetches Wikipedia context and extracts a concise descriptive phrase.
    /// "Flying Lotus, born Steven Ellison, is an American musician..." → "producer, rapper, filmmaker out of Los Angeles"
    private static func wikiContextPhrase(for entityName: String) async -> String? {
        guard let summary = await WikipediaClient.contextSummary(for: entityName) else { return nil }

        let firstSentence = summary.firstSentence
        guard !firstSentence.isEmpty else { return nil }

        // Try to extract the descriptive part after "is a/an"
        let patterns = [
            #"(?:is|was) (?:an? )(.+?)(?:\.|$)"#,
            #"(?:are|were) (?:an? )(.+?)(?:\.|$)"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: firstSentence, range: NSRange(firstSentence.startIndex..., in: firstSentence)),
               let range = Range(match.range(at: 1), in: firstSentence) {
                let descriptor = String(firstSentence[range]).trimmingCharacters(in: .whitespaces)
                if descriptor.count >= 5 && descriptor.count <= 200 {
                    return MalcomeTokenEstimator.truncateAtSentenceBoundary(descriptor, maxChars: 120)
                }
            }
        }

        // Fallback: use the first sentence as-is if short enough
        if firstSentence.count <= 150 {
            return firstSentence
        }

        return nil
    }

    // MARK: - Excerpt Context

    private static func bestExcerptContext(from observations: [ObservationRecord]) -> String? {
        let entityName = observations.first?.authorOrArtist ?? observations.first?.normalizedEntityName ?? ""

        // Sort observations: editorial sources first, then discovery/platform
        let sorted = observations.sorted { a, b in
            let aEditorial = a.tags.contains("editorial")
            let bEditorial = b.tags.contains("editorial")
            if aEditorial != bEditorial { return aEditorial }
            return false
        }

        // Prefer distilled excerpts from editorial sources first
        for obs in sorted {
            if let distilled = obs.distilledExcerpt, !distilled.isEmpty {
                let cleaned = cleanEvidence(distilled)
                if cleaned.count >= 20, !isBandcampMetadata(cleaned) {
                    return MalcomeTokenEstimator.truncateAtSentenceBoundary(cleaned, maxChars: 200)
                }
            }
        }

        // Fall back to cleaned raw excerpts
        let candidates: [(String, Bool)] = sorted.compactMap { obs in
            guard let excerpt = obs.excerpt else { return nil }
            let cleaned = cleanExcerptForBrief(excerpt, entityName: entityName)
            if cleaned.count < 25 { return nil }
            if isBandcampMetadata(cleaned) { return nil }
            let mentionsEntity = !entityName.isEmpty && cleaned.localizedCaseInsensitiveContains(entityName)
            return (cleaned, mentionsEntity)
        }

        // Prefer sentences that mention the entity name — those give specific context
        if let entitySpecific = candidates.first(where: { $0.1 }) {
            return MalcomeTokenEstimator.truncateAtSentenceBoundary(entitySpecific.0, maxChars: 200)
        }

        // Fall back to any non-generic excerpt
        if let fallback = candidates.first(where: { !isGenericEditorialObservation($0.0) }) {
            return MalcomeTokenEstimator.truncateAtSentenceBoundary(fallback.0, maxChars: 200)
        }

        // No excerpt is better than a misleading one
        return nil
    }

    private static func cleanExcerptForBrief(_ text: String, entityName: String) -> String {
        var cleaned = cleanEvidence(text)

        // Skip trivial placeholders
        if cleaned.hasPrefix("Surfacing on ") { return "" }

        // Strip leading "Title by Artist" caption patterns (common in RSS descriptions)
        // Pattern: "TITLE by ARTIST rest of text..." or "TITLE — ARTIST rest of text..."
        let captionPatterns = [
            #"^.{1,80}\s+by\s+.{1,80}\s+"#,
            #"^.{1,80}\s+[–—-]\s+.{1,80}\s+"#,
        ]
        for pattern in captionPatterns {
            if let range = cleaned.range(of: pattern, options: .regularExpression) {
                let remainder = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                // Only strip if there's meaningful text after the caption
                if remainder.count > 30 {
                    cleaned = remainder
                    break
                }
            }
        }

        // Find first natural sentence boundary if text starts mid-sentence
        if let firstChar = cleaned.first, firstChar.isLowercase {
            // Starts with lowercase — likely mid-sentence from a truncated description
            if let sentenceStart = cleaned.range(of: #"\.\s+[A-Z]"#, options: .regularExpression) {
                let afterPeriod = cleaned[sentenceStart.upperBound...]
                if afterPeriod.count > 30 {
                    // Back up to include the capital letter
                    let startIndex = cleaned.index(before: sentenceStart.upperBound)
                    cleaned = String(cleaned[startIndex...])
                }
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detects Bandcamp structural metadata that shouldn't be used as brief context.
    private static func isBandcampMetadata(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Pattern: short text ending with city/state/country (Bandcamp location metadata)
        let locationPatterns = [
            #"(?i),\s*(california|new york|los angeles|london|berlin|tokyo|portland|seattle|brooklyn|chicago|austin)"#,
            #"(?i),\s*[a-z]+\s*$"#,  // Ends with ", CityName"
        ]
        // Very short with location = metadata, not context
        if text.count < 60 {
            for pattern in locationPatterns {
                if lower.range(of: pattern, options: .regularExpression) != nil { return true }
            }
        }
        // "Surfacing on" placeholders
        if lower.hasPrefix("surfacing on ") { return true }
        return false
    }

    private static func isGenericEditorialObservation(_ text: String) -> Bool {
        // Reject sentences that are purely generic observations with no entity-specific content
        let genericPatterns = [
            #"(?i)^as a (medium|genre|format|form)"#,
            #"(?i)^(the|this) (genre|medium|format|scene|industry)"#,
            #"(?i)^in (recent|the past|today's)"#,
            #"(?i)^(music|art|film|fashion|design) (has|is|continues)"#,
        ]
        return genericPatterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func entityTypePhrase(_ entityType: EntityType) -> String {
        switch entityType {
        case .creator: return ""  // Most common, no extra context needed
        case .collective: return "This is a collective, not a solo act — which makes the independent attention more notable."
        case .venue: return "A venue showing up as a signal usually means the room itself is becoming a cultural node."
        case .event, .eventSeries: return "This is an event pattern, not just a name — which means the scene is organizing around something."
        case .publication: return ""
        case .organization, .brand: return ""
        case .scene: return "This is a scene-level pattern, not a single artist — which usually means the movement is broader than any one name."
        case .concept: return ""
        case .unknown: return ""
        }
    }

    // MARK: - Evidence Cleaning

    static func cleanEvidence(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip all bullet characters (leading and embedded)
        cleaned = cleaned.replacingOccurrences(of: "• ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "•", with: "")
        // Strip leading dash/asterisk bullets
        while cleaned.hasPrefix("- ") || cleaned.hasPrefix("* ") {
            cleaned = String(cleaned.dropFirst(2))
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
