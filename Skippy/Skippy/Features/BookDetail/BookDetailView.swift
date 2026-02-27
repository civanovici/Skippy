import SwiftUI

struct BookDetailView: View {
    @State var viewModel: BookDetailViewModel
    let makePlayerViewModel: (Chapter?) -> PlayerViewModel

    var body: some View {
        List {
            Section("Book") {
                Text(viewModel.book.title)
                    .font(.title3.weight(.semibold))
                Text(viewModel.book.author)
                    .foregroundStyle(.secondary)
                ProgressView(value: viewModel.book.progress)
            }

            Section("Playback") {
                NavigationLink("Resume") {
                    PlayerView(viewModel: makePlayerViewModel(viewModel.resumeChapter))
                }
            }

            Section("Chapters") {
                ForEach(viewModel.book.chapters) { chapter in
                    NavigationLink(chapter.title) {
                        PlayerView(viewModel: makePlayerViewModel(chapter))
                    }
                }
            }
        }
        .navigationTitle("Details")
    }
}

#Preview {
    let book = Audiobook.mockLibrary.first!
    return NavigationStack {
        BookDetailView(
            viewModel: BookDetailViewModel(book: book),
            makePlayerViewModel: { chapter in
                PlayerViewModel(audiobook: book, chapter: chapter, playerService: PlayerService(), nowPlayingService: NowPlayingService())
            }
        )
    }
}
