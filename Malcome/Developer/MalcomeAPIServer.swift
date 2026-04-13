import Foundation
import Network
import Security
import FoundationModels

// MARK: - Voice Prompt Constants

enum MalcomeVoicePrompts {

    static let briefPrompt = """
    Lightly edit the text below for natural flow. Change as little as possible. Keep the first-person voice, the short sentences, and the calm tone exactly as they are. Do not add new words like "standout", "intriguing", "promising", "traction", or "waves." Do not change "I take it seriously" to anything else. Output the edited text only, nothing else.

    TEXT:
    """

    static let chatPrompt = """
    You are Malcome. You are in a conversation with someone who just read your cultural radar brief and wants to go deeper.

    You speak in first person, directly, with confidence. Same voice as the brief — warm, smart, ahead of the room, never condescending. You do not hedge or over-explain.

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
}

// MARK: - Token Estimation

enum TokenEstimator {
    static let charsPerToken: Double = 3.5

    static func estimateTokens(from text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / charsPerToken)))
    }

    static func estimateChars(from tokens: Int) -> Int {
        Int(Double(tokens) * charsPerToken)
    }
}

// MARK: - MalcomeAPIServer

class MalcomeAPIServer {

    static let apiPort: UInt16 = 8766

    private var listener: NWListener?
    private weak var appModel: AppViewModel?

    var isRunning: Bool { listener != nil }

    // Non-persistent voice prompt overrides (session-only)
    private var briefPromptOverride: String?
    private var chatPromptOverride: String?
    private var lastIdentityResetAt: Date?

    var activeBriefPrompt: String {
        briefPromptOverride ?? MalcomeVoicePrompts.briefPrompt
    }

    var activeChatPrompt: String {
        chatPromptOverride ?? MalcomeVoicePrompts.chatPrompt
    }

    // MARK: - Token (Keychain-backed)

    private static let keychainService = "com.malcome.developer-api"
    private static let keychainAccount = "localAPIToken"

    static func loadOrCreateToken() -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService as CFString,
            kSecAttrAccount: keychainAccount as CFString,
            kSecReturnData: true
        ]
        var item: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService as CFString,
            kSecAttrAccount: keychainAccount as CFString,
            kSecValueData: Data(token.utf8) as CFData
        ]
        SecItemAdd(add as CFDictionary, nil)
        return token
    }

    var apiToken: String { Self.loadOrCreateToken() }

    // MARK: - Local Network Address

    static func localIPAddress() -> String {
        var best = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return best }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let iface = ptr?.pointee {
            defer { ptr = ptr?.pointee.ifa_next }
            guard iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: iface.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: hostname)
            if !ip.isEmpty && ip != "0.0.0.0" { best = ip }
        }
        return best
    }

    var connectionURL: String { "\(Self.localIPAddress()):\(Self.apiPort)" }

    // MARK: - AFM Availability

    static func checkAFMAvailable() -> Bool {
        SystemLanguageModel.default.isAvailable
    }

    // MARK: - Lifecycle

    func start(appModel: AppViewModel) {
        guard !isRunning else { return }
        self.appModel = appModel
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.apiPort)!)
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global(qos: .userInitiated))
                Task { await self?.handleConnection(conn) }
            }
            l.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("MalcomeAPI: Ready at \(MalcomeAPIServer.localIPAddress()):\(MalcomeAPIServer.apiPort)")
                    print("MalcomeAPI: Token: \(MalcomeAPIServer.loadOrCreateToken())")
                    print("MalcomeAPI: AFM available: \(MalcomeAPIServer.checkAFMAvailable())")
                case .failed(let e):
                    print("MalcomeAPI: Failed — \(e)")
                default: break
                }
            }
            l.start(queue: .global(qos: .userInitiated))
            self.listener = l
        } catch {
            print("MalcomeAPI: Could not start NWListener — \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        print("MalcomeAPI: Stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ conn: NWConnection) async {
        guard let data = await receiveRequest(conn),
              let req = parseRequest(data) else {
            respond(conn, status: 400, body: #"{"error":"Bad request"}"#)
            return
        }
        guard req.token == apiToken else {
            respond(conn, status: 401, body: #"{"error":"Unauthorized"}"#)
            return
        }
        let (status, body) = await route(req)
        respond(conn, status: status, body: body)
    }

    private func receiveRequest(_ conn: NWConnection) async -> Data? {
        await withCheckedContinuation { cont in
            var buf = Data()
            func next() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { chunk, _, done, err in
                    if let chunk { buf.append(chunk) }
                    if let text = String(data: buf, encoding: .utf8), text.contains("\r\n\r\n") {
                        let parts = text.components(separatedBy: "\r\n\r\n")
                        let hdr = parts[0]
                        let body = parts.dropFirst().joined(separator: "\r\n\r\n")
                        if let clLine = hdr.components(separatedBy: "\r\n")
                            .first(where: { $0.lowercased().hasPrefix("content-length:") }),
                           let cl = Int(clLine.components(separatedBy: ":").last?
                                .trimmingCharacters(in: .whitespaces) ?? "") {
                            if body.utf8.count >= cl { cont.resume(returning: buf); return }
                        } else {
                            cont.resume(returning: buf); return
                        }
                    }
                    if done || err != nil { cont.resume(returning: buf.isEmpty ? nil : buf) }
                    else { next() }
                }
            }
            next()
        }
    }

    // MARK: - HTTP Parsing

    private struct ParsedRequest {
        let method: String
        let path: String
        let token: String?
        let body: Data?
    }

    private func parseRequest(_ data: Data) -> ParsedRequest? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let split = text.components(separatedBy: "\r\n\r\n")
        guard let hdrBlock = split.first else { return nil }
        let lines = hdrBlock.components(separatedBy: "\r\n")
        guard let reqLine = lines.first else { return nil }
        let rp = reqLine.components(separatedBy: " ")
        guard rp.count >= 2 else { return nil }
        var token: String?
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("authorization: bearer ") {
                token = String(line.dropFirst("authorization: bearer ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        let bodyStr = split.dropFirst().joined(separator: "\r\n\r\n")
        let bodyData = bodyStr.isEmpty ? nil : bodyStr.data(using: .utf8)
        return ParsedRequest(method: rp[0], path: rp[1], token: token, body: bodyData)
    }

    // MARK: - Routing

    private func route(_ req: ParsedRequest) async -> (Int, String) {
        switch (req.method, req.path) {
        case ("POST", "/brief"):    return await handleBrief(body: req.body)
        case ("GET", "/brief"):     return await handleGetBrief()
        case ("GET", "/pipeline"):  return await handlePipeline()
        case ("POST", "/chat"):     return await handleChat(body: req.body)
        case ("POST", "/command"):  return await handleCommand(body: req.body)
        case ("GET", "/state"):     return await handleState()
        default:                    return (404, #"{"error":"Not found"}"#)
        }
    }

    // MARK: - POST /brief

    private func handleBrief(body: Data?) async -> (Int, String) {
        guard Self.checkAFMAvailable() else {
            return (503, #"{"error":"Apple Foundation Models unavailable on this device"}"#)
        }

        // Parse optional signal/watchlist data from body
        var signalData = ""
        var watchlistData = ""

        if let body,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            signalData = json["signals"] as? String ?? ""
            watchlistData = json["watchlist"] as? String ?? ""
        }

        // If no handcrafted data provided, build from current app state
        if signalData.isEmpty && watchlistData.isEmpty {
            let stateData = await buildSignalDataFromAppState()
            signalData = stateData.signals
            watchlistData = stateData.watchlist
        }

        // Assemble the full prompt
        let voicePrompt = activeBriefPrompt
        let dataBlock = buildDataBlock(signals: signalData, watchlist: watchlistData)
        let fullPrompt = "\(voicePrompt)\n\n\(dataBlock)"

        let voiceTokens = TokenEstimator.estimateTokens(from: voicePrompt)
        let dataTokens = TokenEstimator.estimateTokens(from: dataBlock)
        let promptTokens = voiceTokens + dataTokens

        // Call AFM
        let startTime = Date()
        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: fullPrompt)
            let elapsed = Date().timeIntervalSince(startTime)
            let responseText = response.content
            let responseTokens = TokenEstimator.estimateTokens(from: responseText)
            let totalTokens = promptTokens + responseTokens
            let percentUsed = Double(totalTokens) / 4096.0 * 100.0

            let fingerprint = promptFingerprint(voicePrompt)

            let output = """
            {
              "brief": \(jsonEscape(responseText)),
              "fullPromptUsed": \(jsonEscape(fullPrompt)),
              "voicePromptFingerprint": \(jsonEscape(fingerprint)),
              "tokenEstimate": {
                "voicePrompt": \(voiceTokens),
                "signalData": \(dataTokens),
                "promptTotal": \(promptTokens),
                "responseTokens": \(responseTokens),
                "totalTokens": \(totalTokens),
                "percentUsed": \(String(format: "%.1f", percentUsed))
              },
              "inferenceSeconds": \(String(format: "%.2f", elapsed))
            }
            """
            return (200, output)
        } catch {
            return (500, "{\"error\": \(jsonEscape(error.localizedDescription))}")
        }
    }

    // MARK: - GET /brief (current pipeline brief)

    private func handleGetBrief() async -> (Int, String) {
        guard let model = appModel else {
            return (503, #"{"error":"AppViewModel unavailable"}"#)
        }

        let briefData = await MainActor.run {
            model.brief
        }

        guard let brief = briefData else {
            return (404, #"{"error":"No brief generated yet. Use POST /command with NEW_BRIEF_CYCLE first."}"#)
        }

        let output = """
        {
          "title": \(jsonEscape(brief.title)),
          "body": \(jsonEscape(brief.body)),
          "generatedAt": \(jsonEscape(brief.generatedAt.ISO8601Format())),
          "citationCount": \(brief.citationsPayload.count)
        }
        """
        return (200, output)
    }

    // MARK: - GET /pipeline

    private func handlePipeline() async -> (Int, String) {
        guard let model = appModel else {
            return (503, #"{"error":"AppViewModel unavailable"}"#)
        }

        let state = await MainActor.run {
            (
                sourceStatuses: model.sourceStatuses,
                signals: model.signals,
                watchlist: model.watchlist,
                lastRefreshAt: model.lastRefreshAt,
                refreshSummary: model.refreshSummary,
                refreshWarning: model.refreshWarning,
                isRefreshing: model.isRefreshing
            )
        }

        let totalSources = state.sourceStatuses.count
        let enabledSources = state.sourceStatuses.filter(\.source.enabled)
        let healthySources = enabledSources.filter { $0.latestSnapshot?.status == .success }
        let failedSources = enabledSources.filter { $0.latestSnapshot?.status == .failed }
        let skippedSources = enabledSources.filter { $0.latestSnapshot?.status == .skipped }
        let backoffSources = enabledSources.filter { source in
            if let until = source.source.backoffUntil, until > Date() { return true }
            return false
        }
        let totalObservations = healthySources.reduce(0) { $0 + ($1.latestSnapshot?.itemCount ?? 0) }

        let sourceDetails = state.sourceStatuses.map { status -> String in
            let name = status.source.name
            let enabled = status.source.enabled
            let snapshotStatus = status.latestSnapshot?.status.rawValue ?? "none"
            let items = status.latestSnapshot?.itemCount ?? 0
            let error = status.latestSnapshot?.errorMessage ?? ""
            let backoff = status.source.backoffUntil.map { $0 > Date() ? "active" : "expired" } ?? "none"
            let failures = status.source.consecutiveFailures

            let errorField = error.isEmpty ? "" : ", \"error\": \(jsonEscape(error))"
            return """
                  {
                    "name": \(jsonEscape(name)),
                    "enabled": \(enabled),
                    "status": \(jsonEscape(snapshotStatus)),
                    "items": \(items),
                    "backoff": \(jsonEscape(backoff)),
                    "consecutiveFailures": \(failures)\(errorField)
                  }
            """
        }.joined(separator: ",\n")

        let politenessMode = SourcePipeline.devCadenceFloorSeconds != nil ? "dev" : "production"

        let output = """
        {
          "politenessMode": \(jsonEscape(politenessMode)),
          "lastRefreshAt": \(jsonEscape(state.lastRefreshAt?.ISO8601Format() ?? "never")),
          "isRefreshing": \(state.isRefreshing),
          "refreshSummary": \(jsonEscape(state.refreshSummary ?? "none")),
          "refreshWarning": \(jsonEscape(state.refreshWarning ?? "none")),
          "totalSources": \(totalSources),
          "enabledSources": \(enabledSources.count),
          "healthySources": \(healthySources.count),
          "failedSources": \(failedSources.count),
          "skippedSources": \(skippedSources.count),
          "backoffSources": \(backoffSources.count),
          "totalObservationsLastRefresh": \(totalObservations),
          "activeSignals": \(state.signals.count),
          "watchlistCandidates": \(state.watchlist.count),
          "sources": [
        \(sourceDetails)
          ]
        }
        """
        return (200, output)
    }

    // MARK: - POST /chat

    private func handleChat(body: Data?) async -> (Int, String) {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let message = json["message"] as? String, !message.isEmpty else {
            return (400, #"{"error":"Missing 'message'"}"#)
        }
        guard let model = appModel else {
            return (503, #"{"error":"AppViewModel unavailable"}"#)
        }
        guard MalcomeAPIServer.checkAFMAvailable() else {
            return (503, #"{"error":"Apple Foundation Models unavailable on this device"}"#)
        }

        let state = await MainActor.run {
            (
                brief: model.brief,
                signals: model.signals,
                watchlist: model.watchlist
            )
        }

        guard let brief = state.brief else {
            return (400, #"{"error":"No brief generated yet. Run NEW_BRIEF_CYCLE first."}"#)
        }

        let chatEngine = MalcomeChatEngine(repository: model.container.repository)

        // Assemble prompt for diagnostics
        let existingMessages = (try? await model.container.repository.fetchChatMessages(briefID: brief.id)) ?? []
        let fullPrompt = chatEngine.assemblePrompt(
            userMessage: message,
            briefBody: brief.body,
            signals: Array(state.signals),
            watchlist: Array(state.watchlist),
            recentMessages: existingMessages
        )

        let startTime = Date()
        do {
            let response = try await chatEngine.sendMessage(
                message,
                briefID: brief.id,
                briefBody: brief.body,
                signals: Array(state.signals),
                watchlist: Array(state.watchlist)
            )
            let elapsed = Date().timeIntervalSince(startTime)

            let promptTokens = MalcomeTokenEstimator.estimateTokens(from: fullPrompt)
            let responseTokens = MalcomeTokenEstimator.estimateTokens(from: response.content)
            let totalTokens = promptTokens + responseTokens
            let percentUsed = Double(totalTokens) / 4096.0 * 100.0

            let output = """
            {
              "response": \(jsonEscape(response.content)),
              "fullPromptUsed": \(jsonEscape(fullPrompt)),
              "turnNumber": \(response.turnNumber),
              "tokenEstimate": {
                "promptTokens": \(promptTokens),
                "responseTokens": \(responseTokens),
                "totalTokens": \(totalTokens),
                "percentUsed": \(String(format: "%.1f", percentUsed))
              },
              "inferenceSeconds": \(String(format: "%.2f", elapsed))
            }
            """
            return (200, output)
        } catch {
            return (500, "{\"error\":\(jsonEscape(error.localizedDescription))}")
        }
    }

    // MARK: - POST /command

    private func handleCommand(body: Data?) async -> (Int, String) {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let cmd = json["command"] as? String, !cmd.isEmpty else {
            return (400, #"{"error":"Missing 'command'"}"#)
        }

        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("SET_VOICE_PROMPT:") {
            let promptText = String(trimmed.dropFirst("SET_VOICE_PROMPT:".count))
                .trimmingCharacters(in: .whitespaces)
            briefPromptOverride = promptText
            let fingerprint = promptFingerprint(promptText)
            return (200, "{\"status\":\"ok\",\"command\":\"SET_VOICE_PROMPT\",\"fingerprint\":\(jsonEscape(fingerprint))}")

        } else if trimmed == "CLEAR_VOICE_PROMPT" {
            briefPromptOverride = nil
            return (200, #"{"status":"ok","command":"CLEAR_VOICE_PROMPT"}"#)

        } else if trimmed.hasPrefix("SET_CHAT_PROMPT:") {
            let promptText = String(trimmed.dropFirst("SET_CHAT_PROMPT:".count))
                .trimmingCharacters(in: .whitespaces)
            chatPromptOverride = promptText
            let fingerprint = promptFingerprint(promptText)
            return (200, "{\"status\":\"ok\",\"command\":\"SET_CHAT_PROMPT\",\"fingerprint\":\(jsonEscape(fingerprint))}")

        } else if trimmed == "CLEAR_CHAT_PROMPT" {
            chatPromptOverride = nil
            return (200, #"{"status":"ok","command":"CLEAR_CHAT_PROMPT"}"#)

        } else if trimmed == "SET_POLITENESS_MODE:dev" {
            SourcePipeline.devCadenceFloorSeconds = 120
            return (200, #"{"status":"ok","command":"SET_POLITENESS_MODE","mode":"dev","cadenceFloorSeconds":120}"#)

        } else if trimmed == "SET_POLITENESS_MODE:production" || trimmed == "CLEAR_POLITENESS_MODE" {
            SourcePipeline.devCadenceFloorSeconds = nil
            return (200, #"{"status":"ok","command":"SET_POLITENESS_MODE","mode":"production"}"#)

        } else if trimmed == "RETAG_OBSERVATIONS" {
            guard let model = appModel else {
                return (503, #"{"error":"AppViewModel unavailable"}"#)
            }
            do {
                let count = try await retagObservations(repository: model.container.repository)
                return (200, "{\"status\":\"ok\",\"command\":\"RETAG_OBSERVATIONS\",\"observationsRetagged\":\(count)}")
            } catch {
                return (500, "{\"error\":\(jsonEscape(error.localizedDescription))}")
            }

        } else if trimmed == "RELINK_OBSERVATIONS" {
            guard let model = appModel else {
                return (503, #"{"error":"AppViewModel unavailable"}"#)
            }
            do {
                let result = try await relinkAllObservations(model: model)
                return (200, "{\"status\":\"ok\",\"command\":\"RELINK_OBSERVATIONS\",\"totalObservations\":\(result.totalObservations),\"entitiesResolved\":\(result.entitiesResolved),\"signalsComputed\":\(result.signalsComputed)}")
            } catch {
                return (500, "{\"error\":\(jsonEscape(error.localizedDescription))}")
            }

        } else if trimmed == "EXTRACT_ROUNDUPS" {
            guard let model = appModel else {
                return (503, #"{"error":"AppViewModel unavailable"}"#)
            }
            do {
                let result = try await extractRoundupEntities(repository: model.container.repository)
                return (200, "{\"status\":\"ok\",\"command\":\"EXTRACT_ROUNDUPS\",\"roundupsFound\":\(result.roundupsFound),\"entitiesExtracted\":\(result.entitiesExtracted),\"afmCalls\":\(result.afmCalls)}")
            } catch {
                return (500, "{\"error\":\(jsonEscape(error.localizedDescription))}")
            }

        } else if trimmed == "RENORMALIZE_OBSERVATIONS" {
            guard let model = appModel else {
                return (503, #"{"error":"AppViewModel unavailable"}"#)
            }
            do {
                let count = try await model.container.repository.renormalizeObservations()
                return (200, "{\"status\":\"ok\",\"command\":\"RENORMALIZE_OBSERVATIONS\",\"observationsUpdated\":\(count)}")
            } catch {
                return (500, "{\"error\":\(jsonEscape(error.localizedDescription))}")
            }

        } else if trimmed == "RESET_IDENTITY_GRAPH" {
            guard let model = appModel else {
                return (503, #"{"error":"AppViewModel unavailable"}"#)
            }
            do {
                try await model.container.repository.resetIdentityGraph()
                lastIdentityResetAt = Date()
                let timestamp = lastIdentityResetAt!.ISO8601Format()
                return (200, "{\"status\":\"ok\",\"command\":\"RESET_IDENTITY_GRAPH\",\"resetAt\":\(jsonEscape(timestamp))}")
            } catch {
                return (500, "{\"error\":\(jsonEscape(error.localizedDescription))}")
            }

        } else if trimmed == "NEW_BRIEF_CYCLE" {
            guard let model = appModel else {
                return (503, #"{"error":"AppViewModel unavailable"}"#)
            }
            await MainActor.run {
                Task { await model.forceRefresh() }
            }
            return (200, #"{"status":"ok","command":"NEW_BRIEF_CYCLE"}"#)

        } else if trimmed == "GET_STATE" {
            return await handleState()

        } else {
            return (400, "{\"error\":\"Unknown command: \(jsonEscape(String(trimmed.prefix(60))))\"}")
        }
    }

    // MARK: - GET /state

    private func handleState() async -> (Int, String) {
        let afmAvailable = Self.checkAFMAvailable()
        let briefFingerprint = promptFingerprint(activeBriefPrompt)
        let chatFingerprint = promptFingerprint(activeChatPrompt)

        let briefTitle: String
        let briefGeneratedAt: String
        let signalCount: Int
        let watchlistCount: Int
        let lastRefreshAt: String

        if let model = appModel {
            let state = await MainActor.run {
                (
                    briefTitle: model.brief?.title ?? "None",
                    briefGeneratedAt: model.brief?.generatedAt.ISO8601Format() ?? "None",
                    signalCount: model.signals.count,
                    watchlistCount: model.watchlist.count,
                    lastRefreshAt: model.lastRefreshAt?.ISO8601Format() ?? "None"
                )
            }
            briefTitle = state.briefTitle
            briefGeneratedAt = state.briefGeneratedAt
            signalCount = state.signalCount
            watchlistCount = state.watchlistCount
            lastRefreshAt = state.lastRefreshAt
        } else {
            briefTitle = "Unavailable"
            briefGeneratedAt = "Unavailable"
            signalCount = 0
            watchlistCount = 0
            lastRefreshAt = "Unavailable"
        }

        let politenessMode = SourcePipeline.devCadenceFloorSeconds != nil ? "dev" : "production"

        let output = """
        {
          "afmAvailable": \(afmAvailable),
          "politenessMode": \(jsonEscape(politenessMode)),
          "voicePromptFingerprint": \(jsonEscape(briefFingerprint)),
          "chatPromptFingerprint": \(jsonEscape(chatFingerprint)),
          "briefTitle": \(jsonEscape(briefTitle)),
          "briefGeneratedAt": \(jsonEscape(briefGeneratedAt)),
          "signalCount": \(signalCount),
          "watchlistCount": \(watchlistCount),
          "lastRefreshAt": \(jsonEscape(lastRefreshAt)),
          "lastIdentityResetAt": \(jsonEscape(lastIdentityResetAt?.ISO8601Format() ?? "never")),
          "connectionURL": \(jsonEscape(connectionURL)),
          "token": \(jsonEscape(apiToken))
        }
        """
        return (200, output)
    }

    // MARK: - Signal Data Helpers

    private struct AppStateData {
        let signals: String
        let watchlist: String
    }

    private func buildSignalDataFromAppState() async -> AppStateData {
        guard let model = appModel else {
            return AppStateData(signals: "", watchlist: "")
        }

        let state = await MainActor.run {
            (signals: model.signals, watchlist: model.watchlist, sourceStatuses: model.sourceStatuses)
        }

        let sourceNamesByID = Dictionary(uniqueKeysWithValues:
            state.sourceStatuses.map { ($0.source.id, $0.source.name) }
        )

        let signalLines = state.signals.prefix(3).map { signal in
            let sources = signal.supportingSourceIDs.prefix(3)
                .compactMap { sourceNamesByID[$0] }
                .joined(separator: ", ")
            let summary = String(signal.evidenceSummary.prefix(200))
            return "- \(signal.canonicalName) | \(signal.movement.rawValue) | \(signal.sourceCount) sources (\(sources)) | \(summary)"
        }.joined(separator: "\n")

        let watchlistLines = state.watchlist.prefix(4).map { candidate in
            let whyNow = String(candidate.whyNow.prefix(200))
            return "- \(candidate.title) | \(candidate.stage.rawValue) | \(candidate.sourceFamilyCount) source families | \(whyNow)"
        }.joined(separator: "\n")

        return AppStateData(signals: signalLines, watchlist: watchlistLines)
    }

    private func buildDataBlock(signals: String, watchlist: String) -> String {
        var draft: [String] = []

        if !signals.isEmpty {
            let signalLines = signals.components(separatedBy: "\n").filter { !$0.isEmpty }
            for (index, line) in signalLines.enumerated() {
                let parts = line.replacingOccurrences(of: "- ", with: "")
                    .components(separatedBy: " | ")
                guard parts.count >= 4 else { continue }
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let movement = parts[1].trimmingCharacters(in: .whitespaces)
                let sourcesRaw = parts[2].trimmingCharacters(in: .whitespaces)
                let evidence = parts[3].trimmingCharacters(in: .whitespaces)

                // Extract source names from "3 sources (X, Y, Z)" format
                let sourceNames: String
                if let parenStart = sourcesRaw.firstIndex(of: "("),
                   let parenEnd = sourcesRaw.firstIndex(of: ")") {
                    sourceNames = String(sourcesRaw[sourcesRaw.index(after: parenStart)..<parenEnd])
                } else {
                    sourceNames = sourcesRaw
                }

                if index == 0 {
                    draft.append("\(name) is the one right now. \(evidence). When \(sourceNames) are all noticing the same person independently, that kind of agreement is hard to fake.")
                } else if movement == "new" {
                    draft.append("\(name) caught my attention for a different reason. \(evidence). \(sourceNames) — both picking up the same name in the same cycle. I have learned to pay attention when that happens.")
                } else {
                    draft.append("\(name) is \(movement). \(evidence). The sources behind this are \(sourceNames).")
                }
            }
        }

        if !watchlist.isEmpty {
            let watchLines = watchlist.components(separatedBy: "\n").filter { !$0.isEmpty }
            var watchParts: [String] = []
            for line in watchLines {
                let parts = line.replacingOccurrences(of: "- ", with: "")
                    .components(separatedBy: " | ")
                guard parts.count >= 4 else { continue }
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let stage = parts[1].trimmingCharacters(in: .whitespaces)
                let reason = parts[3].trimmingCharacters(in: .whitespaces)

                if stage == "corroborating" {
                    watchParts.append("I am also watching \(name). \(reason). One more independent confirmation and this moves from watch to signal.")
                } else {
                    watchParts.append("And I want you to know the name \(name). \(reason). Too early to call but I am paying attention.")
                }
            }
            if !watchParts.isEmpty {
                draft.append(watchParts.joined(separator: " "))
            }
        }

        if draft.isEmpty {
            return "Malcome has not landed enough data yet to write a useful brief. The source network needs more corroboration before I can give you a real read."
        }

        return draft.joined(separator: "\n\n")
    }

    // MARK: - Utilities

    private func promptFingerprint(_ prompt: String) -> String {
        let cleaned = prompt.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(60)) + "..."
    }

    private func jsonEscape(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    // MARK: - Roundup Extraction for Existing Observations

    // MARK: - Retag Observations

    private func retagObservations(repository: AppRepository) async throws -> Int {
        let observations = try await repository.fetchObservations()
        let sources = try await repository.fetchSources()
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

        var retaggedCount = 0
        for obs in observations {
            guard let source = sourcesByID[obs.sourceID] else { continue }

            // Re-run editorial content tagger
            let freshTags = HTMLSupport.editorialContentTags(for: obs.title, sourceName: source.name)

            // Build the full tag set: keep base tags, replace editorial content tags
            let baseTags = obs.tags.filter { tag in
                !["recurring_series", "roundup", "self_branded"].contains(tag)
            }
            let newTags = Array(Set(baseTags + freshTags)).sorted()

            if newTags != obs.tags {
                try await repository.updateObservationTags(observationID: obs.id, tags: newTags)
                retaggedCount += 1
            }
        }

        return retaggedCount
    }

    // MARK: - Relink All Observations

    private struct RelinkResult {
        let totalObservations: Int
        let entitiesResolved: Int
        let signalsComputed: Int
    }

    private func relinkAllObservations(model: AppViewModel) async throws -> RelinkResult {
        let repository = model.container.repository

        // Fetch ALL observations — no limit
        let allObservations = try await repository.fetchObservations()
        let sources = try await repository.fetchSources()
        let runHistory = try await repository.recentSignalRuns(limit: 400)
        let pathwayStats = try await repository.fetchPathwayStats(limit: 200)

        let runHistoryByName = Dictionary(grouping: runHistory) {
            $0.canonicalEntityID.isEmpty ? $0.canonicalName : $0.canonicalEntityID
        }
        let pathwayStatsByPattern = Dictionary(uniqueKeysWithValues: pathwayStats.map {
            ("\($0.domain.rawValue)::\($0.pathwayPattern)", $0)
        })
        let sourceMap = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

        // Run signal engine over ALL observations
        let computed = model.container.signalEngine.compute(
            from: allObservations,
            sourcesByID: sourceMap,
            runHistoryByName: runHistoryByName,
            pathwayStatsByPattern: pathwayStatsByPattern,
            now: .now
        )

        // Store results
        try await repository.replaceCanonicalIdentityGraph(
            entities: computed.canonicalEntities,
            aliases: computed.aliases,
            sourceRoles: computed.sourceRoles,
            observationMappings: computed.observationMappings
        )
        try await repository.replaceEntityStageSnapshots(computed.stageSnapshots)
        try await repository.replaceEntityHistories(computed.entityHistories)
        try await repository.replaceSignalCandidates(Array(computed.signals.prefix(20)))
        try await repository.storeSignalRuns(Array(computed.runs.prefix(20)))
        try await repository.appendPathwayHistory(computed.pathwayHistories)
        try await repository.replacePathwayStats(computed.pathwayStats)
        try await repository.replaceSourceInfluenceStats(computed.sourceInfluenceStats)
        try await repository.replaceOutcomeConfirmations(computed.outcomeConfirmations)

        return RelinkResult(
            totalObservations: allObservations.count,
            entitiesResolved: computed.canonicalEntities.count,
            signalsComputed: computed.signals.count
        )
    }

    private struct ExtractionResult {
        let roundupsFound: Int
        let entitiesExtracted: Int
        let afmCalls: Int
    }

    private func extractRoundupEntities(repository: AppRepository) async throws -> ExtractionResult {
        let observations = try await repository.fetchObservations()
        let sources = try await repository.fetchSources()
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

        let roundups = observations.filter { $0.tags.contains("roundup") && !$0.tags.contains("roundup_source") }
        var totalExtracted = 0
        var afmCalls = 0

        for roundup in roundups {
            guard let source = sourcesByID[roundup.sourceID] else { continue }

            afmCalls += 1
            let entities = await RoundupExtractor.extractEntities(
                title: roundup.title,
                excerpt: roundup.excerpt ?? ""
            )

            guard !entities.isEmpty else { continue }

            let drafts = RoundupExtractor.draftsFromExtraction(
                entities: entities,
                originalTitle: roundup.title,
                originalURL: roundup.url,
                originalExcerpt: roundup.excerpt ?? "",
                source: source,
                fetchedAt: roundup.scrapedAt,
                publishedAt: roundup.publishedAt,
                tags: roundup.tags
            )

            let inserted = try await repository.storeObservations(
                snapshotID: roundup.snapshotID,
                sourceID: roundup.sourceID,
                drafts: drafts
            )
            totalExtracted += inserted
        }

        return ExtractionResult(roundupsFound: roundups.count, entitiesExtracted: totalExtracted, afmCalls: afmCalls)
    }

    // MARK: - HTTP Response

    private func respond(_ conn: NWConnection, status: Int, body: String) {
        let phrase: String
        switch status {
        case 200: phrase = "OK"
        case 400: phrase = "Bad Request"
        case 401: phrase = "Unauthorized"
        case 404: phrase = "Not Found"
        case 501: phrase = "Not Implemented"
        case 503: phrase = "Service Unavailable"
        default:  phrase = "Internal Server Error"
        }
        let bodyData = body.data(using: .utf8) ?? Data()
        let header = "HTTP/1.1 \(status) \(phrase)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var resp = header.data(using: .utf8)!
        resp.append(bodyData)
        conn.send(content: resp, completion: .contentProcessed { _ in conn.cancel() })
    }
}
