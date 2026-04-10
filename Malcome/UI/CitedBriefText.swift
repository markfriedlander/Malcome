import SwiftUI

// MARK: - Cited Brief Text

/// Renders brief body text with inline citation markers and tappable citation chips below.
struct CitedBriefText: View {
    let text: String
    let citations: [BriefCitation]
    @State private var selectedCitation: BriefCitation?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Brief body with inline citation markers
            buildInlineText()
                .font(.body)
                .foregroundStyle(MalcomePalette.primary.opacity(0.9))

            // Tappable citation chips
            if !citations.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(citations.enumerated()), id: \.element.id) { index, citation in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selectedCitation?.id == citation.id {
                                    selectedCitation = nil
                                } else {
                                    selectedCitation = citation
                                }
                            }
                        } label: {
                            Text("[\(index + 1)] \(citation.sourceName)")
                                .font(.caption2)
                                .foregroundStyle(selectedCitation?.id == citation.id ? .white : Color.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(selectedCitation?.id == citation.id ? Color.orange.opacity(0.8) : Color.orange.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Preview card for selected citation
            if let citation = selectedCitation {
                CitationPreviewCard(citation: citation) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedCitation = nil }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedCitation?.id)
    }

    private func buildInlineText() -> Text {
        let segments = parseCitationSegments(text)
        return segments.reduce(Text("")) { result, segment in
            switch segment {
            case .plain(let str):
                return result + Text(str)
            case .citation(let index):
                return result + Text("[\(index)]")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .baselineOffset(4)
            }
        }
    }

    // MARK: - Parsing

    private enum TextSegment {
        case plain(String)
        case citation(Int)
    }

    private func parseCitationSegments(_ text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var remaining = text[text.startIndex...]

        while let bracketStart = remaining.range(of: "[") {
            let before = String(remaining[remaining.startIndex..<bracketStart.lowerBound])
            if !before.isEmpty {
                segments.append(.plain(before))
            }

            let afterBracket = remaining[bracketStart.upperBound...]
            if let bracketEnd = afterBracket.range(of: "]") {
                let inside = String(afterBracket[afterBracket.startIndex..<bracketEnd.lowerBound])
                if let num = Int(inside.trimmingCharacters(in: .whitespaces)) {
                    segments.append(.citation(num))
                    remaining = remaining[bracketEnd.upperBound...]
                    continue
                }
            }

            segments.append(.plain("["))
            remaining = remaining[bracketStart.upperBound...]
        }

        let rest = String(remaining)
        if !rest.isEmpty {
            segments.append(.plain(rest))
        }

        return segments
    }
}

// MARK: - Citation Preview Card

struct CitationPreviewCard: View {
    let citation: BriefCitation
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(citation.sourceName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MalcomePalette.secondary)
                }
                .buttonStyle(.plain)
            }

            if !citation.observationTitle.isEmpty {
                Text(citation.observationTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MalcomePalette.primary)
                    .lineLimit(2)
            }

            if !citation.note.isEmpty {
                Text(citation.note)
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                if let url = URL(string: citation.url), !citation.url.isEmpty {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Read more")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.orange)
                    }
                }

                let entityName = citation.signalName.isEmpty || citation.signalName == "watchlist" ? "" : citation.signalName
                if !entityName.isEmpty {
                    streamLink(icon: "music.note", url: searchURL("https://music.apple.com/search?term=", query: entityName))
                    streamLink(icon: "waveform", url: searchURL("https://bandcamp.com/search?q=", query: entityName))
                    streamLink(icon: "play.rectangle", url: searchURL("https://www.youtube.com/results?search_query=", query: entityName))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MalcomePalette.cardElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func streamLink(icon: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.secondary)
            }
        }
    }

    private func searchURL(_ base: String, query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: base + encoded)
    }
}
