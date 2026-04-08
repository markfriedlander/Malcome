import Foundation

enum HTMLSupport {
    nonisolated static func extractAttributeValue(
        from html: String,
        attribute: String,
        onTagContaining tagMarker: String
    ) -> String? {
        let pattern = #"(?is)<[^>]*\#(tagMarker)[^>]*\#(attribute)=["']([^"']+)["'][^>]*>"#
            .replacingOccurrences(of: #"\#(tagMarker)"#, with: NSRegularExpression.escapedPattern(for: tagMarker))
            .replacingOccurrences(of: #"\#(attribute)"#, with: NSRegularExpression.escapedPattern(for: attribute))

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard
            let match = regex.firstMatch(in: html, range: nsRange),
            let range = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        return decodeHTML(String(html[range]))
    }

    nonisolated static func extractDataBlobJSON(from html: String) -> String? {
        extractAttributeValue(from: html, attribute: "data-blob", onTagContaining: #"id="DiscoverApp""#)
    }

    nonisolated static func extractAnchors(from html: String) -> [(href: String, text: String)] {
        let pattern = #"(?is)<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard
                let hrefRange = Range(match.range(at: 1), in: html),
                let textRange = Range(match.range(at: 2), in: html)
            else {
                return nil
            }

            let href = String(html[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawText = String(html[textRange])
            let text = cleanText(rawText)
            guard !href.isEmpty, !text.isEmpty else { return nil }
            return (href, text)
        }
    }

    nonisolated static func extractJSONLDBlocks(from html: String) -> [String] {
        let pattern = #"(?is)<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    nonisolated static func cleanText(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: #"(?is)<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let decoded = decodeHTML(withoutTags)
        let normalizedWhitespace = decoded.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return normalizedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func decodeHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&#8216;", with: "'")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&#8220;", with: "\"")
            .replacingOccurrences(of: "&#8221;", with: "\"")
            .replacingOccurrences(of: "&#8211;", with: "–")
            .replacingOccurrences(of: "&#8212;", with: "—")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    nonisolated static func absoluteURL(_ href: String, relativeTo baseURL: String) -> String {
        guard let url = URL(string: href), url.scheme != nil else {
            return URL(string: href, relativeTo: URL(string: baseURL))?.absoluteURL.absoluteString ?? href
        }
        return href
    }

    nonisolated static func normalizedEntityName(title: String, author: String?, fallbackURL: String) -> String {
        let base = normalizedAlias(author?.isEmpty == false ? author! : title)

        if !base.isEmpty {
            return base
        }

        return fallbackURL
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
    }

    nonisolated static func inferredEntityName(
        from title: String,
        author: String? = nil,
        fallbackURL: String
    ) -> String {
        if let author, !author.isEmpty {
            return normalizedEntityName(title: author, author: author, fallbackURL: fallbackURL)
        }

        let cleanedTitle = cleanText(title)
        let separators = [" :: ", " — ", " – ", " - ", ": "]
        for separator in separators where cleanedTitle.contains(separator) {
            let candidate = cleanedTitle.components(separatedBy: separator).first ?? cleanedTitle
            let normalized = normalizedEntityName(title: candidate, author: nil, fallbackURL: fallbackURL)
            if isMeaningfulEntityName(normalized) {
                return normalized
            }
        }

        return normalizedEntityName(title: cleanedTitle, author: nil, fallbackURL: fallbackURL)
    }

    nonisolated static func isMeaningfulEntityName(_ value: String) -> Bool {
        let normalized = normalizedAlias(value)

        guard normalized.count >= 2 else { return false }

        let blocked: Set<String> = [
            "buy tickets",
            "calendar",
            "details",
            "event details",
            "events",
            "learn more",
            "lineup",
            "more info",
            "rsvp",
            "show details",
            "tickets",
            "upcoming events"
        ]

        return !blocked.contains(normalized)
    }

    nonisolated static func hash(_ value: String) -> String {
        // Use a stable hash so the same observation key survives across app launches.
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3

        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }

        return String(format: "%016llx", hash)
    }

    nonisolated static func normalizedAlias(_ value: String) -> String {
        cleanText(value)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func relaxedAliasKey(_ value: String) -> String {
        normalizedAlias(value)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: #"^the "#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    nonisolated static func eventInstanceKey(
        entityName: String,
        publishedAt: Date?,
        location: String?,
        url: String?
    ) -> String? {
        guard let publishedAt else { return nil }

        let titleKey = normalizedAlias(entityName)
        guard !titleKey.isEmpty else { return nil }

        let dayKey = eventDayKey(for: publishedAt)
        let locationKey = normalizedAlias(location ?? "")
        let urlKey = normalizedURLKey(url ?? "")

        let raw = [titleKey, dayKey, locationKey, urlKey]
            .filter { !$0.isEmpty }
            .joined(separator: "::")

        guard !raw.isEmpty else { return nil }
        return hash(raw)
    }

    nonisolated static func normalizedURLKey(_ value: String) -> String {
        guard
            let url = URL(string: value),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return normalizedAlias(value)
        }

        components.query = nil
        components.fragment = nil
        let normalized = "\(components.host?.lowercased() ?? "")\(components.path.lowercased())"
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func eventDayKey(for date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    nonisolated static func aliasCandidates(title: String, author: String?) -> [String] {
        let cleanedTitle = cleanText(title)
        var candidates: [String] = []

        if let author {
            let cleanedAuthor = cleanText(author)
            if isMeaningfulEntityName(cleanedAuthor) {
                candidates.append(cleanedAuthor)
            }
        }

        if isMeaningfulEntityName(cleanedTitle) {
            candidates.append(cleanedTitle)
        }

        let separators = [" :: ", " — ", " – ", " - ", ": "]
        for separator in separators where cleanedTitle.contains(separator) {
            let left = cleanText(cleanedTitle.components(separatedBy: separator).first ?? cleanedTitle)
            if isMeaningfulEntityName(left) {
                candidates.append(left)
            }
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let normalized = normalizedAlias(candidate)
            guard !normalized.isEmpty else { return false }
            return seen.insert(normalized).inserted
        }
    }

    nonisolated static func leadingProperNameCandidate(in title: String, before separator: String = " on ") -> String? {
        let cleanedTitle = cleanText(title)
        guard cleanedTitle.localizedCaseInsensitiveContains(separator) else {
            return nil
        }

        let prefix = cleanText(cleanedTitle.components(separatedBy: separator).first ?? "")
        let tokens = prefix.split(separator: " ")
        guard (2...4).contains(tokens.count) else {
            return nil
        }

        let acceptableCharacterSet = CharacterSet.letters.union(.init(charactersIn: "'’. -"))
        let looksLikeProperName = tokens.allSatisfy { token in
            guard let scalar = token.unicodeScalars.first else { return false }
            let tokenString = String(token)
            let hasOnlyAcceptableCharacters = token.unicodeScalars.allSatisfy { acceptableCharacterSet.contains($0) }
            return hasOnlyAcceptableCharacters && CharacterSet.uppercaseLetters.contains(scalar)
                && !["The", "This", "That", "These", "Those"].contains(tokenString)
        }

        guard looksLikeProperName else { return nil }
        return prefix
    }

    nonisolated static func inferredEditorialEntity(
        from title: String,
        sourceName: String? = nil,
        fallbackURL: String
    ) -> (name: String, entityType: EntityType, author: String?) {
        let cleanedTitle = cleanText(title)
        let selfBranded = sourceName.map { isSelfBrandedEditorialTitle(cleanedTitle, sourceName: $0) } ?? false

        if let seriesSubject = recurringSeriesSubject(in: cleanedTitle) {
            let candidate = cleanText(seriesSubject)
            if isMeaningfulEntityName(candidate), !isPotentialTitleCollisionAlias(candidate) {
                if selfBranded, !isLikelyNamedEntity(candidate) {
                    return (candidate, .concept, nil)
                }
                return (candidate, .creator, candidate)
            }
        }

        let nameLeadingPatterns = [
            #"(?i)^(?:interview|profile|studio visit|dispatch|conversation|qa|q&a)\s+(?:with\s+)?(.+)$"#,
            #"(?i)^interview:\s*(.+?)(?:\s+on\s+.+)?$"#,
            #"(?i)^meet\s+(.+)$"#,
            #"(?i)^inside\s+(.+)$"#,
            #"(?i)^(.+?)\s+talks\s+.+$"#,
            #"(?i)^(.+?)\s+hosts\s+.+$"#,
            #"(?i)^(.+?)\s+at\s+.+$"#,
            #"(?i)^(.+?)\s+visits\s+.+$"#,
            #"(?i)^(.+?)\s+returns?\s+.+$"#,
        ]

        for pattern in nameLeadingPatterns {
            if let match = firstRegexCapture(in: cleanedTitle, pattern: pattern) {
                let candidate = cleanText(match)
                if isMeaningfulEntityName(candidate), !isPotentialTitleCollisionAlias(candidate) {
                    if selfBranded, !isLikelyNamedEntity(candidate) {
                        return (candidate, .concept, nil)
                    }
                    return (candidate, .creator, candidate)
                }
            }
        }

        if let colonLead = subjectAfterColon(in: cleanedTitle) {
            if isMeaningfulEntityName(colonLead), !isPotentialTitleCollisionAlias(colonLead) {
                return (colonLead, .creator, colonLead)
            }
        }

        if let properName = leadingProperNamePrefix(in: cleanedTitle) {
            let normalized = normalizedAlias(properName)
            if isMeaningfulEntityName(normalized), !isPotentialTitleCollisionAlias(properName) {
                return (properName, .creator, properName)
            }
        }

        let entityType: EntityType = isPotentialTitleCollisionAlias(cleanedTitle) || selfBranded ? .concept : .creator
        return (cleanedTitle, entityType, entityType == .creator ? cleanedTitle : nil)
    }

    nonisolated static func editorialContentTags(for title: String, sourceName: String? = nil) -> [String] {
        let cleaned = cleanText(title)
        let normalized = normalizedAlias(cleaned)
        var tags: [String] = []

        let recurringSeriesPatterns = [
            #"(?i)^the [^:]+ podcast:"#,
            #"(?i)^interview:"#,
            #"(?i)^artist selects:"#,
            #"(?i)^the dealers:"#,
        ]

        if recurringSeriesPatterns.contains(where: { normalized.range(of: $0, options: .regularExpression) != nil }) {
            tags.append("recurring_series")
        }

        let roundupPatterns = [
            #"(?i)^the best "#,
            #"(?i)new adds"#,
            #"(?i)festival report"#,
            #"(?i)preview"#,
        ]

        if roundupPatterns.contains(where: { normalized.range(of: $0, options: .regularExpression) != nil }) {
            tags.append("roundup")
        }

        if normalized.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil {
            tags.append("dated_editorial")
        }

        if let sourceName, isSelfBrandedEditorialTitle(cleaned, sourceName: sourceName) {
            tags.append("self_branded")
        }

        return Array(Set(tags)).sorted()
    }

    nonisolated static func aliasTokenCount(_ value: String) -> Int {
        normalizedAlias(value)
            .split(separator: " ")
            .count
    }

    nonisolated static func isShortAlias(_ value: String) -> Bool {
        let normalized = normalizedAlias(value)
        return normalized.count < 5 || aliasTokenCount(normalized) == 1 && normalized.count < 7
    }

    nonisolated static func isCommonCollisionAlias(_ value: String) -> Bool {
        let normalized = normalizedAlias(value)
        let common: Set<String> = [
            "air",
            "america",
            "angel",
            "babe",
            "beach",
            "black",
            "blue",
            "body",
            "carr",
            "comfort",
            "crush",
            "echo",
            "flea",
            "health",
            "home",
            "isis",
            "luna",
            "menu",
            "paradise",
            "radio",
            "required reading",
            "silence",
            "slippers",
            "strangers",
            "surface",
            "trust"
        ]
        return common.contains(normalized)
    }

    nonisolated static func isPotentialTitleCollisionAlias(_ value: String) -> Bool {
        let normalized = normalizedAlias(value)
        if normalized.isEmpty {
            return true
        }

        let tokens = normalized.split(separator: " ")
        let hasYear = normalized.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
        let hasVolumeMarker = normalized.contains("vol ") || normalized.contains("volume ")
        let hasEpisodeMarker = normalized.contains("episode ") || normalized.contains("season ")
        let startsLikeHeadline = ["how ", "why ", "what ", "when ", "where ", "artists ", "new ways ", "meet the ", "the "].contains {
            normalized.hasPrefix($0)
        }

        return hasYear || hasVolumeMarker || hasEpisodeMarker || (tokens.count >= 5 && startsLikeHeadline)
    }

    nonisolated static func isLikelyNamedEntity(_ value: String) -> Bool {
        let cleaned = cleanText(value)
        let tokens = cleaned.split(separator: " ")
        guard (1...4).contains(tokens.count) else { return false }

        let acceptableCharacterSet = CharacterSet.letters.union(.init(charactersIn: "'’. -&"))
        return tokens.allSatisfy { token in
            let tokenString = String(token)
            guard let scalar = tokenString.unicodeScalars.first else { return false }
            let hasOnlyAcceptableCharacters = tokenString.unicodeScalars.allSatisfy { acceptableCharacterSet.contains($0) }
            let startsUpper = CharacterSet.uppercaseLetters.contains(scalar)
            let allCapsShort = tokenString.count <= 5 && tokenString == tokenString.uppercased()
            return hasOnlyAcceptableCharacters && (startsUpper || allCapsShort)
        }
    }

    nonisolated static func isSelfBrandedEditorialTitle(_ title: String, sourceName: String) -> Bool {
        let normalizedTitle = normalizedAlias(title)
        let normalizedSource = normalizedAlias(sourceName)
        guard !normalizedTitle.isEmpty, !normalizedSource.isEmpty else { return false }

        if normalizedTitle.hasPrefix(normalizedSource) {
            return true
        }

        let possessiveSource = "\(normalizedSource) s "
        return normalizedTitle.hasPrefix(possessiveSource)
    }

    nonisolated private static func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: nsRange),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    nonisolated private static func leadingProperNamePrefix(in title: String) -> String? {
        let separators = [" — ", " – ", ": ", " :: ", " | "]
        let candidate = separators.lazy
            .compactMap { separator -> String? in
                guard title.contains(separator) else { return nil }
                return cleanText(title.components(separatedBy: separator).first ?? "")
            }
            .first ?? title

        let tokens = candidate.split(separator: " ")
        guard (1...4).contains(tokens.count) else { return nil }

        let acceptableCharacterSet = CharacterSet.letters.union(.init(charactersIn: "'’. -&"))
        let looksLikeProperName = tokens.allSatisfy { token in
            let tokenString = String(token)
            guard let scalar = tokenString.unicodeScalars.first else { return false }
            let hasOnlyAcceptableCharacters = tokenString.unicodeScalars.allSatisfy { acceptableCharacterSet.contains($0) }
            let startsUpper = CharacterSet.uppercaseLetters.contains(scalar)
            let allCapsShort = tokenString.count <= 5 && tokenString == tokenString.uppercased()
            return hasOnlyAcceptableCharacters && (startsUpper || allCapsShort)
        }

        guard looksLikeProperName else { return nil }
        return candidate
    }

    nonisolated private static func subjectAfterColon(in title: String) -> String? {
        guard let colonRange = title.range(of: ": ") else { return nil }
        let tail = cleanText(String(title[colonRange.upperBound...]))

        let patterns = [
            #"(?i)^(.+?)\s+with\s+.+$"#,
            #"(?i)^(.+?)\s+on\s+.+$"#,
            #"(?i)^(.+?)\s+talks\s+.+$"#,
            #"(?i)^(.+?)\s+visits\s+.+$"#,
            #"(?i)^(.+?)’s\s+.+$"#,
            #"(?i)^(.+?)'s\s+.+$"#,
        ]

        for pattern in patterns {
            if let match = firstRegexCapture(in: tail, pattern: pattern) {
                let candidate = cleanText(match)
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }

        return nil
    }

    nonisolated private static func recurringSeriesSubject(in title: String) -> String? {
        let patterns = [
            #"(?i)^the [^:]+ podcast:\s*(.+)$"#,
            #"(?i)^[^:]+ review:\s*(.+)$"#,
            #"(?i)^[^:]+ dispatch:\s*(.+)$"#,
        ]

        for pattern in patterns {
            guard let match = firstRegexCapture(in: title, pattern: pattern) else { continue }
            if let subject = subjectAfterColon(in: "Series: \(match)") {
                return subject
            }
            if let proper = leadingProperNamePrefix(in: match) {
                return proper
            }
        }

        return nil
    }

    // MARK: - Observation Re-normalization

    /// Recomputes normalizedEntityName from stored observation fields using current parser logic.
    nonisolated static func renormalizedEntityName(
        title: String,
        authorOrArtist: String?,
        url: String,
        parserType: ParserType,
        sourceName: String
    ) -> String {
        switch parserType {
        case .rssFeed:
            if let author = authorOrArtist, !author.isEmpty,
               !looksLikeCreditString(author),
               isMeaningfulEntityName(normalizedAlias(author)) {
                let clean = cleanText(author)
                return normalizedEntityName(title: clean, author: clean, fallbackURL: url)
            } else {
                let subject = inferredEditorialEntity(from: title, sourceName: sourceName, fallbackURL: url)
                return normalizedEntityName(title: subject.name, author: subject.author, fallbackURL: url)
            }

        case .wordPressPosts:
            let subject = inferredEditorialEntity(from: title, sourceName: sourceName, fallbackURL: url)
            return normalizedEntityName(title: subject.name, author: subject.author, fallbackURL: url)

        case .bandcampTag:
            let primary = authorOrArtist ?? title
            return normalizedEntityName(
                title: primary.isEmpty ? title : primary,
                author: authorOrArtist,
                fallbackURL: url
            )

        default:
            return normalizedEntityName(title: title, author: authorOrArtist, fallbackURL: url)
        }
    }

    /// Detects Bandcamp-style credit strings like "Earl Sweatshirt, MIKE & SURF GANG, \u{201C}POMPEII // UTILITY\u{201D}"
    private nonisolated static func looksLikeCreditString(_ text: String) -> Bool {
        let hasComma = text.contains(", ")
        let hasQuotes = text.contains("\"") || text.contains("\u{201C}") || text.contains("\u{201D}")
            || text.contains("\u{2018}") || text.contains("\u{2019}")
        if hasComma && hasQuotes { return true }

        // Multiple commas with & suggests a multi-artist credit: "A, B & C, Title"
        let commaCount = text.components(separatedBy: ", ").count - 1
        if commaCount >= 2 && text.contains("&") { return true }

        return false
    }
}
