import SwiftUI

/// All books of one series in reading order, opened from a book's series link.
struct SeriesBooksView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State var viewModel: SeriesBooksViewModel

    var body: some View {
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
            } else if viewModel.books.isEmpty {
                ContentUnavailableView("No books", systemImage: "square.stack.3d.up")
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 14) {
                        ForEach(viewModel.books) { book in
                            NavigationLink {
                                BookDetailView(
                                    viewModel: dependencies.makeBookDetailViewModel(book),
                                    makePlayerViewModel: { chapter in
                                        dependencies.makePlayerViewModel(book, chapter: chapter)
                                    }
                                )
                            } label: {
                                BookCardView(
                                    book: book,
                                    isDownloaded: dependencies.downloadManager.fullyDownloadedBookIDs.contains(book.id),
                                    seriesName: viewModel.series.name
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                }
            }
        }
        .navigationTitle(viewModel.series.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14, alignment: .top),
        ]
    }
}
