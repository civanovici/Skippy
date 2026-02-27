import SwiftUI

struct HomeView: View {
    @State var viewModel: HomeViewModel
    @State private var searchText = ""

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
            .navigationTitle("Home")
            .searchable(text: $searchText, prompt: "Search home")
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

    private var filteredShelves: [HomeShelf] {
        guard !searchQuery.isEmpty else {
            return viewModel.shelves
        }
        if !viewModel.searchBooks.isEmpty {
            return [HomeShelf(id: "search-home", title: "Search Results", books: viewModel.searchBooks)]
        }
        return []
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    HomeView(
        viewModel: HomeViewModel(apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()), authStore: AuthStore.previewAuthenticated, logger: Logger()),
        makeBookDetailViewModel: {
            BookDetailViewModel(
                book: $0,
                apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
                authStore: AuthStore.previewAuthenticated,
                logger: Logger()
            )
        },
        makePlayerViewModel: { book, chapter in
            PlayerViewModel(audiobook: book, chapter: chapter, playerService: PlayerService(), nowPlayingService: NowPlayingService())
        }
    )
}
