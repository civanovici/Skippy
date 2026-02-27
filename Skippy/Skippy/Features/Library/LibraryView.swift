import SwiftUI

struct LibraryView: View {
    @State var viewModel: LibraryViewModel
    @State private var searchText = ""

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
                                    BookCardView(book: book)
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
            .searchable(text: $searchText, prompt: "Search library")
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

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14, alignment: .top),
        ]
    }

    private var filteredBooks: [Audiobook] {
        guard !searchQuery.isEmpty else {
            return viewModel.books
        }
        return viewModel.searchResults
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    LibraryView(
        viewModel: LibraryViewModel(apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()), authStore: AuthStore.previewAuthenticated, logger: Logger()),
        makeBookDetailViewModel: { BookDetailViewModel(book: $0) },
        makePlayerViewModel: { book, chapter in
            PlayerViewModel(audiobook: book, chapter: chapter, playerService: PlayerService(), nowPlayingService: NowPlayingService())
        }
    )
}
