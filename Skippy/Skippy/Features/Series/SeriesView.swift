import SwiftUI

struct SeriesView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State var viewModel: SeriesViewModel
    @State private var searchText = ""
    @State private var showDownloadedOnly = false

    let makeBookDetailViewModel: (Audiobook) -> BookDetailViewModel
    let makePlayerViewModel: (Audiobook, Chapter?) -> PlayerViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading series…")
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        ContentUnavailableView("Unable to load series", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                        Button("Retry") {
                            Task {
                                await viewModel.load()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredSeries.isEmpty {
                    if searchQuery.isEmpty {
                        ContentUnavailableView("No series", systemImage: "square.stack.3d.up")
                    } else {
                        ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("No series match \"\(searchQuery)\"."))
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(filteredSeries) { shelf in
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
            .navigationTitle("Series")
            .searchableIf(!viewModel.isOfflineMode, text: $searchText, prompt: "Search series")
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

    private var filteredSeries: [HomeShelf] {
        guard !searchQuery.isEmpty else {
            return applyDownloadedFilter(viewModel.series)
        }
        return applyDownloadedFilter(viewModel.searchSeries)
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
    SeriesView(
        viewModel: SeriesViewModel(
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
