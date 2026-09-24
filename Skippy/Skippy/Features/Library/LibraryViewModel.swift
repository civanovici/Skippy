import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    var books: [Audiobook] = []
    var searchResults: [Audiobook] = []
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
            books = []
            errorMessage = "You are not signed in."
            return
        }

        if !connectivityStore.isNetworkReachable {
            loadOfflineBooks()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            books = try await apiClient.audiobookshelf.fetchLibrary(session: session)
            searchResults = []
            connectivityStore.markServerReachable()
        } catch {
            connectivityStore.reportResult(.failure(error))
            if isOfflineMode {
                loadOfflineBooks()
            } else {
                errorMessage = error.localizedDescription
                logger.error("Library fetch failed: \(error.localizedDescription)")
            }
        }
    }

    func search(query: String) async {
        guard !isOfflineMode else {
            searchResults = []
            isSearching = false
            return
        }
        searchRequestID += 1
        let requestID = searchRequestID

        guard let session = authStore.session else {
            searchResults = []
            isSearching = false
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        do {
            let result = try await apiClient.audiobookshelf.search(session: session, query: trimmed)
            guard requestID == searchRequestID else {
                return
            }
            searchResults = result.books
        } catch {
            guard requestID == searchRequestID else {
                return
            }
            logger.error("Library search failed: \(error.localizedDescription)")
            searchResults = []
        }

        if requestID == searchRequestID {
            isSearching = false
        }
    }

    private func loadOfflineBooks() {
        books = downloadManager.downloadedLibrary()
        searchResults = []
        errorMessage = nil
    }
}
