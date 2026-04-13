import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var chatInput = ""
    @State private var isMalcomeThinking = false
    @State private var chatMessages: [ChatMessageRecord] = []
    @FocusState private var chatFocused: Bool

    private static let thinkingMessages = [
        "Give me a second.",
        "Let me think about that.",
        "Looking at what I've got on this.",
        "One moment.",
        "Checking my sources.",
        "Let me pull that up.",
    ]

    @State private var thinkingMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let errorMessage = appModel.errorMessage {
                            ErrorBanner(message: errorMessage)
                        }

                        if appModel.isFirstLaunch {
                            firstLaunchState
                        } else if appModel.isRefreshing {
                            loadingState
                        } else {
                            threadContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                }
                .onChange(of: chatMessages.count) {
                    if let last = chatMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        MalcomePalette.backgroundTop,
                        Color(red: 0.07, green: 0.08, blue: 0.10),
                        MalcomePalette.backgroundBottom,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )

            chatInputBar
        }
        .navigationTitle("Malcome")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await appModel.bootstrapIfNeeded()
            await loadThread()
        }
        .refreshable {
            await appModel.refreshAll()
            await loadThread()
        }
        .onChange(of: appModel.brief?.id) {
            Task { await loadThread() }
        }
    }

    // MARK: - First Launch State

    private var firstLaunchState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Text("First time here. Give me a moment to get current.")
                .font(.subheadline)
                .foregroundStyle(MalcomePalette.primary)
                .multilineTextAlignment(.center)
            if !appModel.loadingMessages.currentMessage.isEmpty {
                Text(appModel.loadingMessages.currentMessage)
                    .font(.caption.italic())
                    .foregroundStyle(MalcomePalette.secondary)
                    .multilineTextAlignment(.center)
                    .id(appModel.loadingMessages.currentMessage)
                    .transition(.opacity.animation(.easeInOut(duration: 0.5)))
            }
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading State

    @State private var shimmerOpacity: Double = 0.7

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 80)
            if !appModel.loadingMessages.currentMessage.isEmpty {
                Text(appModel.loadingMessages.currentMessage)
                    .font(.subheadline.italic())
                    .foregroundStyle(MalcomePalette.secondary)
                    .opacity(shimmerOpacity)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .id(appModel.loadingMessages.currentMessage)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeIn(duration: 0.5)),
                        removal: .opacity.animation(.easeOut(duration: 0.5))
                    ))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                            shimmerOpacity = 1.0
                        }
                    }
            }
            Spacer().frame(height: 80)
        }
        .animation(.easeInOut(duration: 0.5), value: appModel.loadingMessages.currentMessage)
    }

    // MARK: - Thread Content (brief + chat as unified conversation)

    @ViewBuilder
    private var threadContent: some View {
        if chatMessages.isEmpty, appModel.brief == nil {
            VStack(spacing: 16) {
                Spacer().frame(height: 40)
                Text("Pull down to refresh")
                    .font(.subheadline)
                    .foregroundStyle(MalcomePalette.secondary)
                Button {
                    Task { await appModel.forceRefresh(); await loadThread() }
                } label: {
                    Text("Check again")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
                .disabled(appModel.isRefreshing)
                Spacer().frame(height: 40)
            }
            .frame(maxWidth: .infinity)
        } else {
            ForEach(chatMessages, id: \.id) { message in
                threadMessage(message)
                    .id(message.id)
            }

            if isMalcomeThinking {
                HStack(spacing: 6) {
                    Text(thinkingMessage)
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.tertiary)
                        .italic()
                }
                .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private func threadMessage(_ message: ChatMessageRecord) -> some View {
        if message.role == "user" {
            // User message — right-aligned bubble
            HStack {
                Spacer()
                Text(message.content)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else if message.turnNumber == 0, let brief = appModel.brief {
            // Brief message — first in thread, rendered with citations
            VStack(alignment: .leading, spacing: 10) {
                Text(briefTimestamp(brief))
                    .font(.caption2)
                    .foregroundStyle(MalcomePalette.tertiary)

                Text(brief.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MalcomePalette.primary)

                CitedBriefText(text: brief.body, citations: brief.citationsPayload)
            }
            .padding(.bottom, 4)
        } else {
            // Malcome chat response — left-aligned
            Text(message.content)
                .font(.subheadline)
                .foregroundStyle(MalcomePalette.primary.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(MalcomePalette.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Chat Input

    private var chatInputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask Malcome...", text: $chatInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(MalcomePalette.primary)
                .lineLimit(1...4)
                .focused($chatFocused)

            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(chatInput.trimmingCharacters(in: .whitespaces).isEmpty ? MalcomePalette.tertiary : Color.orange)
            }
            .buttonStyle(.plain)
            .disabled(chatInput.trimmingCharacters(in: .whitespaces).isEmpty || isMalcomeThinking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MalcomePalette.cardElevated)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(MalcomePalette.stroke),
            alignment: .top
        )
    }

    // MARK: - Actions

    private func sendMessage() async {
        let message = chatInput.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty, let brief = appModel.brief else { return }

        chatInput = ""
        chatFocused = false
        isMalcomeThinking = true
        thinkingMessage = Self.thinkingMessages.randomElement() ?? "One moment."

        let userTurnCount = chatMessages.filter({ $0.role == "user" }).count
        let userMessage = ChatMessageRecord(
            id: UUID().uuidString,
            briefID: brief.id,
            role: "user",
            content: message,
            timestamp: .now,
            turnNumber: userTurnCount + 1
        )
        chatMessages.append(userMessage)

        let chatEngine = MalcomeChatEngine(repository: appModel.container.repository)
        do {
            let response = try await chatEngine.sendMessage(
                message,
                briefID: brief.id,
                briefBody: brief.body,
                signals: Array(appModel.signals),
                watchlist: Array(appModel.watchlist)
            )
            chatMessages.append(response)
        } catch {
            let errorResponse = ChatMessageRecord(
                id: UUID().uuidString,
                briefID: brief.id,
                role: "malcome",
                content: "I could not process that right now. \(error.localizedDescription)",
                timestamp: .now,
                turnNumber: userMessage.turnNumber
            )
            chatMessages.append(errorResponse)
        }

        isMalcomeThinking = false
    }

    private func loadThread() async {
        guard let brief = appModel.brief else {
            chatMessages = []
            return
        }

        // Store brief as first message if not already present
        let existingMessages = (try? await appModel.container.repository.fetchChatMessages(briefID: brief.id)) ?? []
        let hasBriefMessage = existingMessages.contains { $0.turnNumber == 0 && $0.role == "malcome" }

        if !hasBriefMessage {
            try? await appModel.container.repository.storeChatMessage(
                id: UUID().uuidString,
                briefID: brief.id,
                role: "malcome",
                content: brief.body,
                timestamp: brief.generatedAt,
                turnNumber: 0
            )
        }

        chatMessages = (try? await appModel.container.repository.fetchChatMessages(briefID: brief.id)) ?? []
    }

    private func briefTimestamp(_ brief: BriefRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: brief.generatedAt)
    }
}
