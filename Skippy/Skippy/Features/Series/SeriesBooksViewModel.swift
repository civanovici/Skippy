import Foundation
import Observation

@MainActor
@Observable
final class SeriesBooksViewModel {
    let series: SeriesPosition
    var books: [Audiobook] = []
    var isLoading = false
    var errorMessage: String?

    private let apiClient: APIClientProtocol
    private let authStore: AuthStore
    private let connectivityStore: ConnectivityStore
    private let logger: Logger

    init(
        series: SeriesPosition,
        apiClient: APIClientProtocol,
        authStore: AuthStore,
        connectivityStore: ConnectivityStore,
        logger: Logger
    ) {
        self.series = series
        self.apiClient = apiClient
        self.authStore = authStore
        self.connectivityStore = connectivityStore
        self.logger = logger
    }

    func load() async {
        guard let session = authStore.session else {
            errorMessage = "You are not signed in."
            return
        }

        // Block the UI only on the first load so returning from a book keeps the scroll position.
        isLoading = books.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            books = try await apiClient.audiobookshelf.fetchSeriesBooks(session: session, series: series)
            connectivityStore.markServerReachable()
        } catch {
            connectivityStore.reportResult(.failure(error))
            if books.isEmpty {
                errorMessage = error.localizedDescription
            }
            logger.error("Series books fetch failed: \(error.localizedDescription)")
        }
    }
}
