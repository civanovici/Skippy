import Foundation
import Observation

@Observable
final class AppDependencies {
    let authStore: AuthStore
    let apiClient: APIClientProtocol
    let playerService: PlayerServiceProtocol
    let nowPlayingService: NowPlayingServiceProtocol
    let downloadManager: DownloadManaging
    let connectivityStore: ConnectivityStore
    let persistenceController: PersistenceController
    let logger: Logger

    init(
        authStore: AuthStore,
        apiClient: APIClientProtocol,
        playerService: PlayerServiceProtocol,
        nowPlayingService: NowPlayingServiceProtocol,
        downloadManager: DownloadManaging,
        connectivityStore: ConnectivityStore,
        persistenceController: PersistenceController,
        logger: Logger
    ) {
        self.authStore = authStore
        self.apiClient = apiClient
        self.playerService = playerService
        self.nowPlayingService = nowPlayingService
        self.downloadManager = downloadManager
        self.connectivityStore = connectivityStore
        self.persistenceController = persistenceController
        self.logger = logger
    }

    @MainActor
    static func makeLive() -> AppDependencies {
        let logger = Logger()
        return AppDependencies(
            authStore: AuthStore(keychainStore: KeychainStore(), logger: logger),
            apiClient: APIClient(audiobookshelf: AudiobookshelfHTTPAPI()),
            playerService: PlayerService(),
            nowPlayingService: NowPlayingService(),
            downloadManager: DownloadManager(),
            connectivityStore: ConnectivityStore(),
            persistenceController: .shared,
            logger: logger
        )
    }

    @MainActor
    static func makeMock() -> AppDependencies {
        let logger = Logger()
        return AppDependencies(
            authStore: AuthStore(keychainStore: KeychainStore(), logger: logger),
            apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
            playerService: PlayerService(),
            nowPlayingService: NowPlayingService(),
            downloadManager: DownloadManager(),
            connectivityStore: ConnectivityStore(),
            persistenceController: .shared,
            logger: logger
        )
    }
}
