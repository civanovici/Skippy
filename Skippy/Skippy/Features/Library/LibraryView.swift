import SwiftUI

struct LibraryView: View {
    @State var viewModel: LibraryViewModel
    let onLogout: () -> Void

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
                } else if viewModel.books.isEmpty {
                    ContentUnavailableView("No audiobooks", systemImage: "books.vertical")
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 14) {
                            ForEach(viewModel.books) { book in
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Logout", role: .destructive) {
                        onLogout()
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
}

#Preview {
    LibraryView(
        viewModel: LibraryViewModel(apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()), authStore: AuthStore.previewAuthenticated, logger: Logger()),
        onLogout: {},
        makeBookDetailViewModel: { BookDetailViewModel(book: $0) },
        makePlayerViewModel: { book, chapter in
            PlayerViewModel(audiobook: book, chapter: chapter, playerService: PlayerService(), nowPlayingService: NowPlayingService())
        }
    )
}
