import Foundation
import FoundationModels

// MARK: - Heuristic Caps

enum BriefCaps {
    static let maxSignals = 3
    static let maxWatchlistItems = 4
    static let maxObservationsPerSignal = 4
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
    Lightly edit the text below for natural flow. Change as little as possible. Keep the first-person voice, the short sentences, and the calm tone exactly as they are. Keep all citation markers like [1] and [2] exactly where they are. Keep all dash-bounded appositives (Name — description — verb) exactly as structured. Do not add new words like "standout", "intriguing", "promising", "traction", "waves", "buzzing", "exciting", or "undeniable." Output the edited text only, nothing else.

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
        var body = draftResult.sourceReferences.isEmpty
            ? draftResult.text
            : await polishWithAFM(draftResult.text)
        // Global cleanup: fix punctuation artifacts from excerpt/template concatenation
        while body.contains("..") && !body.contains("...") {
            body = body.replacingOccurrences(of: "..", with: ".")
        }
        // Fix quoted-text double punctuation: '.".' → '."' and '.". ' → '." '
        body = body.replacingOccurrences(of: ".\".\"", with: ".\"")
        body = body.replacingOccurrences(of: ".\".", with: ".\"")
        body = body.replacingOccurrences(of: ".'.", with: ".'")
        body = body.replacingOccurrences(of: ".\u{201D}.", with: ".\u{201D}")
        let title = briefTitle(from: capped, briefBody: body)

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
                sourceCities: packet.sourceCities,
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

    private func briefTitle(from input: BriefingInput, briefBody: String) -> String {
        if let lead = input.signals.first {
            return lead.signal.canonicalName
        }
        if let lead = input.watchlistCandidates.first {
            return lead.title
        }
        return ""
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

    /// Tracks used phrase indices within a single brief to prevent repetition.
    /// Uses a hash of the variant array + index to track which template slot variants have been used.
    private static var usedSlotIndices: Set<String> = []

    private static func pickPhrase(from variants: [String]) -> String {
        // Create a slot key from the first variant (identifies the template slot)
        let slotKey = String(variants.first?.prefix(30) ?? "")
        let available = variants.enumerated().filter { index, _ in
            !usedSlotIndices.contains("\(slotKey)::\(index)")
        }
        if let (index, phrase) = available.randomElement() {
            usedSlotIndices.insert("\(slotKey)::\(index)")
            return phrase
        }
        // All used — pick random from full set
        return variants.randomElement() ?? ""
    }

    static func compose(from input: BriefingInput, observationCount: Int = 0, nearMissCount: Int = 0) async -> DraftResult {
        usedSlotIndices.removeAll()
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
        private var seenSourceNames: [String: Int] = [:]

        mutating func cite(sourceName: String, observation: ObservationRecord?) -> String {
            // Each unique source name gets exactly one citation number
            if let existingIndex = seenSourceNames[sourceName] {
                return "[\(existingIndex)]"
            }

            let ref = DraftResult.SourceReference(
                sourceName: sourceName,
                observationTitle: observation?.title ?? "",
                url: observation?.url ?? "",
                excerpt: observation?.distilledExcerpt ?? observation?.excerpt ?? ""
            )
            references.append(ref)
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
            let historicalTemplates = [
                "NAME has been building quietly in DOMAIN. I have been watching this for a while — SOURCES have both noticed independently, and the pattern has held. This is not new news, but it is durable, which is often more interesting.",
                "NAME is not new to me. The DOMAIN sources have had this name in circulation for a while now. SOURCES have been consistent, and that kind of staying power is what I pay attention to.",
                "I have been sitting on NAME for a few cycles. SOURCES keep returning to this name across DOMAIN, and the evidence has not thinned out. That tells me something.",
                "The pattern around NAME is older than today's read. SOURCES have been tracking this independently in DOMAIN for long enough that I trust the signal even though it is not fresh news.",
            ]
            for packet in historicalSignals {
                let name = packet.signal.canonicalName
                let domain = packet.signal.domain.label.lowercased()
                let sources = packet.sourceNames.prefix(3).joined(separator: " and ")
                let template = pickPhrase(from: historicalTemplates)
                let filled = template
                    .replacingOccurrences(of: "NAME", with: name)
                    .replacingOccurrences(of: "DOMAIN", with: domain)
                    .replacingOccurrences(of: "SOURCES", with: sources)
                paragraphs.append(filled)
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
                paragraphs.append(pickPhrase(from: [
                    "This is not a one-off sighting. The current evidence is fresh, but there is stored history behind it too.",
                    "This name has history in my sources. The current attention is new, but the foundation is not.",
                    "I have seen this name before in stored history. The fact that it is surfacing again with fresh corroboration makes it more interesting, not less.",
                    "There is both current and historical evidence here. That combination usually means something durable.",
                ]))
            } else {
                paragraphs.append(pickPhrase(from: [
                    "The \(domain) radar is thin right now. One signal does not make a pattern. But when the corroboration is this clean, it is worth leading with.",
                    "It is a quiet cycle for \(domain). But the quality of this one signal is high enough to lead with.",
                    "Not much else on the \(domain) surface right now. But this one is clean and I would rather show you one real signal than fill space.",
                    "The \(domain) radar has one strong read and not much else. That is an honest picture.",
                ]))
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
        let cities = packet.sourceCities
        let domain = packet.signal.domain.label.lowercased()
        let entityType = packet.signal.entityType
        let movement = packet.signal.movement

        var sentences: [String] = []

        // Sentence 1 — Who + what they are
        let wikiContext = await wikiContextPhrase(for: name, domain: packet.signal.domain)
        let leadOpener = pickPhrase(from: [
            "is the one right now",
            "is where the attention is",
            "is the name I keep coming back to",
            "has my attention",
            "is the name to know right now",
            "is leading today's radar",
            "is the one I am watching closest",
            "is at the front of today's read",
        ])
        if let wiki = wikiContext {
            sentences.append("\(name) — \(wiki) — \(leadOpener).")
        } else {
            // No Wikipedia — use bare name. Honest silence is better than "a music artist."
            sentences.append("\(name) \(leadOpener).")
        }

        // Sentence 2 — What is specifically happening right now (attributed to source)
        let excerptContext = await bestExcerptContext(from: packet.observations)
        if let context = excerptContext {
            // Find the editorial source for attribution
            let editorialSource = packet.observations.first { obs in
                obs.tags.contains("editorial") && obs.excerpt != nil && !obs.excerpt!.isEmpty
            }
            if let sourceName = editorialSource?.subtitle, !sourceName.isEmpty {
                sentences.append("According to \(sourceName), \(context)")
            } else {
                sentences.append(context)
            }
        } else {
            sentences.append(pickPhrase(from: [
                "Something is happening — I do not have the full picture yet but the right sources are paying attention.",
                "The details are still forming, but the fact that independent sources are converging on this name is worth noting.",
                "I do not have the full story yet, but when this many sources start pointing the same direction, I start paying attention.",
                "There is movement around this name. The specifics are still coming into focus.",
                "The sources are noticing something. I am still assembling the picture but the pattern is real.",
                "I cannot tell you exactly what is happening yet, but the right people are looking in this direction.",
                "The shape of this is still forming. What I can tell you is that the attention is real and it is coming from the right places.",
                "Something is moving. I will have more when the next cycle fills in the details.",
            ]))
        }

        // Sentence 3 — Who noticed and where (with citations)
        // Build source-with-city pairs from observations
        var sourceCityMap: [String: String] = [:]
        for obs in packet.observations {
            if let location = obs.location, !location.isEmpty {
                let sourceName = obs.subtitle ?? ""
                if !sourceName.isEmpty && sourceCityMap[sourceName] == nil {
                    sourceCityMap[sourceName] = location
                }
            }
        }

        let citedSources = sources.prefix(3).enumerated().map { index, sourceName -> String in
            let obs = index < packet.observations.count ? packet.observations[index] : packet.observations.first
            let marker = tracker.cite(sourceName: sourceName, observation: obs)
            return "\(sourceName)\(marker)"
        }

        let citedWithCity = sources.prefix(3).enumerated().map { index, sourceName -> String in
            let obs = index < packet.observations.count ? packet.observations[index] : packet.observations.first
            let marker = tracker.cite(sourceName: sourceName, observation: obs)
            if let city = sourceCityMap[sourceName] {
                return "\(sourceName)\(marker) in \(city)"
            }
            return "\(sourceName)\(marker)"
        }

        let uniqueCities = Set(sourceCityMap.values)
        let familyCount = packet.signal.currentSourceFamilyCount
        let isTrulyIndependent = familyCount >= 2

        if uniqueCities.count >= 2 && citedWithCity.count >= 2 && isTrulyIndependent {
            sentences.append("Both \(citedWithCity.prefix(2).joined(separator: " and ")) picked this up independently.")
        } else if citedSources.count >= 2 && isTrulyIndependent {
            sentences.append("\(citedSources.joined(separator: " and ")) are both picking up on this independently in \(domain).")
        } else if citedSources.count >= 2 {
            // Same family — honest about it
            sentences.append("\(citedSources.joined(separator: " and ")) are both covering this in \(domain).")
        } else if let source = citedSources.first {
            sentences.append("The signal is coming through \(source).")
        }

        // Sentence 4 — Why that agreement matters
        if isTrulyIndependent && sources.count >= 2 {
            sentences.append(pickPhrase(from: [
                "When sources that watch completely different parts of the \(domain) scene agree independently, that kind of convergence is hard to fake.",
                "Independent agreement across different \(domain) lanes is the pattern I trust most. You cannot coordinate this by accident.",
                "The interesting part is not any single mention — it is the fact that unrelated sources are arriving at the same conclusion.",
                "This is what real emergence looks like in \(domain): different vantage points, same name, no coordination.",
                "Cross-source agreement is the strongest signal I can give you. These sources do not talk to each other.",
                "When genuinely independent parts of the \(domain) scene converge on a name without coordinating, I take it seriously.",
                "The corroboration here is real — these are not the same editors reading the same press release.",
                "Independent sources noticing the same thing is the pattern that separates signal from noise in \(domain).",
            ]))
        } else if sources.count >= 2 {
            sentences.append(pickPhrase(from: [
                "The coverage is real, though it is still within the same network. A second independent source family would make this stronger.",
                "Multiple mentions from the same lane. Good attention, but I am waiting for a second independent family to confirm.",
                "The repetition is noted but the agreement is within one source network. I want to see this from a genuinely different direction.",
            ]))
        }

        // Sentence 5 — What it suggests
        switch movement {
        case .new:
            sentences.append(pickPhrase(from: [
                "This is the first time it has crossed my radar.",
                "This is a new name on the radar. First appearance this cycle.",
                "I had not seen this before this cycle. That makes it worth watching.",
                "New to the radar. The fact that it arrived with corroboration is notable.",
            ]))
        case .rising:
            sentences.append(pickPhrase(from: [
                "This is accelerating.",
                "The momentum is building.",
                "This is picking up speed.",
                "Each cycle, the support gets broader.",
            ]))
        case .stable:
            sentences.append(pickPhrase(from: [
                "This has been consistent — which at this stage is more telling than a loud entrance.",
                "Staying power at this stage matters more than a sharp spike.",
                "The consistency is the story. This is not going away.",
                "Steady presence across multiple cycles. That is usually more meaningful than a single loud moment.",
            ]))
        case .declining:
            sentences.append(pickPhrase(from: [
                "The window on this one may be closing.",
                "The support is thinning. I am keeping it in view but the momentum is fading.",
                "This was stronger last cycle. The attention is not holding.",
                "The pattern is weakening. Worth watching but not leading with.",
            ]))
        }

        return sentences.joined(separator: " ")
    }

    /// Verify that an AFM-compressed phrase is grounded in the source and doesn't contain the entity name.
    private static func phraseIsGrounded(_ phrase: String, in source: String, entityName: String) -> Bool {
        let phraseLower = phrase.lowercased()
        let sourceLower = source.lowercased()

        // Reject if the entity name leaked into the phrase
        if phraseLower.contains(entityName.lowercased()) { return false }

        // Reject grammatically broken patterns
        if phraseLower.contains("from la-based") || phraseLower.contains("la-based based") { return false }

        // Extract significant words (3+ chars, capitalized) from the phrase
        let phraseWords = phrase.split(separator: " ").map(String.init)
        let significantWords = phraseWords.filter { word in
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            guard clean.count >= 3 else { return false }
            // City names, proper nouns — anything that could be a hallucinated fact
            return clean.first?.isUppercase == true || ["LA", "NYC", "UK", "DJ"].contains(clean)
        }

        if !significantWords.isEmpty {
            let grounded = significantWords.filter { word in
                sourceLower.contains(word.lowercased().trimmingCharacters(in: .punctuationCharacters))
            }
            return grounded.count >= max(1, (significantWords.count + 1) / 2)
        }
        return true
    }

    // MARK: - Secondary Signals

    private static func composeSecondarySignal(_ packet: BriefingInput.SignalPacket, tracker: inout SourceTracker) async -> String {
        let name = packet.signal.canonicalName
        let sources = packet.sourceNames
        let domain = packet.signal.domain.label.lowercased()
        let movement = packet.signal.movement
        let rawWikiContext = await wikiContextPhrase(for: name, domain: packet.signal.domain)
        // Ensure context phrases end with a period for proper sentence concatenation
        let wikiContext: String? = rawWikiContext.map { phrase in
            phrase.hasSuffix(".") ? phrase : phrase + "."
        }
        let context: String?
        if let wiki = wikiContext {
            context = wiki
        } else {
            context = await bestExcerptContext(from: packet.observations)
        }

        let citedSources = sources.prefix(3).enumerated().map { index, sourceName -> String in
            let obs = index < packet.observations.count ? packet.observations[index] : packet.observations.first
            let marker = tracker.cite(sourceName: sourceName, observation: obs)
            return "\(sourceName)\(marker)"
        }

        var sentences: [String] = []

        switch movement {
        case .new:
            sentences.append(pickPhrase(from: [
                "\(name) caught my attention for a different reason.",
                "\(name) is new on the radar.",
                "\(name) just appeared this cycle.",
                "\(name) is a name I had not seen before this pass.",
            ]))
            if let context {
                sentences.append(context)
            }
            if citedSources.count >= 2 {
                let sourceList = citedSources.joined(separator: " and ")
                sentences.append("\(sourceList) — both picking up the same name in the same cycle. I have learned to pay attention when that happens in \(domain).")
            }

        case .rising:
            sentences.append(pickPhrase(from: [
                "\(name) has been building.",
                "\(name) is picking up momentum.",
                "\(name) keeps gaining ground.",
                "\(name) is getting louder across the network.",
            ]))
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
                parts.append(pickPhrase(from: [
                    "One more independent confirmation and this moves from watch to signal.",
                    "Almost there. One more independent source and I would call this a signal.",
                    "Close to crossing the line. One more independent lane would do it.",
                    "The pattern is forming but needs one more independent confirmation before I lead with it.",
                ]))

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

        paragraphs.append(pickPhrase(from: [
            "No name has crossed the corroboration line yet, but I have been watching the \(domainPhrase) surface and there are patterns forming.",
            "Nothing has graduated to a full signal yet, but the \(domainPhrase) radar is not empty. Here is what I am watching.",
            "The \(domainPhrase) surface is active but nothing has hit the corroboration threshold yet. These are the names that are closest.",
            "I do not have a strong call yet, but these names keep turning up in the \(domainPhrase) lanes and that is worth telling you about.",
        ]))

        paragraphs.append(composeWatchlistParagraph(input.watchlistCandidates))

        paragraphs.append(pickPhrase(from: [
            "None of this is a signal yet. That is the honest read. But these are the names I would want to know if I were you.",
            "I am not ready to call any of these yet. But I wanted you to hear the names before everyone else does.",
            "Nothing here is certain. But if you asked me where to look next, these are the directions I would point.",
            "These are pre-signal names. The corroboration is not there yet but the early attention is real.",
        ]))

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

    /// Fetches Wikipedia context and uses AFM to compress it into a clean 8-12 word appositive.
    private static func wikiContextPhrase(for entityName: String, domain: CulturalDomain = .music) async -> String? {
        guard let summary = await WikipediaClient.contextSummary(for: entityName, domain: domain) else { return nil }

        let firstSentence = summary.firstSentence
        guard !firstSentence.isEmpty else { return nil }

        // Use AFM to compress into a clean appositive, then verify against source
        if SystemLanguageModel.default.isAvailable {
            let prompt = "Extract a short description from this text. 8-12 words. Do NOT include the subject's name. Do NOT add any facts not in the text. No full sentences. No trailing period. Input: \(firstSentence). Description:"
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                var phrase = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                while phrase.hasSuffix(".") || phrase.hasSuffix(",") || phrase.hasSuffix(";") {
                    phrase = String(phrase.dropLast()).trimmingCharacters(in: .whitespaces)
                }
                let wordCount = phrase.split(separator: " ").count
                if wordCount >= 4 && wordCount <= 20 && !phrase.isEmpty {
                    if phraseIsGrounded(phrase, in: firstSentence, entityName: entityName) {
                        return phrase
                    }
                }
            } catch {}
        }

        // Regex fallback if AFM unavailable
        let patterns = [
            #"(?:is|was) (?:an? )(.+?)(?:\.|$)"#,
            #"(?:are|were) (?:an? )(.+?)(?:\.|$)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: firstSentence, range: NSRange(firstSentence.startIndex..., in: firstSentence)),
               let range = Range(match.range(at: 1), in: firstSentence) {
                let descriptor = String(firstSentence[range]).trimmingCharacters(in: .whitespaces)
                if descriptor.count >= 5 && descriptor.count <= 120 {
                    return MalcomeTokenEstimator.truncateAtSentenceBoundary(descriptor, maxChars: 80)
                }
            }
        }

        if firstSentence.count <= 100 { return firstSentence }
        return nil
    }

    // MARK: - Excerpt Context

    private static func bestExcerptContext(from observations: [ObservationRecord]) async -> String? {
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
                    if let safe = await safeExcerpt(cleaned) { return safe }
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

        // Prefer sentences that mention the entity name
        if let entitySpecific = candidates.first(where: { $0.1 }) {
            if let safe = await safeExcerpt(entitySpecific.0) { return safe }
        }

        // Fall back to any non-generic excerpt
        if let fallback = candidates.first(where: { !isGenericEditorialObservation($0.0) }) {
            if let safe = await safeExcerpt(fallback.0) { return safe }
        }

        // Last resort: take editorial excerpt and compress if needed.
        // Never truncate mid-sentence. Use AFM to compress long excerpts.
        for obs in sorted {
            guard let excerpt = obs.excerpt, !excerpt.isEmpty else { continue }
            if excerpt.hasPrefix("Surfacing on ") { continue }
            if isBandcampMetadata(excerpt) { continue }
            let cleaned = cleanEvidence(excerpt)
            if cleaned.count < 30 { continue }

            // If short enough, use as-is (must end with period)
            if cleaned.count <= 200 && cleaned.hasSuffix(".") {
                return cleaned
            }

            // Any excerpt over 60 chars — compress with AFM into 1-2 clean sentences
            if cleaned.count > 60 {
                if let compressed = await compressExcerpt(cleaned) {
                    return compressed
                }
            }
        }

        return nil
    }

    /// Returns a complete-sentence excerpt or nil. Never truncates mid-sentence.
    /// Short complete excerpts pass through. Long excerpts get AFM compression.
    private static func safeExcerpt(_ text: String) async -> String? {
        // Short enough and ends with period — use as-is
        if text.count <= 200 && text.hasSuffix(".") {
            return text
        }
        // Has a complete sentence under 200 chars — use the first one
        if let dotSpace = text.range(of: ". ") {
            let first = String(text[text.startIndex...dotSpace.lowerBound]) + "."
            if first.count >= 25 && first.count <= 200 {
                return first
            }
        }
        // Long text — compress with AFM
        if text.count > 60 {
            return await compressExcerpt(text)
        }
        return nil
    }

    /// Compress a long editorial excerpt into 1-2 clean sentences using AFM.
    private static func compressExcerpt(_ excerpt: String) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let prompt = "Rewrite this into one or two complete sentences, maximum 40 words. Keep the key facts. No truncation. Input: \(String(excerpt.prefix(500))). Output:"
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            var result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.count >= 20 && result.count <= 300 {
                if !result.hasSuffix(".") { result += "." }
                return result
            }
        } catch {}
        return nil
    }

    private static func ensureEndsWithPeriod(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Clean up any double periods
        while result.contains("..") && !result.contains("...") {
            result = result.replacingOccurrences(of: "..", with: ".")
        }
        if result.hasSuffix(".") || result.hasSuffix("!") || result.hasSuffix("?") || result.hasSuffix("\"") || result.hasSuffix("\u{201D}") {
            return result
        }
        return result + "."
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
        // Decode common HTML entities
        cleaned = cleaned.replacingOccurrences(of: "&hellip;", with: "...")
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&mdash;", with: "—")
        cleaned = cleaned.replacingOccurrences(of: "&ndash;", with: "–")
        cleaned = cleaned.replacingOccurrences(of: "&lsquo;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&rsquo;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
        cleaned = cleaned.replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
        cleaned = cleaned.replacingOccurrences(of: "[&hellip;]", with: "...")
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
