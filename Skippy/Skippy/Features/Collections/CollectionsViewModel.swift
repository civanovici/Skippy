import Foundation
import Observation

@MainActor
@Observable
final class CollectionsViewModel {
    var collections: [HomeShelf] = []
    var searchBooks: [Audiobook] = []
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
            collections = []
            errorMessage = "You are not signed in."
            return
        }

        if !connectivityStore.isNetworkReachable {
            loadOfflineCollections()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            collections = try await apiClient.audiobookshelf.fetchCollections(session: session)
            searchBooks = []
            connectivityStore.markServerReachable()
        } catch {
            connectivityStore.reportResult(.failure(error))
            if isOfflineMode {
                loadOfflineCollections()
            } else {
                errorMessage = error.localizedDescription
                logger.error("Collections fetch failed: \(error.localizedDescription)")
            }
        }
    }

    func search(query: String) async {
        guard !isOfflineMode else {
            searchBooks = []
            isSearching = false
            return
        }
        searchRequestID += 1
        let requestID = searchRequestID

        guard let session = authStore.session else {
            searchBooks = []
            isSearching = false
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchBooks = []
            isSearching = false
            return
        }

        isSearching = true

        do {
            let result = try await apiClient.audiobookshelf.search(session: session, query: trimmed)
            guard requestID == searchRequestID else {
                return
            }
            searchBooks = result.books
        } catch {
            guard requestID == searchRequestID else {
                return
            }
            logger.error("Collections search failed: \(error.localizedDescription)")
            searchBooks = []
        }

        if requestID == searchRequestID {
            isSearching = false
        }
    }

    private func loadOfflineCollections() {
        let downloaded = downloadManager.downloadedLibrary()
        collections = downloaded.isEmpty
            ? []
            : [HomeShelf(id: "offline-collections", title: "Downloaded", books: downloaded)]
        searchBooks = []
        errorMessage = nil
    }
}
