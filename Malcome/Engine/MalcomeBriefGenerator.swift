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
    Lightly edit the text below for natural flow. Change as little as possible. Keep the first-person voice, the short sentences, and the calm tone exactly as they are. Do not add new words like "standout", "intriguing", "promising", "traction", "waves", "buzzing", "exciting", or "undeniable." Output the edited text only, nothing else.

    TEXT:
    """

    func generateBrief(from input: BriefingInput) async throws -> BriefRecord {
        let capped = capInput(input)
        let draft = DraftComposer.compose(from: capped)
        let body = await polishWithAFM(draft)
        let title = briefTitle(from: capped)

        let citations = buildCitations(from: capped)

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

    private func briefTitle(from input: BriefingInput) -> String {
        if let lead = input.signals.first {
            return "\(lead.signal.canonicalName) and the Cultural Current"
        }
        if let lead = input.watchlistCandidates.first {
            return "Watching \(lead.title)"
        }
        return "Malcome Radar"
    }

    // MARK: - Citations

    private func buildCitations(from input: BriefingInput) -> [BriefCitation] {
        var citations: [BriefCitation] = []

        for packet in input.signals {
            for (index, observation) in packet.observations.prefix(2).enumerated() {
                citations.append(BriefCitation(
                    id: "\(packet.signal.id)-\(index)",
                    signalName: packet.signal.canonicalName,
                    sourceName: packet.sourceNames.first ?? "Unknown Source",
                    observationTitle: observation.title,
                    url: observation.url,
                    note: observation.excerpt ?? "Observed during the latest refresh."
                ))
            }
        }

        for (index, candidate) in input.watchlistCandidates.enumerated() {
            citations.append(BriefCitation(
                id: "watch-\(index)",
                signalName: "watchlist",
                sourceName: candidate.sourceIDs.first ?? "Unknown Source",
                observationTitle: candidate.title,
                url: "",
                note: candidate.whyNow
            ))
        }

        return citations
    }
}

// MARK: - DraftComposer

enum DraftComposer {

    static func compose(from input: BriefingInput) -> String {
        if input.signals.isEmpty && input.watchlistCandidates.isEmpty {
            return composeEmptyState()
        }

        if input.signals.isEmpty {
            return composeWatchlistOnly(input)
        }

        return composeFullBrief(input)
    }

    // MARK: - Full Brief (signals + watchlist)

    private static func composeFullBrief(_ input: BriefingInput) -> String {
        var paragraphs: [String] = []

        if let lead = input.signals.first {
            paragraphs.append(composeLeadSignal(lead))
        }

        for packet in input.signals.dropFirst() {
            paragraphs.append(composeSecondarySignal(packet))
        }

        if !input.watchlistCandidates.isEmpty {
            if !paragraphs.isEmpty {
                paragraphs[paragraphs.count - 1] += " The rest of today's radar is earlier — names that are showing up but have not crossed the corroboration line yet."
            }
            paragraphs.append(composeWatchlistParagraph(input.watchlistCandidates))
        } else if input.signals.count == 1 {
            // Thin-data case: only one signal, no watchlist. Expand the read.
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

    private static func composeLeadSignal(_ packet: BriefingInput.SignalPacket) -> String {
        let name = packet.signal.canonicalName
        let sources = packet.sourceNames
        let domain = packet.signal.domain.label.lowercased()
        let entityType = packet.signal.entityType
        let context = bestExcerptContext(from: packet.observations)

        var sentences: [String] = []
        sentences.append("\(name) is the one right now.")

        // Add entity type and excerpt context so the reader knows what this is
        if let context {
            sentences.append(context)
        } else {
            let typePhrase = entityTypePhrase(entityType)
            if !typePhrase.isEmpty {
                sentences.append(typePhrase)
            }
        }

        if sources.count >= 3 {
            let sourceList = sources.prefix(3).joined(separator: ", ")
            sentences.append("When \(sourceList) are all noticing the same name independently across different parts of the \(domain) surface, that kind of agreement is hard to fake.")
        } else if sources.count == 2 {
            let sourceList = sources.joined(separator: " and ")
            sentences.append("\(sourceList) are both picking up on this independently — two different lanes in \(domain) arriving at the same conclusion.")
        } else if let source = sources.first {
            sentences.append("The signal is coming through \(source), which has a track record of being right early in \(domain).")
        }

        return sentences.joined(separator: " ")
    }

    // MARK: - Secondary Signals

    private static func composeSecondarySignal(_ packet: BriefingInput.SignalPacket) -> String {
        let name = packet.signal.canonicalName
        let sources = packet.sourceNames
        let domain = packet.signal.domain.label.lowercased()
        let movement = packet.signal.movement
        let context = bestExcerptContext(from: packet.observations)

        var sentences: [String] = []

        switch movement {
        case .new:
            sentences.append("\(name) caught my attention for a different reason.")
            if let context {
                sentences.append(context)
            }
            if sources.count >= 2 {
                let sourceList = sources.joined(separator: " and ")
                sentences.append("\(sourceList) — both picking up the same name in the same cycle. I have learned to pay attention when that happens in \(domain).")
            }

        case .rising:
            sentences.append("\(name) has been building.")
            if let context {
                sentences.append(context)
            }
            if sources.count >= 2 {
                sentences.append("The support is coming from \(sources.joined(separator: " and ")), which is the right kind of spread across \(domain).")
            }

        case .stable:
            sentences.append("\(name) is still here.")
            if let context {
                sentences.append(context)
            }
            sentences.append("Consistency at this stage in \(domain) usually means something real underneath.")

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

    private static func composeWatchlistOnly(_ input: BriefingInput) -> String {
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
        "Malcome has not landed enough corroboration yet to give you a real read. The source network is still building. I will have something when independent lanes start agreeing."
    }

    // MARK: - Excerpt Context

    private static func bestExcerptContext(from observations: [ObservationRecord]) -> String? {
        // Find the best non-trivial excerpt to give the reader context about the cultural object
        let candidates = observations.compactMap { obs -> String? in
            guard let excerpt = obs.excerpt else { return nil }
            let cleaned = cleanEvidence(excerpt)
            // Skip trivial excerpts that are just "Surfacing on [source]" placeholders
            if cleaned.hasPrefix("Surfacing on ") { return nil }
            if cleaned.count < 20 { return nil }
            return cleaned
        }

        guard let best = candidates.first else { return nil }
        return MalcomeTokenEstimator.truncateAtSentenceBoundary(best, maxChars: 200)
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

    private static func cleanEvidence(_ text: String) -> String {
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
