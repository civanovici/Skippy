import SwiftUI

struct CollectionsView: View {
    @State var viewModel: CollectionsViewModel
    @State private var searchText = ""

    let makeBookDetailViewModel: (Audiobook) -> BookDetailViewModel
    let makePlayerViewModel: (Audiobook, Chapter?) -> PlayerViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading collections…")
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        ContentUnavailableView("Unable to load collections", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                        Button("Retry") {
                            Task {
                                await viewModel.load()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredCollections.isEmpty {
                    if searchQuery.isEmpty {
                        ContentUnavailableView("No collections", systemImage: "rectangle.stack")
                    } else {
                        ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("No collections match \"\(searchQuery)\"."))
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(filteredCollections) { shelf in
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
            .navigationTitle("Collections")
            .searchable(text: $searchText, prompt: "Search collections")
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

    private var filteredCollections: [HomeShelf] {
        guard !searchQuery.isEmpty else {
            return viewModel.collections
        }
        let matchedBookIDs = Set(viewModel.searchBooks.map(\.id))
        return viewModel.collections.compactMap { shelf in
            if shelf.title.localizedCaseInsensitiveContains(searchQuery) {
                return shelf
            }
            let books = shelf.books.filter {
                matchedBookIDs.contains($0.id)
            }
            guard !books.isEmpty else {
                return nil
            }
            return HomeShelf(id: shelf.id, title: shelf.title, books: books)
        }
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    CollectionsView(
        viewModel: CollectionsViewModel(apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()), authStore: AuthStore.previewAuthenticated, logger: Logger()),
        makeBookDetailViewModel: {
            BookDetailViewModel(
                book: $0,
                apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
                authStore: AuthStore.previewAuthenticated,
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
                persistenceController: PersistenceController(),
                logger: Logger()
            )
        }
    )
}
