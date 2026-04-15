import Foundation
import FoundationModels

/// A/B test comparing Pipeline A (SignalEngine + DraftComposer) against
/// Pipeline B (small-chunk AFM calls assembled deterministically).
/// Runs 50 comparison pairs from historical database observations.
/// Does not modify any existing pipeline code.
enum ABTest {

    // MARK: - Output Types

    struct PairResult: Codable {
        let pairID: Int
        let dateSlice: String
        let sourceCount: Int
        let sourcesUsed: [String]
        let pipelineA: BriefOutput
        let pipelineB: BriefOutput
    }

    struct BriefOutput: Codable {
        let title: String
        let brief: String
        let error: String?
    }

    struct TestReport: Codable {
        let runAt: String
        let totalPairs: Int
        let completedPairs: Int
        let pairs: [PairResult]
    }

    // MARK: - Excluded sources (Bandcamp self-promotion)

    private static let excludedSourceIDs: Set<String> = [
        "bandcamp-la-tag",
        "bandcamp-la-discover",
    ]

    // MARK: - Run

    static func run(repository: AppRepository, signalEngine: SignalEngine, briefComposer: BriefComposer) async -> TestReport {
        var pairs: [PairResult] = []

        // Get all observations and sources
        let allObservations: [ObservationRecord]
        let allSources: [SourceRecord]
        do {
            allObservations = try await repository.fetchObservations()
            allSources = try await repository.fetchSources()
        } catch {
            return TestReport(runAt: ISO8601DateFormatter().string(from: .now), totalPairs: 0, completedPairs: 0, pairs: [])
        }

        let sourcesByID = Dictionary(uniqueKeysWithValues: allSources.map { ($0.id, $0) })

        // Filter out excluded sources
        let editorialObservations = allObservations.filter { obs in
            !excludedSourceIDs.contains(obs.sourceID)
        }

        // Group observations by date (day granularity)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let grouped = Dictionary(grouping: editorialObservations) { obs in
            dateFormatter.string(from: obs.scrapedAt)
        }

        // Get date slices with enough diversity (3+ source families)
        let viableSlices = grouped.filter { _, observations in
            let families = Set(observations.compactMap { obs -> String? in
                sourcesByID[obs.sourceID]?.sourceFamilyID
            })
            return observations.count >= 5 && families.count >= 2
        }.sorted { $0.key > $1.key }

        // Take up to 50 slices
        let slicesToTest = Array(viableSlices.prefix(50))

        for (index, (dateStr, sliceObservations)) in slicesToTest.enumerated() {
            let sampled = Array(sliceObservations.shuffled().prefix(25))
            let sourcesUsed = Array(Set(sampled.compactMap { sourcesByID[$0.sourceID]?.name })).sorted()

            // Pipeline A: existing engine
            let pipelineAResult = await runPipelineA(
                observations: allObservations,  // Full history for context
                dateSlice: dateStr,
                sourcesByID: sourcesByID,
                repository: repository,
                signalEngine: signalEngine,
                briefComposer: briefComposer
            )

            // Pipeline B: small-chunk AFM
            let pipelineBResult = await runPipelineB(
                observations: sampled,
                sourcesByID: sourcesByID
            )

            pairs.append(PairResult(
                pairID: index + 1,
                dateSlice: dateStr,
                sourceCount: sampled.count,
                sourcesUsed: sourcesUsed,
                pipelineA: pipelineAResult,
                pipelineB: pipelineBResult
            ))
        }

        return TestReport(
            runAt: ISO8601DateFormatter().string(from: .now),
            totalPairs: slicesToTest.count,
            completedPairs: pairs.count,
            pairs: pairs
        )
    }

    // MARK: - Pipeline A (existing engine)

    private static func runPipelineA(
        observations: [ObservationRecord],
        dateSlice: String,
        sourcesByID: [String: SourceRecord],
        repository: AppRepository,
        signalEngine: SignalEngine,
        briefComposer: BriefComposer
    ) async -> BriefOutput {
        do {
            let runHistory = (try? await repository.recentSignalRuns(limit: 400)) ?? []
            let pathwayStats = (try? await repository.fetchPathwayStats(limit: 200)) ?? []
            let runHistoryByName = Dictionary(grouping: runHistory) {
                $0.canonicalEntityID.isEmpty ? $0.canonicalName : $0.canonicalEntityID
            }
            let pathwayStatsByPattern = Dictionary(uniqueKeysWithValues: pathwayStats.map {
                ("\($0.domain.rawValue)::\($0.pathwayPattern)", $0)
            })

            let computed = signalEngine.compute(
                from: observations,
                sourcesByID: sourcesByID,
                runHistoryByName: runHistoryByName,
                pathwayStatsByPattern: pathwayStatsByPattern,
                now: .now
            )

            // Build a BriefingInput from the computed signals
            let topSignals = computed.signals
                .filter { $0.currentSourceFamilyCount >= 2 }
                .prefix(3)

            if topSignals.isEmpty {
                return BriefOutput(title: "", brief: "Pipeline A: No signals with 2+ source families.", error: nil)
            }

            let packets = topSignals.map { signal -> BriefingInput.SignalPacket in
                let evidence = observations.filter { $0.canonicalEntityID == signal.canonicalEntityID || $0.normalizedEntityName == signal.canonicalName.lowercased() }.prefix(4)
                let sourceNames = Array(Set(evidence.compactMap { sourcesByID[$0.sourceID]?.name })).sorted()
                let sourceCities = Array(Set(evidence.compactMap { obs -> String? in
                    guard let source = sourcesByID[obs.sourceID] else { return nil }
                    return source.city == .global ? nil : source.city.displayName
                })).sorted()

                return BriefingInput.SignalPacket(
                    signal: signal,
                    observations: Array(evidence),
                    sourceNames: sourceNames,
                    sourceCities: sourceCities,
                    priorMentions: 0,
                    recentMentions: evidence.count
                )
            }

            let input = BriefingInput(
                generatedAt: .now,
                signals: Array(packets),
                watchlistCandidates: [],
                domainMix: Array(Set(packets.map(\.signal.domain.label))).sorted(),
                sourceInfluenceHighlights: []
            )

            let generator = MalcomeBriefGenerator()
            let brief = try await generator.generateBrief(from: input)
            return BriefOutput(title: brief.title, brief: brief.body, error: nil)
        } catch {
            return BriefOutput(title: "", brief: "", error: "Pipeline A error: \(error.localizedDescription)")
        }
    }

    // MARK: - Pipeline B (small-chunk AFM)

    private static func runPipelineB(
        observations: [ObservationRecord],
        sourcesByID: [String: SourceRecord]
    ) async -> BriefOutput {
        guard SystemLanguageModel.default.isAvailable else {
            return BriefOutput(title: "", brief: "", error: "AFM unavailable")
        }

        // Build plain text context from observations
        let contextBlock = observations.compactMap { obs -> String? in
            let sourceName = sourcesByID[obs.sourceID]?.name ?? "Unknown"
            let excerpt = obs.excerpt ?? ""
            guard !obs.title.isEmpty else { return nil }
            return "Source: \(sourceName)\nTitle: \(obs.title)\nOpening: \(String(excerpt.prefix(300)))"
        }.joined(separator: "\n\n")

        // Chunk 1 — Signal detection
        let chunk1Prompt = """
        You are a cultural intelligence reading these articles from trusted upstream sources. Name one entity — artist, filmmaker, musician, collective — that appears in these articles and is worth paying attention to right now. Just the name and one sentence about what is specifically happening with them. Nothing else.

        \(contextBlock)
        """

        guard let chunk1 = await afmCall(chunk1Prompt) else {
            return BriefOutput(title: "", brief: "", error: "Chunk 1 (signal detection) failed")
        }

        // Extract entity name from chunk 1 (first line or first few words)
        let entityName = chunk1.components(separatedBy: ".").first?
            .components(separatedBy: ",").first?
            .components(separatedBy: " — ").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? chunk1.prefix(40).description

        // Chunk 2 — Voice opening
        let chunk2Prompt = """
        Write one sentence introducing \(entityName) to someone who may not know them. Include what they do and where they are from. Be specific. No enthusiasm. No adjectives like 'incredible' or 'amazing'. Just facts.
        """

        let chunk2 = await afmCall(chunk2Prompt) ?? "\(entityName) is an artist worth knowing."

        // Chunk 3 — Corroboration (deterministic, no AFM)
        let mentioningSources = observations.filter { obs in
            obs.title.localizedCaseInsensitiveContains(entityName.components(separatedBy: " ").last ?? entityName)
                || obs.excerpt?.localizedCaseInsensitiveContains(entityName.components(separatedBy: " ").last ?? entityName) == true
        }
        let sourceNames = Array(Set(mentioningSources.compactMap { sourcesByID[$0.sourceID]?.name })).sorted()

        let chunk3: String
        if sourceNames.count >= 2 {
            chunk3 = "\(sourceNames.prefix(2).joined(separator: " and ")) both picked this up independently. When sources that watch different parts of the scene agree without coordinating, that is worth taking seriously."
        } else if let source = sourceNames.first {
            chunk3 = "The signal is coming through \(source)."
        } else {
            chunk3 = "The signal is emerging from the source network."
        }

        // Chunk 4 — Closing take
        let chunk4Prompt = """
        In one sentence, what does it mean that \(entityName) is being noticed right now? What does it suggest about where things are heading? Be direct. No hedging.
        """

        let chunk4 = await afmCall(chunk4Prompt) ?? "This is worth watching."

        // Assemble
        let brief = [chunk2, chunk1, chunk3, chunk4]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return BriefOutput(title: entityName, brief: brief, error: nil)
    }

    // MARK: - AFM Helper

    private static func afmCall(_ prompt: String) async -> String? {
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
