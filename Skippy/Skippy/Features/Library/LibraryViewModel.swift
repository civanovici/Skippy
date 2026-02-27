import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    var books: [Audiobook] = []
    var isLoading = false
    var errorMessage: String?

    private let apiClient: APIClientProtocol
    private let authStore: AuthStore
    private let logger: Logger

    init(apiClient: APIClientProtocol, authStore: AuthStore, logger: Logger) {
        self.apiClient = apiClient
        self.authStore = authStore
        self.logger = logger
    }

    func load() async {
        guard let session = authStore.session else {
            books = []
            errorMessage = "You are not signed in."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            books = try await apiClient.audiobookshelf.fetchLibrary(session: session)
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Library fetch failed: \(error.localizedDescription)")
        }
    }
}
