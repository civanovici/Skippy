import Foundation
import Observation

@MainActor
@Observable
final class SeriesViewModel {
    var series: [HomeShelf] = []
    var searchSeries: [HomeShelf] = []
    var isLoading = false
    var isSearching = false
    var errorMessage: String?

    private let apiClient: APIClientProtocol
    private let authStore: AuthStore
    private let logger: Logger
    private var searchRequestID = 0

    init(apiClient: APIClientProtocol, authStore: AuthStore, logger: Logger) {
        self.apiClient = apiClient
        self.authStore = authStore
        self.logger = logger
    }

    func load() async {
        guard let session = authStore.session else {
            series = []
            errorMessage = "You are not signed in."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            series = try await apiClient.audiobookshelf.fetchSeries(session: session)
            searchSeries = []
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Series fetch failed: \(error.localizedDescription)")
        }
    }

    func search(query: String) async {
        searchRequestID += 1
        let requestID = searchRequestID

        guard let session = authStore.session else {
            searchSeries = []
            isSearching = false
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchSeries = []
            isSearching = false
            return
        }

        isSearching = true

        do {
            let result = try await apiClient.audiobookshelf.search(session: session, query: trimmed)
            guard requestID == searchRequestID else {
                return
            }
            searchSeries = result.series
        } catch {
            guard requestID == searchRequestID else {
                return
            }
            logger.error("Series search failed: \(error.localizedDescription)")
            searchSeries = []
        }

        if requestID == searchRequestID {
            isSearching = false
        }
    }
}
