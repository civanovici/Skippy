import SwiftUI

struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State var viewModel: HomeViewModel
    @State private var searchText = ""
    @State private var showDownloadedOnly = false

    let makeBookDetailViewModel: (Audiobook) -> BookDetailViewModel
    let makePlayerViewModel: (Audiobook, Chapter?) -> PlayerViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading home…")
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        ContentUnavailableView("Unable to load home", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                        Button("Retry") {
                            Task {
                                await viewModel.load()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredShelves.isEmpty {
                    if searchQuery.isEmpty {
                        ContentUnavailableView("No shelves", systemImage: "books.vertical")
                    } else {
                        ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("No books match \"\(searchQuery)\"."))
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(filteredShelves) { shelf in
                                ShelfView(title: shelf.title, books: shelf.books, downloadedBookIDs: downloadedBookIDs) { book in
                                    BookDetailView(
                                        viewModel: makeBookDetailViewModel(book),
                                        makePlayerViewModel: { chapter in
                                            makePlayerViewModel(book, chapter)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
            .navigationTitle("Home")
            .searchableIf(!viewModel.isOfflineMode, text: $searchText, prompt: "Search home")
            .task(id: searchText) {
                guard !viewModel.isOfflineMode else {
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else {
                    return
                }
                await viewModel.search(query: searchText)
            }
            .toolbar {
                if viewModel.isSearching {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isOfflineMode {
                        Label("Offline", systemImage: "wifi.slash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDownloadedOnly.toggle()
                    } label: {
                        Image(systemName: effectiveDownloadedOnly ? "arrow.down.circle.fill" : "arrow.down.circle")
                    }
                    .help("Show downloaded only")
                    .disabled(viewModel.isOfflineMode)
                }
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
            .onChange(of: viewModel.isOfflineMode) { _, isOffline in
                if isOffline {
                    showDownloadedOnly = true
                    searchText = ""
                }
            }
        }
    }

    private var filteredShelves: [HomeShelf] {
        guard !searchQuery.isEmpty else {
            return applyDownloadedFilter(viewModel.shelves)
        }
        if !viewModel.searchBooks.isEmpty {
            return applyDownloadedFilter([HomeShelf(id: "search-home", title: "Search Results", books: viewModel.searchBooks)])
        }
        return []
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var downloadedBookIDs: Set<String> {
        dependencies.downloadManager.fullyDownloadedBookIDs
    }

    private var effectiveDownloadedOnly: Bool {
        viewModel.isOfflineMode || showDownloadedOnly
    }

    private func applyDownloadedFilter(_ shelves: [HomeShelf]) -> [HomeShelf] {
        guard effectiveDownloadedOnly else {
            return shelves
        }
        return shelves.compactMap { shelf in
            let books = shelf.books.filter { downloadedBookIDs.contains($0.id) }
            guard !books.isEmpty else {
                return nil
            }
            return HomeShelf(id: shelf.id, title: shelf.title, books: books)
        }
    }
}

#Preview {
    HomeView(
        viewModel: HomeViewModel(
            apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
            authStore: AuthStore.previewAuthenticated,
            downloadManager: DownloadManager(),
            connectivityStore: ConnectivityStore(),
            logger: Logger()
        ),
        makeBookDetailViewModel: {
            BookDetailViewModel(
                book: $0,
                apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
                authStore: AuthStore.previewAuthenticated,
                downloadManager: DownloadManager(),
                connectivityStore: ConnectivityStore(),
                persistenceController: PersistenceController(),
                logger: Logger()
            )
        },
        makePlayerViewModel: { book, chapter in
            PlayerViewModel(
                audiobook: book,
                chapter: chapter,
                playerService: PlayerService(),
                nowPlayingService: NowPlayingService(),
                apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
                authStore: AuthStore.previewAuthenticated,
                downloadManager: DownloadManager(),
                connectivityStore: ConnectivityStore(),
                persistenceController: PersistenceController(),
                logger: Logger()
            )
        }
    )
}
