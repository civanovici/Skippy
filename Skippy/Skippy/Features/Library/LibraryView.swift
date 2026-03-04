import SwiftUI

struct LibraryView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State var viewModel: LibraryViewModel
    @State private var searchText = ""
    @State private var showDownloadedOnly = false

    let makeBookDetailViewModel: (Audiobook) -> BookDetailViewModel
    let makePlayerViewModel: (Audiobook, Chapter?) -> PlayerViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading library…")
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        ContentUnavailableView("Unable to load library", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                        Button("Retry") {
                            Task {
                                await viewModel.load()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredBooks.isEmpty {
                    if searchQuery.isEmpty {
                        ContentUnavailableView("No audiobooks", systemImage: "books.vertical")
                    } else {
                        ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("No books match \"\(searchQuery)\"."))
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 14) {
                            ForEach(filteredBooks) { book in
                                NavigationLink {
                                    BookDetailView(
                                        viewModel: makeBookDetailViewModel(book),
                                        makePlayerViewModel: { chapter in
                                            makePlayerViewModel(book, chapter)
                                        }
                                    )
                                } label: {
                                    BookCardView(book: book, isDownloaded: downloadedBookIDs.contains(book.id))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    }
                }
            }
            .navigationTitle("Library")
            .searchableIf(!viewModel.isOfflineMode, text: $searchText, prompt: "Search library")
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

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14, alignment: .top),
        ]
    }

    private var filteredBooks: [Audiobook] {
        guard !searchQuery.isEmpty else {
            return applyDownloadedFilter(viewModel.books)
        }
        return applyDownloadedFilter(viewModel.searchResults)
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

    private func applyDownloadedFilter(_ books: [Audiobook]) -> [Audiobook] {
        guard effectiveDownloadedOnly else {
            return books
        }
        return books.filter { downloadedBookIDs.contains($0.id) }
    }
}

#Preview {
    LibraryView(
        viewModel: LibraryViewModel(
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
