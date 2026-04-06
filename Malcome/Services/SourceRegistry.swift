import Foundation

protocol SourcePack: Sendable {
    var id: String { get }
    var name: String { get }
    func seeds() -> [SourceSeed]
}

struct SourceRegistry {
    func initialSeeds() -> [SourceSeed] {
        packs.flatMap { $0.seeds() }
    }

    private var packs: [any SourcePack] {
        [
            LosAngelesMusicPack(),
            LosAngelesArtPack(),
            CrossCityEditorialPack(),
            CreatorPlatformPack(),
            SupportSignalPack(),
        ]
    }
}

private struct LosAngelesMusicPack: SourcePack {
    let id = "la-music-core"
    let name = "LA Music Core"

    func seeds() -> [SourceSeed] {
        [
            SourceSeed(
                id: "bandcamp-la-discover",
                name: "Bandcamp LA Discover",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .discovery,
                tier: .a,
                baseURL: "https://bandcamp.com/discover/los-angeles",
                city: .losAngeles,
                parserType: .bandcampTag,
                enabled: true,
                justification: "Bandcamp discover pages often surface artists before broader scene consensus catches up.",
                refreshCadenceMinutes: 360,
                failureBackoffMinutes: 180
            ),
            SourceSeed(
                id: "bandcamp-la-tag",
                name: "Bandcamp LA Tag",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .discovery,
                tier: .a,
                baseURL: "https://bandcamp.com/tag/los-angeles",
                city: .losAngeles,
                parserType: .bandcampTag,
                enabled: true,
                justification: "Bandcamp tag pages are an upstream map of self-identifying local scenes and niche releases.",
                refreshCadenceMinutes: 360,
                failureBackoffMinutes: 180
            ),
            SourceSeed(
                id: "the-smell",
                name: "The Smell",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .venue,
                tier: .a,
                baseURL: "https://thesmell.org/events",
                city: .losAngeles,
                parserType: .venueCalendar,
                enabled: true,
                justification: "The Smell reliably catches early DIY acts before they graduate into wider LA visibility.",
                refreshCadenceMinutes: 240,
                failureBackoffMinutes: 120
            ),
            SourceSeed(
                id: "zebulon",
                name: "Zebulon",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .venue,
                tier: .a,
                baseURL: "https://zebulon.la/",
                city: .losAngeles,
                parserType: .diceEvents,
                enabled: true,
                justification: "Zebulon’s bookings are a strong indicator of crossover between underground music, art, and scene energy.",
                refreshCadenceMinutes: 240,
                failureBackoffMinutes: 120
            ),
            SourceSeed(
                id: "lodge-room",
                name: "Lodge Room",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .venue,
                tier: .a,
                baseURL: "https://www.lodgeroomhlp.com/",
                city: .losAngeles,
                parserType: .venueCalendar,
                enabled: true,
                justification: "Lodge Room often spots rising artists in the phase between cult status and broader breakout.",
                refreshCadenceMinutes: 240,
                failureBackoffMinutes: 120
            ),
            SourceSeed(
                id: "permanent-records-roadhouse",
                name: "Permanent Records Roadhouse",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .venue,
                tier: .a,
                baseURL: "https://roadhouse.permanentrecordsla.com/",
                city: .losAngeles,
                parserType: .stub,
                enabled: true,
                justification: "Permanent Records Roadhouse is a high-signal node for local scene adjacency, crate-digger taste, and emerging live bills.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 480
            ),
            SourceSeed(
                id: "aquarium-drunkard",
                name: "Aquarium Drunkard",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .editorial,
                tier: .a,
                baseURL: "https://aquariumdrunkard.com/",
                city: .losAngeles,
                parserType: .genericDiscussion,
                enabled: true,
                justification: "Aquarium Drunkard is valuable for surfacing left-of-center artists and adjacent scenes with strong downstream influence.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "kxlu",
                name: "KXLU",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .community,
                tier: .a,
                baseURL: "https://kxlu.com/",
                city: .losAngeles,
                parserType: .wordPressPosts,
                enabled: true,
                justification: "KXLU catches college-radio and DIY scene movement before larger tastemakers smooth it into consensus.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
        ]
    }
}

private struct LosAngelesArtPack: SourcePack {
    let id = "la-art-core"
    let name = "LA Art Core"

    func seeds() -> [SourceSeed] {
        [
            SourceSeed(
                id: "arts-2220",
                name: "2220 Arts",
                moduleID: id,
                moduleName: name,
                domain: .art,
                classification: .institutional,
                tier: .a,
                baseURL: "https://2220arts.org/",
                city: .losAngeles,
                parserType: .stub,
                enabled: true,
                justification: "2220 Arts is useful for catching interdisciplinary and left-field cultural programming before it goes mainstream.",
                refreshCadenceMinutes: 720,
                failureBackoffMinutes: 720
            ),
            SourceSeed(
                id: "hyperallergic",
                name: "Hyperallergic",
                moduleID: id,
                moduleName: name,
                domain: .art,
                classification: .editorial,
                tier: .a,
                baseURL: "https://hyperallergic.com/",
                city: .losAngeles,
                parserType: .genericDiscussion,
                enabled: true,
                justification: "Hyperallergic is a strong upstream art editorial signal for artists, institutions, and concepts before they harden into mainstream cultural consensus.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "carla",
                name: "CARLA",
                moduleID: id,
                moduleName: name,
                domain: .art,
                classification: .editorial,
                tier: .a,
                baseURL: "https://contemporaryartreview.la/",
                city: .losAngeles,
                parserType: .wordPressPosts,
                enabled: true,
                justification: "CARLA is a sharp early-reading publication for the Los Angeles art world, especially around artists, galleries, and scene conversations before broader validation.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
        ]
    }
}

private struct CrossCityEditorialPack: SourcePack {
    let id = "cross-city-editorial"
    let name = "Cross-City Editorial"

    func seeds() -> [SourceSeed] {
        [
            SourceSeed(
                id: "bandcamp-daily",
                name: "Bandcamp Daily",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .editorial,
                tier: .a,
                baseURL: "https://daily.bandcamp.com/feed",
                city: .global,
                parserType: .rssFeed,
                enabled: true,
                justification: "Bandcamp Daily is a strong tastemaker lane for emerging artists, labels, and scenes before those movements flatten into wider consensus.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "film-comment",
                name: "Film Comment",
                moduleID: id,
                moduleName: name,
                domain: .film,
                classification: .editorial,
                tier: .a,
                baseURL: "https://www.filmcomment.com/",
                city: .newYork,
                parserType: .wordPressPosts,
                enabled: true,
                justification: "Film Comment is a high-signal film editorial source that often surfaces directors, festivals, and critical movements before they flatten into mainstream film coverage.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "brooklyn-vegan",
                name: "BrooklynVegan",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .editorial,
                tier: .a,
                baseURL: "https://www.brooklynvegan.com/feed/",
                city: .newYork,
                parserType: .rssFeed,
                enabled: true,
                justification: "BrooklynVegan is a strong New York music tastemaker for scenes, lineups, and artist movement before those patterns flatten into broader consensus.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "the-quietus",
                name: "The Quietus",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .editorial,
                tier: .a,
                baseURL: "https://thequietus.com/",
                city: .london,
                parserType: .wordPressPosts,
                enabled: true,
                justification: "The Quietus is a high-signal tastemaker for left-field music, scenes, and criticism before those movements flatten into broader consensus.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "crack-magazine",
                name: "Crack Magazine",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .editorial,
                tier: .a,
                baseURL: "https://crackmagazine.net/feed/",
                city: .london,
                parserType: .rssFeed,
                enabled: true,
                justification: "Crack Magazine is a strong cross-scene tastemaker for experimental, club, and style-adjacent music culture before those threads become broader consensus.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "artnews",
                name: "ARTnews",
                moduleID: id,
                moduleName: name,
                domain: .art,
                classification: .editorial,
                tier: .b,
                baseURL: "https://www.artnews.com/",
                city: .newYork,
                parserType: .wordPressPosts,
                enabled: true,
                justification: "ARTnews is useful for catching artists, institutions, and art-world inflection points as they begin moving from specialist attention toward broader cultural visibility.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "artforum",
                name: "Artforum",
                moduleID: id,
                moduleName: name,
                domain: .art,
                classification: .editorial,
                tier: .a,
                baseURL: "https://www.artforum.com/feed/",
                city: .newYork,
                parserType: .rssFeed,
                enabled: true,
                justification: "Artforum remains a meaningful art-world tastemaker for artists, institutions, and criticism that often signal where serious cultural attention is consolidating next.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "i-d",
                name: "i-D",
                moduleID: id,
                moduleName: name,
                domain: .fashion,
                classification: .editorial,
                tier: .a,
                baseURL: "https://i-d.co/feed/",
                city: .london,
                parserType: .rssFeed,
                enabled: true,
                justification: "i-D is a long-running fashion and youth-culture tastemaker that often catches emerging aesthetics, scenes, and personalities before they harden into mainstream style consensus.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "hypebeast",
                name: "Hypebeast",
                moduleID: id,
                moduleName: name,
                domain: .fashion,
                classification: .editorial,
                tier: .a,
                baseURL: "https://hypebeast.com/feed",
                city: .global,
                parserType: .rssFeed,
                enabled: true,
                justification: "Hypebeast is useful for early streetwear, design, sneaker, and culture crossover signals when those lanes are moving before broader mass adoption.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "creative-review",
                name: "Creative Review",
                moduleID: id,
                moduleName: name,
                domain: .design,
                classification: .editorial,
                tier: .a,
                baseURL: "https://www.creativereview.co.uk/feed/",
                city: .london,
                parserType: .rssFeed,
                enabled: true,
                justification: "Creative Review is a long-running design tastemaker that often catches visual-language shifts, studios, and creative voices before those aesthetics flatten into broader commercial consensus.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
        ]
    }
}

private struct CreatorPlatformPack: SourcePack {
    let id = "creator-platforms"
    let name = "Creator Platforms"

    func seeds() -> [SourceSeed] {
        [
            SourceSeed(
                id: "vimeo-staff-picks",
                name: "Vimeo Staff Picks",
                moduleID: id,
                moduleName: name,
                domain: .film,
                classification: .discovery,
                tier: .a,
                baseURL: "https://vimeo.com/channels/staffpicks/videos/rss",
                city: .global,
                parserType: .rssFeed,
                enabled: true,
                justification: "Vimeo Staff Picks is a curated creator-platform lane for short films and video work that often surfaces directors and visual voices before broader institutional pickup.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
            SourceSeed(
                id: "short-of-the-week",
                name: "Short of the Week",
                moduleID: id,
                moduleName: name,
                domain: .film,
                classification: .discovery,
                tier: .a,
                baseURL: "https://www.shortoftheweek.com/feed/",
                city: .global,
                parserType: .rssFeed,
                enabled: true,
                justification: "Short of the Week is a curated short-film tastemaker that often surfaces directors, visual styles, and festival-bound work before wider film coverage locks in around them.",
                refreshCadenceMinutes: 480,
                failureBackoffMinutes: 240
            ),
        ]
    }
}

private struct SupportSignalPack: SourcePack {
    let id = "support-signals"
    let name = "Support Signals"

    func seeds() -> [SourceSeed] {
        [
            SourceSeed(
                id: "kcrw-events",
                name: "KCRW Events",
                moduleID: id,
                moduleName: name,
                domain: .mixed,
                classification: .editorial,
                tier: .a,
                baseURL: "https://www.kcrw.com/events",
                city: .losAngeles,
                parserType: .genericDiscussion,
                enabled: true,
                justification: "KCRW event curation often reflects which local acts and venues are beginning to matter outside their immediate niche.",
                refreshCadenceMinutes: 720,
                failureBackoffMinutes: 720
            ),
            SourceSeed(
                id: "kcrw-music",
                name: "KCRW Music Coverage",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .editorial,
                tier: .a,
                baseURL: "https://www.kcrw.com/music",
                city: .losAngeles,
                parserType: .genericDiscussion,
                enabled: true,
                justification: "KCRW music coverage is a strong editorial filter for artists and scenes approaching wider recognition.",
                refreshCadenceMinutes: 720,
                failureBackoffMinutes: 720
            ),
            SourceSeed(
                id: "la-record",
                name: "LA Record",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .editorial,
                tier: .a,
                baseURL: "https://larecord.com/",
                city: .losAngeles,
                parserType: .genericDiscussion,
                enabled: true,
                justification: "LA Record has deep local scene proximity and often notices shifts before institutional tastemakers do.",
                refreshCadenceMinutes: 720,
                failureBackoffMinutes: 360
            ),
            SourceSeed(
                id: "the-echo-home",
                name: "The Echo",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .venue,
                tier: .b,
                baseURL: "https://www.theecho.com/",
                city: .losAngeles,
                parserType: .venueCalendar,
                enabled: true,
                justification: "The Echo is a dependable support signal for acts already starting to accumulate real local momentum.",
                refreshCadenceMinutes: 240,
                failureBackoffMinutes: 120
            ),
            SourceSeed(
                id: "the-bellwether-home",
                name: "The Bellwether",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .venue,
                tier: .b,
                baseURL: "https://thebellwetherla.com/",
                city: .losAngeles,
                parserType: .venueCalendar,
                enabled: true,
                justification: "The Bellwether is a reliable support venue for tracking artists as they begin to scale beyond micro-scene rooms.",
                refreshCadenceMinutes: 240,
                failureBackoffMinutes: 120
            ),
            SourceSeed(
                id: "resident-advisor-la",
                name: "Resident Advisor LA",
                moduleID: id,
                moduleName: name,
                domain: .nightlife,
                classification: .community,
                tier: .b,
                baseURL: "https://ra.co/events/us/losangeles",
                city: .losAngeles,
                parserType: .residentAdvisor,
                enabled: true,
                justification: "Resident Advisor is a useful support signal for nightlife and dance culture once a scene starts spreading across venues.",
                refreshCadenceMinutes: 720,
                failureBackoffMinutes: 720
            ),
            SourceSeed(
                id: "dice-la",
                name: "Dice Los Angeles",
                moduleID: id,
                moduleName: name,
                domain: .music,
                classification: .commercialScaling,
                tier: .b,
                baseURL: "https://dice.fm/browse/los-angeles/music",
                city: .losAngeles,
                parserType: .stub,
                enabled: true,
                justification: "Dice feeds can help confirm when underground venue activity starts consolidating into a broader booking pattern.",
                refreshCadenceMinutes: 720,
                failureBackoffMinutes: 720
            ),
        ]
    }
}
