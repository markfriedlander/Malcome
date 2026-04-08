import SwiftUI

// MARK: - Cited Brief Text

/// Renders brief body text with tappable citation markers [1], [2] etc.
/// Tapping a marker shows a preview card with source details and stream links.
struct CitedBriefText: View {
    let text: String
    let citations: [BriefCitation]
    @State private var selectedCitation: BriefCitation?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            buildAttributedText()
                .font(.body)
                .foregroundStyle(MalcomePalette.primary.opacity(0.9))

            if let citation = selectedCitation {
                CitationPreviewCard(citation: citation) {
                    withAnimation { selectedCitation = nil }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedCitation?.id)
    }

    @ViewBuilder
    private func buildAttributedText() -> some View {
        let segments = parseCitationSegments(text)
        // Use Text concatenation for inline rendering
        segments.reduce(Text("")) { result, segment in
            switch segment {
            case .plain(let str):
                return result + Text(str)
            case .citation(let index):
                if index > 0, index <= citations.count {
                    return result + Text(" [\(index)]")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                        .baselineOffset(4)
                } else {
                    return result + Text(" [\(index)]")
                        .font(.caption)
                        .foregroundStyle(MalcomePalette.secondary)
                        .baselineOffset(4)
                }
            }
        }
        .onTapGesture { location in
            // Text tap handling — find which citation was tapped
            // SwiftUI doesn't provide per-range tap, so we cycle through citations
            // For now, show first citation on any tap within a citation area
        }
        .overlay(citationTapTargets())
    }

    @ViewBuilder
    private func citationTapTargets() -> some View {
        // Overlay invisible buttons for each citation marker
        // This is a workaround since Text concatenation doesn't support per-segment tap
        HStack(spacing: 0) {
            ForEach(Array(citations.enumerated()), id: \.element.id) { index, citation in
                Button {
                    withAnimation {
                        if selectedCitation?.id == citation.id {
                            selectedCitation = nil
                        } else {
                            selectedCitation = citation
                        }
                    }
                } label: {
                    Text("[\(index + 1)]")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 4)
    }

    // MARK: - Citation Parsing

    private enum TextSegment {
        case plain(String)
        case citation(Int)
    }

    private func parseCitationSegments(_ text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var remaining = text[text.startIndex...]

        while let bracketStart = remaining.range(of: "[") {
            // Add plain text before the bracket
            let before = String(remaining[remaining.startIndex..<bracketStart.lowerBound])
            if !before.isEmpty {
                segments.append(.plain(before))
            }

            // Try to find matching close bracket with a number inside
            let afterBracket = remaining[bracketStart.upperBound...]
            if let bracketEnd = afterBracket.range(of: "]") {
                let inside = String(afterBracket[afterBracket.startIndex..<bracketEnd.lowerBound])
                if let num = Int(inside.trimmingCharacters(in: .whitespaces)) {
                    segments.append(.citation(num))
                    remaining = remaining[bracketEnd.upperBound...]
                    continue
                }
            }

            // Not a citation marker — treat as plain text
            segments.append(.plain("["))
            remaining = remaining[bracketStart.upperBound...]
        }

        // Add any remaining plain text
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

                // Stream links — construct search deep links from entity name
                let entityName = extractEntityName(from: citation)
                if !entityName.isEmpty {
                    streamLink(
                        name: "Apple Music",
                        icon: "music.note",
                        url: appleMusicSearchURL(entityName)
                    )
                    streamLink(
                        name: "Bandcamp",
                        icon: "waveform",
                        url: bandcampSearchURL(entityName)
                    )
                    streamLink(
                        name: "YouTube",
                        icon: "play.rectangle",
                        url: youtubeSearchURL(entityName)
                    )
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
    private func streamLink(name: String, icon: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(MalcomePalette.secondary)
            }
        }
    }

    private func extractEntityName(from citation: BriefCitation) -> String {
        // Use signalName if available, otherwise try to extract from observation title
        if !citation.signalName.isEmpty && citation.signalName != "watchlist" {
            return citation.signalName
        }
        return ""
    }

    private func appleMusicSearchURL(_ query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "https://music.apple.com/search?term=\(encoded)")
    }

    private func bandcampSearchURL(_ query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "https://bandcamp.com/search?q=\(encoded)")
    }

    private func youtubeSearchURL(_ query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "https://www.youtube.com/results?search_query=\(encoded)")
    }
}
