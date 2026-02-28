import SwiftUI

struct SeriesView: View {
    @State var viewModel: SeriesViewModel
    @State private var searchText = ""

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
                                ShelfView(title: shelf.title, books: shelf.books) { book in
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
            .searchable(text: $searchText, prompt: "Search series")
            .task(id: searchText) {
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
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
        }
    }

    private var filteredSeries: [HomeShelf] {
        guard !searchQuery.isEmpty else {
            return viewModel.series
        }
        return viewModel.searchSeries
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    SeriesView(
        viewModel: SeriesViewModel(apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()), authStore: AuthStore.previewAuthenticated, logger: Logger()),
        makeBookDetailViewModel: {
            BookDetailViewModel(
                book: $0,
                apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
                authStore: AuthStore.previewAuthenticated,
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
                persistenceController: PersistenceController(),
                logger: Logger()
            )
        }
    )
}
