import Foundation
import Observation

@Observable
final class AppDependencies {
    let authStore: AuthStore
    let apiClient: APIClientProtocol
    let playerService: PlayerServiceProtocol
    let nowPlayingService: NowPlayingServiceProtocol
    let downloadManager: DownloadManaging
    let persistenceController: PersistenceController
    let logger: Logger

    init(
        authStore: AuthStore,
        apiClient: APIClientProtocol,
        playerService: PlayerServiceProtocol,
        nowPlayingService: NowPlayingServiceProtocol,
        downloadManager: DownloadManaging,
        persistenceController: PersistenceController,
        logger: Logger
    ) {
        self.authStore = authStore
        self.apiClient = apiClient
        self.playerService = playerService
        self.nowPlayingService = nowPlayingService
        self.downloadManager = downloadManager
        self.persistenceController = persistenceController
        self.logger = logger
    }

    static func makeMock() -> AppDependencies {
        let logger = Logger()
        return AppDependencies(
            authStore: AuthStore(keychainStore: KeychainStore(), logger: logger),
            apiClient: APIClient(),
            playerService: PlayerService(),
            nowPlayingService: NowPlayingService(),
            downloadManager: DownloadManager(),
            persistenceController: .shared,
            logger: logger
        )
    }
}
