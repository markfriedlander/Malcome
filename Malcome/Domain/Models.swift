import Foundation

enum CulturalDomain: String, Codable, CaseIterable, Sendable {
    case music
    case art
    case fashion
    case film
    case design
    case nightlife
    case internetCulture = "internet_culture"
    case mixed
    case generalCulture = "general_culture"

    nonisolated var label: String {
        switch self {
        case .music: "Music"
        case .art: "Art"
        case .fashion: "Fashion"
        case .film: "Film"
        case .design: "Design"
        case .nightlife: "Nightlife"
        case .internetCulture: "Internet Culture"
        case .mixed: "Mixed"
        case .generalCulture: "General Culture"
        }
    }
}

enum SourceClassification: String, Codable, CaseIterable, Sendable {
    case discovery
    case editorial
    case community
    case institutional
    case venue
    case commercialScaling = "commercial_scaling"

    nonisolated var label: String {
        switch self {
        case .discovery: "Discovery"
        case .editorial: "Editorial"
        case .community: "Community"
        case .institutional: "Institutional"
        case .venue: "Venue"
        case .commercialScaling: "Commercial Scaling"
        }
    }
}

enum SourceCity: String, Codable, CaseIterable, Sendable {
    case losAngeles = "los_angeles"
    case newYork = "new_york"
    case london
    case berlin
    case global

    nonisolated var displayName: String {
        switch self {
        case .losAngeles: "Los Angeles"
        case .newYork: "New York City"
        case .london: "London"
        case .berlin: "Berlin"
        case .global: "Global"
        }
    }
}

enum ParserType: String, Codable, CaseIterable, Sendable {
    case bandcampTag
    case diceEvents
    case residentAdvisor
    case venueCalendar
    case wordPressPosts = "wordpress_posts"
    case rssFeed = "rss_feed"
    case gitHubTrending
    case genericDiscussion
    case stub
}

enum SourceTier: String, Codable, CaseIterable, Sendable {
    case a = "A"
    case b = "B"
    case c = "C"

    nonisolated var label: String {
        "Tier \(rawValue)"
    }
}

enum SnapshotStatus: String, Codable, CaseIterable, Sendable {
    case running
    case success
    case failed
    case skipped
}

enum EntityType: String, Codable, CaseIterable, Sendable {
    case creator
    case venue
    case collective
    case publication
    case eventSeries = "event_series"
    case brand
    case concept
    case event
    case organization
    case scene
    case unknown
}

enum BriefPeriodType: String, Codable, CaseIterable, Sendable {
    case daily
}

enum SignalMovement: String, Codable, CaseIterable, Sendable {
    case new
    case rising
    case stable
    case declining

    nonisolated var label: String {
        rawValue.capitalized
    }
}

enum SignalMaturity: String, Codable, CaseIterable, Sendable {
    case earlyEmergence = "early_emergence"
    case advancing
    case peaking
    case cooling
    case stalled

    nonisolated var label: String {
        switch self {
        case .earlyEmergence: "Early Emergence"
        case .advancing: "Advancing"
        case .peaking: "Peaking"
        case .cooling: "Cooling"
        case .stalled: "Stalled"
        }
    }
}

enum SignalLifecycleState: String, Codable, CaseIterable, Sendable {
    case emerging
    case advancing
    case peaked
    case cooling
    case failed
    case disappeared

    nonisolated var label: String {
        switch self {
        case .emerging: "Emerging"
        case .advancing: "Advancing"
        case .peaked: "Peaked"
        case .cooling: "Cooling"
        case .failed: "Failed"
        case .disappeared: "Disappeared"
        }
    }
}

enum DownstreamOutcomeTier: String, Codable, CaseIterable, Sendable {
    case institutionalPickup = "institutional_pickup"
    case largerVenueTier = "larger_venue_tier"
    case majorEditorialCoverage = "major_editorial_coverage"
    case crossDomainAppearance = "cross_domain_appearance"

    nonisolated var label: String {
        switch self {
        case .institutionalPickup: "Institutional Pickup"
        case .largerVenueTier: "Larger Venue Tier"
        case .majorEditorialCoverage: "Major Editorial Coverage"
        case .crossDomainAppearance: "Cross-Domain Appearance"
        }
    }
}

enum ConversionState: String, Codable, CaseIterable, Sendable {
    case pending
    case converted
    case stalledBeforeConversion = "stalled_before_conversion"
    case neverConverted = "never_converted"

    nonisolated var label: String {
        switch self {
        case .pending: "Pending"
        case .converted: "Converted"
        case .stalledBeforeConversion: "Stalled Before Conversion"
        case .neverConverted: "Never Converted"
        }
    }
}

enum WatchlistStage: String, Codable, CaseIterable, Sendable {
    case early
    case forming
    case corroborating

    nonisolated var label: String {
        switch self {
        case .early: "Early Watch"
        case .forming: "Forming"
        case .corroborating: "Corroborating"
        }
    }
}

enum SourceInfluenceScope: String, Codable, CaseIterable, Sendable {
    case source
    case family

    nonisolated var label: String {
        switch self {
        case .source: "Source"
        case .family: "Source Family"
        }
    }
}

struct SourceRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var moduleID: String
    var moduleName: String
    var sourceFamilyID: String
    var sourceFamilyName: String
    var domain: CulturalDomain
    var classification: SourceClassification
    var tier: SourceTier
    var baseURL: String
    var city: SourceCity
    var parserType: ParserType
    var enabled: Bool
    var justification: String
    var refreshCadenceMinutes: Int
    var failureBackoffMinutes: Int
    var lastAttemptAt: Date?
    var backoffUntil: Date?
    var consecutiveFailures: Int
    var lastSuccessAt: Date?

    var doctrineProfile: SourceDoctrineProfile {
        SourceDoctrineProfile(
            whyEarly: SourceDoctrineProfile.whyEarly(for: self),
            whySelective: SourceDoctrineProfile.whySelective(for: self),
            corroborationRole: SourceDoctrineProfile.corroborationRole(for: self)
        )
    }
}

struct SourceDoctrineProfile: Hashable, Sendable {
    let whyEarly: String
    let whySelective: String
    let corroborationRole: String

    fileprivate static func whyEarly(for source: SourceRecord) -> String {
        switch source.id {
        case "short-of-the-week":
            return "Short-film work often appears here before broader film press or institutional pickup catches up."
        case "vimeo-staff-picks":
            return "Visual voices and short-form directors often surface here before wider critical or platform consensus forms."
        case "bandcamp-la-discover", "bandcamp-la-tag", "bandcamp-daily":
            return "Bandcamp tends to surface artists, labels, and scenes before broader music consensus hardens."
        case "the-quietus", "crack-magazine", "brooklyn-vegan":
            return "This lane tends to notice artist and scene movement before wider music coverage flattens it into consensus."
        case "hyperallergic", "carla", "artforum", "artnews":
            return "Artists, institutions, and art-world conversations often show up here before they become broader cultural consensus."
        case "i-d", "hypebeast", "creative-review":
            return "Aesthetic and design movement tends to register here before broader commercial or mainstream adoption."
        case "film-comment":
            return "Directors, festivals, and film discourse often gather here before mainstream film coverage settles on them."
        case "kxlu":
            return "College and community radio often catches scene movement before larger tastemakers smooth it into consensus."
        default:
            switch source.classification {
            case .discovery:
                return "This source sits close to first visibility, where movement can appear before broader validation."
            case .community:
                return "This source is close to live scenes and often catches movement before mainstream editorial attention."
            case .editorial:
                return "This source can catch movement early enough to matter if its taste and scene proximity are strong."
            case .venue:
                return "Venue activity can reveal early momentum before a broader cluster has fully formed."
            case .institutional:
                return "Institutional lanes matter when they expose movement before it becomes broadly legible elsewhere."
            case .commercialScaling:
                return "This lane can show when something begins scaling beyond its earliest niche footing."
            }
        }
    }

    fileprivate static func whySelective(for source: SourceRecord) -> String {
        switch source.id {
        case "short-of-the-week", "vimeo-staff-picks":
            return "It is editorially selected rather than an open upload firehose, so appearance here already means something."
        case "kxlu":
            return "The station’s programming reflects scene taste and curation rather than a raw inventory of everything available."
        case "bandcamp-la-discover", "bandcamp-la-tag":
            return "It is still broad, but it is narrowed by scene tagging and discovery framing rather than general music coverage."
        case "the-smell", "zebulon", "lodge-room", "the-echo-home", "the-bellwether-home":
            return "A venue calendar is only useful because the room itself is a meaningful selector, not because calendars are inherently strong."
        default:
            switch source.classification {
            case .discovery:
                return "It is selective enough to function as a real filter instead of a generic public firehose."
            case .community:
                return "Its attention reflects scene participation and curation rather than generic publishing volume."
            case .editorial:
                return "Its value depends on acting like a tastemaker filter, not just another respectable publication."
            case .venue:
                return "The room itself is the filter, which is why a calendar here can still mean something."
            case .institutional:
                return "It only belongs when the institution is acting as a real cultural selector rather than a generic program archive."
            case .commercialScaling:
                return "It is useful only when the lane signals meaningful selection pressure rather than broad marketplace volume."
            }
        }
    }

    fileprivate static func corroborationRole(for source: SourceRecord) -> String {
        switch source.classification {
        case .discovery:
            return "Best used as an early lane that needs confirmation from editorial, community, venue, or another distinct source family."
        case .community:
            return "Best used to confirm whether a live scene or subculture is really moving beyond a single tastemaker."
        case .editorial:
            return "Best used to confirm that movement is being noticed outside the original discovery lane."
        case .venue:
            return "Best used as a supporting lane once an artist, event, or scene starts showing real local traction."
        case .institutional:
            return "Best used as later-stage confirmation that a movement is spreading into stronger cultural infrastructure."
        case .commercialScaling:
            return "Best used to show that something is moving beyond niche detection and beginning to scale."
        }
    }
}

struct SnapshotRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let startedAt: Date
    var completedAt: Date?
    var status: SnapshotStatus
    var itemCount: Int
    var errorMessage: String?
}

struct ObservationRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let snapshotID: String
    let canonicalEntityID: String
    let domain: CulturalDomain
    let entityType: EntityType
    let externalIDOrHash: String
    let title: String
    let subtitle: String?
    let url: String
    let authorOrArtist: String?
    let tags: [String]
    let location: String?
    let publishedAt: Date?
    let scrapedAt: Date
    let excerpt: String?
    let normalizedEntityName: String
    let rawPayload: String

    var eventInstanceKey: String? {
        guard entityType == .event || entityType == .eventSeries || tags.contains("event") || tags.contains("venue-calendar") else {
            return nil
        }

        let entityName = authorOrArtist ?? title
        return HTMLSupport.eventInstanceKey(
            entityName: entityName,
            publishedAt: publishedAt,
            location: location,
            url: url
        )
    }
}

struct SignalCandidateRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let canonicalEntityID: String
    let domain: CulturalDomain
    let canonicalName: String
    let entityType: EntityType
    let firstSeenAt: Date
    let latestSeenAt: Date
    let sourceCount: Int
    let observationCount: Int
    let currentSourceCount: Int
    let currentSourceFamilyCount: Int
    let currentObservationCount: Int
    let historicalSourceCount: Int
    let historicalObservationCount: Int
    let growthScore: Double
    let diversityScore: Double
    let repeatAppearanceScore: Double
    let progressionScore: Double
    let saturationScore: Double
    let emergenceScore: Double
    let confidence: Double
    let movement: SignalMovement
    let maturity: SignalMaturity
    let lifecycleState: SignalLifecycleState
    let conversionState: ConversionState
    let outcomeTiers: [DownstreamOutcomeTier]
    let supportingSourceIDs: [String]
    let progressionStages: [SourceClassification]
    let progressionPattern: String
    let movementSummary: String
    let maturitySummary: String
    let lifecycleSummary: String
    let conversionSummary: String
    let pathwaySummary: String
    let sourceInfluenceSummary: String
    let progressionSummary: String
    let evidenceSummary: String
}

struct CanonicalEntityRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let domain: CulturalDomain
    let entityType: EntityType
    let aliases: [String]
    let mergeConfidence: Double
    let mergeSummary: String
}

struct EntityAliasRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let canonicalEntityID: String
    let aliasText: String
    let normalizedAlias: String
    let sourceID: String?
}

struct EntitySourceRoleRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let canonicalEntityID: String
    let sourceID: String
    let sourceClassification: SourceClassification
    let firstSeenAt: Date
    let lastSeenAt: Date
    let appearanceCount: Int
}

struct EntityStageSnapshotRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let canonicalEntityID: String
    let date: Date
    let stage: SourceClassification
    let sourceCount: Int
    let signalScore: Double
}

struct EntityHistoryRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let canonicalEntityID: String
    let canonicalName: String
    let domain: CulturalDomain
    let entityType: EntityType
    let firstSeenAt: Date
    let lastSeenAt: Date
    let appearanceCount: Int
    let sourceDiversity: Int
    let lifecycleState: SignalLifecycleState
    let lifecycleSummary: String
    let conversionState: ConversionState
    let conversionSummary: String
}

struct SignalRunRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let runAt: Date
    let canonicalEntityID: String
    let canonicalName: String
    let domain: CulturalDomain
    let entityType: EntityType
    let rank: Int
    let score: Double
    let supportingSourceIDs: [String]
    let observationCount: Int
    let sourceCount: Int
    let currentSourceCount: Int
    let currentSourceFamilyCount: Int
    let currentObservationCount: Int
    let historicalSourceCount: Int
    let historicalObservationCount: Int
    let movement: SignalMovement
    let maturity: SignalMaturity
    let lifecycleState: SignalLifecycleState
    let conversionState: ConversionState
    let outcomeTiers: [DownstreamOutcomeTier]
    let progressionPattern: String
    let explanation: String
    let lifecycleSummary: String
    let conversionSummary: String
    let sourceInfluenceSummary: String
}

struct PathwayHistoryRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let runAt: Date
    let canonicalEntityID: String
    let pathwayPattern: String
    let domain: CulturalDomain
    let lifecycleState: SignalLifecycleState
    let conversionState: ConversionState
    let signalScore: Double
}

struct PathwayStatRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let pathwayPattern: String
    let domain: CulturalDomain
    let sampleCount: Int
    let advancingCount: Int
    let peakedCount: Int
    let coolingCount: Int
    let failedCount: Int
    let disappearedCount: Int
    let successWeight: Double
    let failureWeight: Double
    let conversionCount: Int
    let stalledConversionCount: Int
    let neverConvertedCount: Int
    let conversionWeight: Double
    let predictiveScore: Double
    let summary: String
}

struct SourceInfluenceStatRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let scope: SourceInfluenceScope
    let scopeKey: String
    let displayName: String
    let domain: CulturalDomain
    let sampleCount: Int
    let advancingCount: Int
    let peakedCount: Int
    let failedCount: Int
    let disappearedCount: Int
    let conversionCount: Int
    let stalledConversionCount: Int
    let neverConvertedCount: Int
    let averageSignalScore: Double
    let predictiveScore: Double
    let summary: String
}

struct OutcomeConfirmationRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let canonicalEntityID: String
    let outcomeTier: DownstreamOutcomeTier
    let confirmedAt: Date
    let sourceIDs: [String]
    let summary: String
}

struct BriefCitation: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let signalName: String
    let sourceName: String
    let observationTitle: String
    let url: String
    let note: String
}

struct BriefRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let generatedAt: Date
    let title: String
    let body: String
    let citationsPayload: [BriefCitation]
    let periodType: BriefPeriodType
}

struct WatchlistCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let canonicalEntityID: String
    let title: String
    let domain: CulturalDomain
    let entityType: EntityType
    let stage: WatchlistStage
    let sourceIDs: [String]
    let sourceFamilyCount: Int
    let observationCount: Int
    let historicalMentionCount: Int
    let historicalSourceDiversity: Int
    let latestSeenAt: Date
    let summary: String
    let note: String
    let whyNow: String
    let upgradeTrigger: String
    let score: Double
}

struct SourceStatusRecord: Identifiable, Hashable, Sendable {
    let id: String
    let source: SourceRecord
    let latestSnapshot: SnapshotRecord?
}

struct SourceSeed: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let moduleID: String
    let moduleName: String
    let sourceFamilyID: String
    let sourceFamilyName: String
    let domain: CulturalDomain
    let classification: SourceClassification
    let tier: SourceTier
    let baseURL: String
    let city: SourceCity
    let parserType: ParserType
    let enabled: Bool
    let justification: String
    let refreshCadenceMinutes: Int
    let failureBackoffMinutes: Int

    init(
        id: String,
        name: String,
        moduleID: String,
        moduleName: String,
        sourceFamilyID: String? = nil,
        sourceFamilyName: String? = nil,
        domain: CulturalDomain,
        classification: SourceClassification,
        tier: SourceTier,
        baseURL: String,
        city: SourceCity,
        parserType: ParserType,
        enabled: Bool,
        justification: String,
        refreshCadenceMinutes: Int,
        failureBackoffMinutes: Int
    ) {
        self.id = id
        self.name = name
        self.moduleID = moduleID
        self.moduleName = moduleName
        self.sourceFamilyID = sourceFamilyID ?? Self.defaultSourceFamilyID(from: baseURL)
        self.sourceFamilyName = sourceFamilyName ?? Self.defaultSourceFamilyName(from: baseURL)
        self.domain = domain
        self.classification = classification
        self.tier = tier
        self.baseURL = baseURL
        self.city = city
        self.parserType = parserType
        self.enabled = enabled
        self.justification = justification
        self.refreshCadenceMinutes = refreshCadenceMinutes
        self.failureBackoffMinutes = failureBackoffMinutes
    }

    private static func defaultSourceFamilyID(from baseURL: String) -> String {
        guard let host = URL(string: baseURL)?.host?.lowercased() else {
            return "independent"
        }

        let normalized = host
            .replacingOccurrences(of: "www.", with: "", options: [.anchored])
            .replacingOccurrences(of: "m.", with: "", options: [.anchored])

        if normalized.hasSuffix(".bandcamp.com") || normalized == "bandcamp.com" {
            return "bandcamp"
        }

        return normalized.replacingOccurrences(of: ".", with: "-")
    }

    private static func defaultSourceFamilyName(from baseURL: String) -> String {
        guard let host = URL(string: baseURL)?.host?.lowercased() else {
            return "Independent"
        }

        let normalized = host
            .replacingOccurrences(of: "www.", with: "", options: [.anchored])
            .replacingOccurrences(of: "m.", with: "", options: [.anchored])

        if normalized.hasSuffix(".bandcamp.com") || normalized == "bandcamp.com" {
            return "Bandcamp"
        }

        return normalized
    }
}

struct ObservationDraft: Sendable {
    let domain: CulturalDomain
    let entityType: EntityType
    let externalIDOrHash: String
    let title: String
    let subtitle: String?
    let url: String
    let authorOrArtist: String?
    let tags: [String]
    let location: String?
    let publishedAt: Date?
    let scrapedAt: Date
    let excerpt: String?
    let normalizedEntityName: String
    let rawPayload: String

    var eventInstanceKey: String? {
        guard entityType == .event || entityType == .eventSeries || tags.contains("event") || tags.contains("venue-calendar") else {
            return nil
        }

        let entityName = authorOrArtist ?? title
        return HTMLSupport.eventInstanceKey(
            entityName: entityName,
            publishedAt: publishedAt,
            location: location,
            url: url
        )
    }
}

struct RefreshReport: Sendable {
    let startedAt: Date
    let completedAt: Date
    let snapshots: [SnapshotRecord]
}
