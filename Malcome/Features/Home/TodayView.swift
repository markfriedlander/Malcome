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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage = appModel.errorMessage {
                        ErrorBanner(message: errorMessage)
                    }

                    briefContent

                    chatThread
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 80)
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
            await loadChatMessages()
        }
        .refreshable {
            await appModel.refreshAll()
            chatMessages = []
        }
    }

    // MARK: - Brief Content

    @ViewBuilder
    private var briefContent: some View {
        if appModel.isRefreshing {
            // Loading state — prominent loading messages
            VStack(spacing: 16) {
                Spacer().frame(height: 60)
                Text(appModel.loadingMessages.currentMessage)
                    .font(.body.italic())
                    .foregroundStyle(MalcomePalette.secondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.5), value: appModel.loadingMessages.currentMessage)
                    .frame(maxWidth: .infinity)
                Spacer().frame(height: 60)
            }
        } else if let brief = appModel.brief {
            VStack(alignment: .leading, spacing: 12) {
                // Quiet timestamp
                Text(briefTimestamp(brief))
                    .font(.caption2)
                    .foregroundStyle(MalcomePalette.tertiary)

                // Brief title
                Text(brief.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MalcomePalette.primary)

                // Brief body with citations
                CitedBriefText(text: brief.body, citations: brief.citationsPayload)
            }
        } else {
            VStack(spacing: 12) {
                Spacer().frame(height: 40)
                Text("Pull down to refresh")
                    .font(.body)
                    .foregroundStyle(MalcomePalette.secondary)
                Spacer().frame(height: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Chat Thread

    @ViewBuilder
    private var chatThread: some View {
        if !chatMessages.isEmpty || isMalcomeThinking {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(chatMessages, id: \.id) { message in
                    chatBubble(message)
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
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func chatBubble(_ message: ChatMessageRecord) -> some View {
        if message.role == "user" {
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
        } else {
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

        // Add user message to display immediately
        let userMessage = ChatMessageRecord(
            id: UUID().uuidString,
            briefID: brief.id,
            role: "user",
            content: message,
            timestamp: .now,
            turnNumber: chatMessages.filter({ $0.role == "user" }).count + 1
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

    private func loadChatMessages() async {
        guard let brief = appModel.brief else { return }
        let messages = (try? await appModel.container.repository.fetchChatMessages(briefID: brief.id)) ?? []
        chatMessages = messages
    }

    private func briefTimestamp(_ brief: BriefRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: brief.generatedAt)
    }
}
