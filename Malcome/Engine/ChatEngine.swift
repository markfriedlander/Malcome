import Foundation
import FoundationModels

struct MalcomeChatEngine: Sendable {
    let repository: AppRepository

    private static let chatPrompt = """
    You are Malcome. Lightly rewrite the draft response below into natural conversational prose. Keep every fact exactly. Keep the calm, first-person voice. Two to four sentences. Do not add any claims, descriptions, or opinions not in the draft. Do not draw on outside knowledge about any entity. Output the response only.

    DRAFT:
    """

    // MARK: - Context Caps

    private static let maxBriefBodyChars = 1000
    private static let maxSignalContextChars = 600
    private static let maxRecentTurns = 3

    // MARK: - Send Message

    func sendMessage(
        _ userMessage: String,
        briefID: String,
        briefBody: String,
        signals: [SignalCandidateRecord],
        watchlist: [WatchlistCandidate]
    ) async throws -> ChatMessageRecord {
        guard SystemLanguageModel.default.isAvailable else {
            throw ChatEngineError.afmUnavailable
        }

        // Determine turn number
        let existingMessages = try await repository.fetchChatMessages(briefID: briefID)
        let userTurnCount = existingMessages.filter { $0.role == "user" }.count
        let turnNumber = userTurnCount + 1

        // Store user message
        let userRecord = ChatMessageRecord(
            id: UUID().uuidString,
            briefID: briefID,
            role: "user",
            content: userMessage,
            timestamp: .now,
            turnNumber: turnNumber
        )
        try await repository.storeChatMessage(
            id: userRecord.id,
            briefID: userRecord.briefID,
            role: userRecord.role,
            content: userRecord.content,
            timestamp: userRecord.timestamp,
            turnNumber: userRecord.turnNumber
        )

        // Fetch Wikipedia context if user is asking for background
        var wikipediaContext: String?
        if isBackgroundQuestion(userMessage) {
            let entityName = extractEntityFromQuestion(userMessage, signals: signals, watchlist: watchlist)
            if let name = entityName {
                if let summary = await WikipediaClient.contextSummary(for: name) {
                    wikipediaContext = summary.extract
                }
            }
        }

        // Assemble context
        let prompt = assemblePrompt(
            userMessage: userMessage,
            briefBody: briefBody,
            signals: signals,
            watchlist: watchlist,
            recentMessages: existingMessages,
            wikipediaContext: wikipediaContext
        )

        // Call AFM
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        let responseText = response.content

        // Store Malcome's response
        let malcomeRecord = ChatMessageRecord(
            id: UUID().uuidString,
            briefID: briefID,
            role: "malcome",
            content: responseText,
            timestamp: .now,
            turnNumber: turnNumber
        )
        try await repository.storeChatMessage(
            id: malcomeRecord.id,
            briefID: malcomeRecord.briefID,
            role: malcomeRecord.role,
            content: malcomeRecord.content,
            timestamp: malcomeRecord.timestamp,
            turnNumber: malcomeRecord.turnNumber
        )

        return malcomeRecord
    }

    // MARK: - Prompt Assembly

    func assemblePrompt(
        userMessage: String,
        briefBody: String,
        signals: [SignalCandidateRecord],
        watchlist: [WatchlistCandidate],
        recentMessages: [ChatMessageRecord],
        wikipediaContext: String? = nil
    ) -> String {
        let draft = composeDraftResponse(
            userMessage: userMessage,
            briefBody: briefBody,
            signals: signals,
            watchlist: watchlist,
            wikipediaContext: wikipediaContext
        )

        return Self.chatPrompt + "\n" + draft
    }

    // MARK: - Draft Response Composer

    private func composeDraftResponse(
        userMessage: String,
        briefBody: String,
        signals: [SignalCandidateRecord],
        watchlist: [WatchlistCandidate],
        wikipediaContext: String? = nil
    ) -> String {
        let query = userMessage.lowercased()

        // Find which entity the user is asking about
        let matchedSignal = signals.first { signal in
            query.contains(signal.canonicalName.lowercased())
                || signal.canonicalName.lowercased().split(separator: " ").contains(where: { query.contains($0) && $0.count > 3 })
        }
        let matchedWatch = watchlist.first { candidate in
            query.contains(candidate.title.lowercased())
                || candidate.title.lowercased().split(separator: " ").contains(where: { query.contains($0) && $0.count > 3 })
        }

        if let signal = matchedSignal {
            var draft = draftSignalResponse(signal)
            if let wiki = wikipediaContext {
                draft += " For background — \(wiki)"
            }
            return draft
        }

        if let candidate = matchedWatch {
            var draft = draftWatchlistResponse(candidate)
            if let wiki = wikipediaContext {
                draft += " For background — \(wiki)"
            }
            return draft
        }

        // No match but Wikipedia has context
        if let wiki = wikipediaContext {
            return "I have not seen that name in my current sources yet, but here is some background. \(wiki) If this starts showing up in my source network, I will flag it."
        }

        // No match, no Wikipedia — honest about what we don't have
        return "I do not have much background on this one yet — which is part of why it is interesting if my sources are starting to notice them. I can only speak to what the source network is showing me right now."
    }

    private func draftSignalResponse(_ signal: SignalCandidateRecord) -> String {
        let name = signal.canonicalName
        let domain = signal.domain.label.lowercased()
        let movement = signal.movement
        let sourceCount = signal.sourceCount
        let currentFamilies = signal.currentSourceFamilyCount

        var sentences: [String] = []

        // Lead with why this matters, not just what it is
        switch movement {
        case .new:
            sentences.append("I put \(name) in the brief because it just appeared across \(sourceCount) independent \(domain) sources in the same cycle.")
            sentences.append("That is usually how real signals start.")
        case .rising:
            sentences.append("\(name) is in the brief because it has been building quietly.")
            sentences.append("\(sourceCount) sources in \(domain) are noticing independently.")
        case .stable:
            sentences.append("\(name) keeps showing up. \(sourceCount) sources in \(domain), steady.")
            sentences.append("Consistency at this stage usually means something real underneath.")
        case .declining:
            sentences.append("\(name) was stronger last cycle. Fewer sources are picking it up now.")
            sentences.append("I am keeping it in view but the momentum is not holding the way it was.")
        }

        if currentFamilies >= 2 {
            sentences.append("The part that got my attention is that \(currentFamilies) genuinely independent source families arrived at the same conclusion without coordinating. That is the pattern I trust most.")
        } else {
            sentences.append("It is still in one lane, which means I am watching but not yet convinced.")
        }

        return sentences.joined(separator: " ")
    }

    private func draftWatchlistResponse(_ candidate: WatchlistCandidate) -> String {
        let name = candidate.title
        let stage = candidate.stage

        var sentences: [String] = []

        switch stage {
        case .corroborating:
            sentences.append("\(name) is on the watchlist and getting closer to becoming a real signal.")
            sentences.append("It is showing up across \(candidate.sourceFamilyCount) independent source families, which is the right pattern.")
            sentences.append("One more independent confirmation and I would move it from watch to signal.")
        case .forming:
            sentences.append("\(name) is forming but still early.")
            sentences.append("I have seen it in \(candidate.sourceFamilyCount) lane so far.")
            sentences.append("It needs to break out into another independent source family before I would call it a signal.")
        case .early:
            sentences.append("\(name) just registered for the first time.")
            sentences.append("Too early to make a call. But the fact that it appeared at all means the right people are starting to notice.")
        }

        return sentences.joined(separator: " ")
    }

    private func isBackgroundQuestion(_ message: String) -> Bool {
        let lower = message.lowercased()
        let patterns = [
            "who is", "who are", "what is", "tell me about",
            "tell me more about", "what do you know about",
            "give me background", "background on",
            "what should i know about", "fill me in on",
        ]
        return patterns.contains { lower.contains($0) }
    }

    private func extractEntityFromQuestion(
        _ message: String,
        signals: [SignalCandidateRecord],
        watchlist: [WatchlistCandidate]
    ) -> String? {
        let lower = message.lowercased()

        // Check known signals first
        for signal in signals {
            if lower.contains(signal.canonicalName.lowercased()) {
                return signal.canonicalName
            }
        }
        for candidate in watchlist {
            if lower.contains(candidate.title.lowercased()) {
                return candidate.title
            }
        }

        // Try to extract from common question patterns
        let patterns = [
            #"(?i)who (?:is|are) (.+?)[\?\.]?$"#,
            #"(?i)tell me (?:more )?about (.+?)[\?\.]?$"#,
            #"(?i)what (?:is|are) (.+?)[\?\.]?$"#,
            #"(?i)background on (.+?)[\?\.]?$"#,
            #"(?i)fill me in on (.+?)[\?\.]?$"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
               let range = Range(match.range(at: 1), in: message) {
                let extracted = String(message[range]).trimmingCharacters(in: .whitespaces)
                if !extracted.isEmpty { return extracted }
            }
        }

        return nil
    }
}

enum ChatEngineError: Error, LocalizedError {
    case afmUnavailable

    var errorDescription: String? {
        switch self {
        case .afmUnavailable:
            return "Apple Foundation Models is not available on this device. Malcome's chat requires Apple Intelligence hardware."
        }
    }
}
