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
    private let downloadManager: DownloadManaging
    private let connectivityStore: ConnectivityStore
    private let logger: Logger
    private var searchRequestID = 0

    var isOfflineMode: Bool {
        connectivityStore.isOfflineEffective
    }

    init(
        apiClient: APIClientProtocol,
        authStore: AuthStore,
        downloadManager: DownloadManaging,
        connectivityStore: ConnectivityStore,
        logger: Logger
    ) {
        self.apiClient = apiClient
        self.authStore = authStore
        self.downloadManager = downloadManager
        self.connectivityStore = connectivityStore
        self.logger = logger
    }

    func load() async {
        guard let session = authStore.session else {
            series = []
            errorMessage = "You are not signed in."
            return
        }

        if !connectivityStore.isNetworkReachable {
            loadOfflineSeries()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            series = try await apiClient.audiobookshelf.fetchSeries(session: session)
            searchSeries = []
            connectivityStore.markServerReachable()
        } catch {
            connectivityStore.reportResult(.failure(error))
            if isOfflineMode {
                loadOfflineSeries()
            } else {
                errorMessage = error.localizedDescription
                logger.error("Series fetch failed: \(error.localizedDescription)")
            }
        }
    }

    func search(query: String) async {
        guard !isOfflineMode else {
            searchSeries = []
            isSearching = false
            return
        }
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

    private func loadOfflineSeries() {
        let downloaded = downloadManager.downloadedLibrary()
        series = downloaded.isEmpty
            ? []
            : [HomeShelf(id: "offline-series", title: "Downloaded", books: downloaded)]
        searchSeries = []
        errorMessage = nil
    }
}
