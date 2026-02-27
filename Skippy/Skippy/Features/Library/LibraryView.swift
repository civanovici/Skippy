import SwiftUI

struct LibraryView: View {
    @State var viewModel: LibraryViewModel

    let makeBookDetailViewModel: (Audiobook) -> BookDetailViewModel
    let makePlayerViewModel: (Audiobook, Chapter?) -> PlayerViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading library…")
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView("Unable to load library", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                } else if viewModel.books.isEmpty {
                    ContentUnavailableView("No audiobooks", systemImage: "books.vertical")
                } else {
                    List(viewModel.books) { book in
                        NavigationLink {
                            BookDetailView(
                                viewModel: makeBookDetailViewModel(book),
                                makePlayerViewModel: { chapter in
                                    makePlayerViewModel(book, chapter)
                                }
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(book.title)
                                    .font(.headline)
                                Text(book.author)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                ProgressView(value: book.progress)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Library")
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
        }
    }
}

#Preview {
    LibraryView(
        viewModel: LibraryViewModel(apiClient: APIClient(), authStore: AuthStore.previewAuthenticated, logger: Logger()),
        makeBookDetailViewModel: { BookDetailViewModel(book: $0) },
        makePlayerViewModel: { book, chapter in
            PlayerViewModel(audiobook: book, chapter: chapter, playerService: PlayerService(), nowPlayingService: NowPlayingService())
        }
    )
}
