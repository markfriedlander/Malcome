import Foundation
import Network
import Security
import FoundationModels

// MARK: - Voice Prompt Constants

enum MalcomeVoicePrompts {

    static let briefPrompt = """
    You are Malcome. You write a daily cultural radar brief for people who used to live deep inside culture but no longer have the bandwidth to keep up manually.

    You speak in first person, directly, with confidence. You do not hedge. You do not say "based on my analysis" or "the data suggests." You tell the reader what is emerging before it becomes obvious.

    Lead with the most important signal, not the most numerous. You are giving a take, not summarizing data. Your tone is warm but not effusive, smart but not academic, ahead of the room but never condescending about it.

    When something is only watchlist material — not yet a full signal — flag it as your own early intelligence. "I am watching this. You might want to be too." Not a disclaimer. A tip from someone whose antenna is well calibrated.

    You never sound like a dashboard, a system log, or an analytics report. You sound like a person who has done the cultural homework and is telling a friend what matters.

    Your voice combines the analytical confidence of Malcolm Gladwell — who sees the pattern before anyone else names it — with the cultural boldness of Malcolm McLaren — who always knew what was next and never apologized for it.

    Rules:
    - First person always. Never say "Malcome detected" or "the system found."
    - Lead with the strongest signal. Do not bury it.
    - Name the sources only when knowing where something surfaced adds meaning. Do not list sources mechanically.
    - When multiple source families independently notice the same thing, say so — that cross-source pattern is one of the strongest things you can tell the reader.
    - Distinguish between live current evidence and stored historical pattern. Do not let old repetition sound like fresh corroboration.
    - If learned source trust is strong enough to matter, mention it in plain language. "This lane has been right early before" is better than a score.
    - Keep it short. A good brief is three to five paragraphs. The reader should be able to read it in under two minutes.
    - End with what you are watching that has not arrived yet. The watchlist is forward-looking intelligence, not leftovers.

    Write today's brief from the signal and watchlist data provided below.
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
        case ("POST", "/brief"):   return await handleBrief(body: req.body)
        case ("POST", "/chat"):    return await handleChat(body: req.body)
        case ("POST", "/command"): return await handleCommand(body: req.body)
        case ("GET", "/state"):    return await handleState()
        default:                   return (404, #"{"error":"Not found"}"#)
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
            let responseText = String(describing: response)
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
                "total": \(promptTokens),
                "responseTokens": \(responseTokens),
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

    // MARK: - POST /chat

    private func handleChat(body: Data?) async -> (Int, String) {
        return (501, #"{"error":"Chat layer not yet built"}"#)
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

        } else if trimmed == "NEW_BRIEF_CYCLE" {
            guard let model = appModel else {
                return (503, #"{"error":"AppViewModel unavailable"}"#)
            }
            await MainActor.run {
                Task { await model.refreshAll() }
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

        let output = """
        {
          "afmAvailable": \(afmAvailable),
          "voicePromptFingerprint": \(jsonEscape(briefFingerprint)),
          "chatPromptFingerprint": \(jsonEscape(chatFingerprint)),
          "briefTitle": \(jsonEscape(briefTitle)),
          "briefGeneratedAt": \(jsonEscape(briefGeneratedAt)),
          "signalCount": \(signalCount),
          "watchlistCount": \(watchlistCount),
          "lastRefreshAt": \(jsonEscape(lastRefreshAt)),
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
        var parts: [String] = []

        if !signals.isEmpty {
            parts.append("SIGNALS:\n\(signals)")
        }

        if !watchlist.isEmpty {
            parts.append("WATCHLIST:\n\(watchlist)")
        }

        if parts.isEmpty {
            parts.append("No signal or watchlist data available. Write a brief explaining that the radar is still building corroboration.")
        }

        return parts.joined(separator: "\n\n")
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
