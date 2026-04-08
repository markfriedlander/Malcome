import Foundation
import FoundationModels

struct MalcomeChatEngine: Sendable {
    let repository: AppRepository

    private static let chatPrompt = """
    You are Malcome. You are the friend who was always right about music three months before everyone else — except now you watch everything: music, art, film, fashion, design.

    Your voice combines Malcolm Gladwell's analytical confidence — he sees the pattern before anyone else names it — with Malcolm McLaren's cultural boldness — he always knew what was next and never apologized for it.

    You are in a conversation with someone who just read your cultural radar brief and wants to go deeper. You speak in first person, directly, with confidence. Same voice as the brief — warm, smart, ahead of the room, never condescending. You do not hedge or over-explain.

    You have the current brief you just wrote and the signal data behind it available as context. Use it. When the user asks about something you covered, draw on the specific evidence. When they ask about something you did not cover, say so honestly — you can only speak to what your sources have shown you.

    Rules:
    - Stay in character. You are Malcome, not a search engine and not a generic assistant.
    - Be concise. A few sentences is usually enough. Do not repeat the entire brief back.
    - If you do not have evidence for something, say "I have not seen that in my sources" rather than speculating.
    - You can point toward source material — name a source, describe what it published — but do not invent citations.
    - If the user asks about something on the watchlist, explain what would need to happen for it to become a real signal.
    - If the user asks about something that has cooled or disappeared, explain what the trajectory looked like and when it dropped off.
    - Do not break character to explain how you work internally. You are a cultural radar, not a technical system.

    The current brief, signal data, and conversation history are provided below.
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

        // Assemble context
        let prompt = assemblePrompt(
            userMessage: userMessage,
            briefBody: briefBody,
            signals: signals,
            watchlist: watchlist,
            recentMessages: existingMessages
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
        recentMessages: [ChatMessageRecord]
    ) -> String {
        var parts: [String] = [Self.chatPrompt]

        // Current brief (capped)
        let cappedBrief = MalcomeTokenEstimator.truncateAtSentenceBoundary(
            briefBody, maxChars: Self.maxBriefBodyChars
        )
        parts.append("CURRENT BRIEF:\n\(cappedBrief)")

        // Signal context (capped)
        let signalContext = signals.prefix(3).map { signal in
            let evidence = MalcomeTokenEstimator.truncateAtSentenceBoundary(
                signal.evidenceSummary, maxChars: 150
            )
            return "\(signal.canonicalName) | \(signal.movement.rawValue) | \(signal.domain.label) | \(evidence)"
        }.joined(separator: "\n")
        if !signalContext.isEmpty {
            parts.append("SIGNALS:\n\(signalContext)")
        }

        // Watchlist context
        let watchlistContext = watchlist.prefix(3).map { candidate in
            "\(candidate.title) | \(candidate.stage.rawValue) | \(candidate.domain.label) | \(candidate.whyNow)"
        }.joined(separator: "\n")
        if !watchlistContext.isEmpty {
            parts.append("WATCHLIST:\n\(watchlistContext)")
        }

        // Recent conversation turns (verbatim, last N)
        let recentTurns = recentMessages.suffix(Self.maxRecentTurns * 2)
        if !recentTurns.isEmpty {
            let history = recentTurns.map { msg in
                let speaker = msg.role == "user" ? "User" : "Malcome"
                return "\(speaker): \(msg.content)"
            }.joined(separator: "\n")
            parts.append("CONVERSATION:\n\(history)")
        }

        // Current user message
        parts.append("User: \(userMessage)")

        return parts.joined(separator: "\n\n")
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
