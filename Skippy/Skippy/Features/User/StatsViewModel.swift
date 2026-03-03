import Foundation
import Observation

@MainActor
@Observable
final class StatsViewModel {
    var userStats: UserListeningStats?
    var libraryStats: LibraryStatsSnapshot?
    var isLoading = false
    var errorMessage: String?

    private let apiClient: APIClientProtocol
    private let authStore: AuthStore
    private let logger: Logger
    private let daysWindow: Int

    init(
        apiClient: APIClientProtocol,
        authStore: AuthStore,
        logger: Logger,
        daysWindow: Int = 30
    ) {
        self.apiClient = apiClient
        self.authStore = authStore
        self.logger = logger
        self.daysWindow = max(daysWindow, 1)
    }

    func load() async {
        guard let session = authStore.session else {
            userStats = nil
            libraryStats = nil
            errorMessage = "You are not signed in."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var failures: [String] = []

        do {
            userStats = try await apiClient.audiobookshelf.fetchMyListeningStats(
                session: session,
                days: daysWindow
            )
        } catch {
            userStats = nil
            failures.append("Listening activity could not be loaded.")
            logger.error("Listening stats fetch failed: \(error.localizedDescription)")
        }

        do {
            libraryStats = try await apiClient.audiobookshelf.fetchPrimaryLibraryStats(session: session)
        } catch {
            libraryStats = nil
            failures.append("Library analytics could not be loaded.")
            logger.error("Library stats fetch failed: \(error.localizedDescription)")
        }

        if !failures.isEmpty {
            errorMessage = failures.joined(separator: " ")
        }
    }
}
