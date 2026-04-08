import Foundation
import Combine

enum MalcomeLoadingMessages {

    // MARK: - Message Pool

    static let musicMessages = [
        "Listening to a DAT tape someone left at the office",
        "Arguing about the Undertones at a record fair",
        "Making a mixtape nobody asked for",
        "Flipping through the new arrivals bin",
        "At the back of a show, watching who else showed up",
        "On hold with a label that doesn't know it matters yet",
        "Reading Melody Maker in a venue green room",
        "Annotating a Xeroxed fanzine from 1987",
        "On the phone with a DJ in Amsterdam",
        "Rewinding a cassette with a pencil",
        "At a listening party nobody else was invited to",
        "Asking the guy at the record shop what he's been playing",
        "Sorting through a dead DJ's record collection",
        "On a night bus with headphones and no destination",
        "Reading a setlist someone left on the floor",
        "In a basement that smells like dry ice and possibility",
        "Waiting for the support act nobody came to see",
        "Taping over something we'll both regret",
        "Checking if the B-side is better than the A-side",
        "Convincing the soundman to turn it up",
    ]

    static let filmMessages = [
        "Sitting through the credits to see who did the music",
        "At a screening nobody reviewed",
        "Reading a treatment nobody optioned yet",
        "On the phone with a festival programmer in Rotterdam",
        "Watching a short film on a laptop in a café",
        "In the back of a cinematheque, taking notes",
        "Reading the trades between the lines",
        "At a Q&A where the director said too much",
        "In an editing suite at 3am",
        "Watching a rough cut nobody else has seen",
        "Checking the print schedule at a repertory cinema",
        "Reading a subtitle file to see what got lost",
    ]

    static let artMessages = [
        "At a gallery opening, pretending to look at the art",
        "Reading a press release between the lines",
        "On the phone with a gallerist who won't say who yet",
        "In a studio that isn't open to the public",
        "Looking at slides nobody submitted to the right people yet",
        "At a degree show, moving fast",
        "Reading an artist statement that actually says something",
        "In a storage unit full of work that hasn't shown yet",
        "Walking through a group show where one piece changed everything",
        "Checking if the catalogue essay matches the work",
    ]

    static let generalMessages = [
        "Dancing with Madge at The Mudd Club",
        "Reading the bathroom walls at CBGBs",
        "Reading the NME on a flight to somewhere interesting",
        "On the phone with someone in Tokyo",
        "Watching a set at a venue you've never heard of",
        "In a conversation that started three cities ago",
        "Reading something that hasn't been indexed yet",
        "Following a thread that most people dropped",
        "At a party where nobody's checking their phone",
        "Somewhere between the opening act and the headliner",
        "In a city you'd never expect this to come from",
        "On a terrace at dawn, still talking about last night",
        "Reading a fax from 1993 that turned out to be right",
        "At a residency nobody applied to twice",
        "In a conversation that will matter in six months",
        "Somewhere offline, which is where things still start",
        "Checking the guestlist for a thing that doesn't have one",
        "Looking at a map of a scene that doesn't know it's a scene yet",
        "Making a call that won't make sense for another year",
        "Waiting for a source to call back",
        "Checking the guest list at a show that sold out in 4 minutes",
        "On the phone with a producer whose name you'll know in six months",
        "At a soundcheck nobody was supposed to attend",
        "Reading a review that got it right three years early",
        "In a city you'd never expect this to start from",
        "Watching the second night because the first one was too obvious",
        "At a residency that isn't on the website yet",
        "On a train between two cities that both think they discovered it",
        "In a record shop where the owner doesn't tell everyone everything",
        "Somewhere between the tip and the confirmation",
    ]

    static let allMessages: [String] = musicMessages + filmMessages + artMessages + generalMessages

    // MARK: - Domain-Weighted Selection

    static func randomMessage(activeDomains: Set<CulturalDomain> = []) -> String {
        if activeDomains.isEmpty {
            return allMessages.randomElement() ?? generalMessages[0]
        }

        // Build a weighted pool favoring active domains
        var pool: [String] = generalMessages
        if activeDomains.contains(.music) { pool += musicMessages }
        if activeDomains.contains(.film) { pool += filmMessages }
        if activeDomains.contains(.art) { pool += artMessages }

        // Always include some general flavor
        return pool.randomElement() ?? generalMessages[0]
    }
}

// MARK: - Loading Message Publisher

@MainActor
final class LoadingMessageProvider: ObservableObject {
    @Published private(set) var currentMessage: String = ""

    private var timer: Timer?
    private var activeDomains: Set<CulturalDomain> = []
    private var usedMessages: Set<String> = []

    func start(activeDomains: Set<CulturalDomain> = []) {
        self.activeDomains = activeDomains
        usedMessages.removeAll()
        currentMessage = nextMessage()
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentMessage = self?.nextMessage() ?? ""
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentMessage = ""
    }

    private func nextMessage() -> String {
        // Avoid repeats until pool is exhausted
        let pool = activeDomains.isEmpty
            ? MalcomeLoadingMessages.allMessages
            : MalcomeLoadingMessages.allMessages.filter { msg in
                !usedMessages.contains(msg)
            }

        if pool.isEmpty {
            usedMessages.removeAll()
            return MalcomeLoadingMessages.randomMessage(activeDomains: activeDomains)
        }

        let message = MalcomeLoadingMessages.randomMessage(activeDomains: activeDomains)
        usedMessages.insert(message)
        return message
    }
}
