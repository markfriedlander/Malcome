import Foundation

struct AppContainer {
    let repository: AppRepository
    let sourceRegistry: SourceRegistry
    let sourcePipeline: SourcePipeline
    let signalEngine: SignalEngine
    let briefComposer: BriefComposer

    static func live(databaseURL: URL? = nil) -> AppContainer {
        let repository = AppRepository(databaseURL: databaseURL)
        let registry = SourceRegistry()
        let parserFactory = SourceParserFactory()
        let pipeline = SourcePipeline(repository: repository, parserFactory: parserFactory)
        let signalEngine = SignalEngine()
        let briefComposer = BriefComposer(repository: repository, generator: LocalBriefGenerator())

        return AppContainer(
            repository: repository,
            sourceRegistry: registry,
            sourcePipeline: pipeline,
            signalEngine: signalEngine,
            briefComposer: briefComposer
        )
    }
}
