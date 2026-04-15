import Foundation

struct RSSFeedParser: SourceParsing {
    nonisolated init() {}

    nonisolated func parse(source: SourceRecord, html: String, fetchedAt: Date) -> [ObservationDraft] {
        guard let data = html.data(using: .utf8) else { return [] }
        let items = RSSFeedDocument.parse(data: data)

        return dedupeObservationDrafts(items.compactMap { item in
            let title = HTMLSupport.cleanText(item.displayTitle)
            let rawURL = HTMLSupport.cleanText(item.link)
            let url = HTMLSupport.absoluteURL(rawURL, relativeTo: source.baseURL)

            guard !title.isEmpty, !url.isEmpty else { return nil }

            let excerpt = HTMLSupport.cleanText(item.description)
            let creator = item.creator.map(HTMLSupport.cleanText) ?? ""

            // When dc:creator provides a clean artist name, use it for entity resolution
            // instead of trying to extract an entity from the full title (which may be a
            // credit string like "Artist, Artist, 'Release Title'").
            let subject: (name: String, entityType: EntityType, author: String?)
            let normalized: String

            let isStaffByline = HTMLSupport.isStaffByline(creator, sourceName: source.name)
            // For editorial sources, the dc:creator is a journalist/editor byline, not a cultural entity.
            // The subject lives in the headline. Only use dc:creator for non-editorial sources
            // (discovery, community, venue) where the author IS the artist.
            let isEditorialSource = source.classification == .editorial

            if !creator.isEmpty, !isStaffByline, !isEditorialSource,
               !HTMLSupport.isLikelyCreditString(creator),
               HTMLSupport.isMeaningfulEntityName(HTMLSupport.normalizedAlias(creator)) {
                let cleanCreator = HTMLSupport.cleanText(creator)
                subject = (name: cleanCreator, entityType: .creator, author: cleanCreator)
                normalized = HTMLSupport.normalizedEntityName(
                    title: cleanCreator,
                    author: cleanCreator,
                    fallbackURL: url
                )
            } else {
                subject = HTMLSupport.inferredEditorialEntity(
                    from: title,
                    sourceName: source.name,
                    fallbackURL: url
                )
                normalized = HTMLSupport.normalizedEntityName(
                    title: subject.name,
                    author: subject.author,
                    fallbackURL: url
                )
            }

            guard HTMLSupport.isMeaningfulEntityName(normalized) else { return nil }

            let categoryTags = item.categories
                .map(HTMLSupport.cleanText)
                .filter { !$0.isEmpty }
                .map(HTMLSupport.normalizedAlias)

            let tags = Array(Set([
                "editorial",
                source.domain.rawValue,
                source.classification.rawValue
            ] + HTMLSupport.editorialContentTags(for: title, sourceName: source.name) + categoryTags)).sorted()

            return ObservationDraft(
                domain: source.domain,
                entityType: subject.entityType,
                externalIDOrHash: HTMLSupport.hash(url),
                title: title,
                subtitle: source.name,
                url: url,
                authorOrArtist: subject.author ?? (creator.isEmpty ? nil : creator),
                tags: tags,
                location: source.city == .global ? nil : source.city.displayName,
                publishedAt: item.publishedAt,
                scrapedAt: fetchedAt,
                excerpt: excerpt.isEmpty ? "Surfacing on \(source.name)." : excerpt,
                normalizedEntityName: normalized,
                rawPayload: item.rawPayload
            )
        })
    }
}

private struct RSSFeedItem: Sendable {
    let title: String
    let plainTitle: String?
    let link: String
    let description: String
    let creator: String?
    let publishedAt: Date?
    let categories: [String]
    let rawPayload: String

    nonisolated var displayTitle: String {
        let preferred = HTMLSupport.cleanText(plainTitle ?? "")
        return preferred.isEmpty ? title : preferred
    }
}

private enum RSSFeedDocument {
    nonisolated static func parse(data: Data) -> [RSSFeedItem] {
        let delegate = RSSFeedParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }
}

private final class RSSFeedParserDelegate: NSObject, XMLParserDelegate {
    private var currentItem: RSSFeedDraft?
    private var currentElement = ""
    private var currentText = ""

    nonisolated(unsafe) fileprivate private(set) var items: [RSSFeedItem] = []

    nonisolated override init() {
        super.init()
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        let name = qName ?? elementName
        if name == "item" {
            currentItem = RSSFeedDraft()
        }
        currentElement = name
        currentText = ""
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = qName ?? elementName
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if var item = currentItem {
            switch name {
            case "title":
                item.title = text
            case "plainTitle":
                if !text.isEmpty {
                    item.plainTitle = text
                }
            case "link":
                item.link = text
            case "description", "content:encoded":
                if !text.isEmpty, item.description.isEmpty {
                    item.description = text
                }
            case "dc:creator", "author", "media:credit":
                if !text.isEmpty {
                    item.creator = text
                }
            case "pubDate":
                item.pubDate = text
            case "dc:date":
                item.isoDate = text
            case "category":
                if !text.isEmpty {
                    item.categories.append(text)
                }
            case "item":
                if let built = item.build() {
                    items.append(built)
                }
                currentItem = nil
            default:
                break
            }
            currentItem = item
        }

        currentElement = ""
        currentText = ""
    }
}

private struct RSSFeedDraft {
    var title = ""
    var plainTitle: String?
    var link = ""
    var description = ""
    var creator: String?
    var pubDate = ""
    var isoDate = ""
    var categories: [String] = []

    func build() -> RSSFeedItem? {
        guard !title.isEmpty, !link.isEmpty else { return nil }

        return RSSFeedItem(
            title: title,
            plainTitle: plainTitle,
            link: link,
            description: description,
            creator: creator,
            publishedAt: RSSFeedDraft.parseDate(pubDate) ?? RSSFeedDraft.parseISODate(isoDate),
            categories: categories,
            rawPayload: "{\"title\":\"\(title)\",\"link\":\"\(link)\"}"
        )
    }

    private static func parseDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: raw)
    }

    private static func parseISODate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: raw) {
            return parsed
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
