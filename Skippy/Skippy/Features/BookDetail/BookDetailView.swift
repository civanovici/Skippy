import SwiftUI

struct BookDetailView: View {
    @State var viewModel: BookDetailViewModel
    let makePlayerViewModel: (Chapter?) -> PlayerViewModel
    @State private var chaptersExpanded = true
    @State private var tracksExpanded = false

    private static let shortDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        formatter.allowedUnits = [.minute, .second]
        return formatter
    }()

    private static let longDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topSummary
                metadataGrid
                controlsRow

                Text(viewModel.descriptionText)
                    .font(.body)
                    .foregroundStyle(.secondary)

                chaptersSection
                tracksSection
            }
            .padding(16)
        }
        .navigationTitle(viewModel.book.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading details…")
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            await viewModel.load()
        }
        .alert("Unable to Load Details", isPresented: errorAlertIsPresented) {
            Button("Retry") {
                Task {
                    await viewModel.load()
                }
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var topSummary: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCardView(book: viewModel.book)
                .frame(width: 110)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.book.title)
                    .font(.title2.weight(.bold))
                if let subtitle = viewModel.subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Text("by \(viewModel.book.author)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metadataGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataRow("Narrators", value: viewModel.narratorsText)
            metadataRow("Publish Year", value: viewModel.publishedYearText)
            metadataRow("Publisher", value: viewModel.publisherText)
            metadataRow("Genres", value: viewModel.genresText)
            metadataRow("Duration", value: viewModel.durationText)
            metadataRow("Size", value: viewModel.sizeText)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 12) {
            NavigationLink {
                PlayerView(viewModel: makePlayerViewModel(viewModel.resumeChapter))
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            ProgressView(value: viewModel.book.progress)
                .frame(maxWidth: .infinity)
        }
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 105, alignment: .leading)
            Text(value)
                .font(.body.weight(.medium))
                .multilineTextAlignment(.leading)
        }
    }

    private var chaptersSection: some View {
        DisclosureGroup(isExpanded: $chaptersExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.displayChapters) { chapter in
                    NavigationLink {
                        PlayerView(viewModel: makePlayerViewModel(chapter))
                    } label: {
                        HStack {
                            Text(chapter.title)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(formattedDuration(chapter.duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text("Chapters")
                Spacer()
                Text("\(viewModel.displayChapters.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tracksSection: some View {
        DisclosureGroup(isExpanded: $tracksExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.tracks) { track in
                    HStack {
                        Text(track.title)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if let duration = track.duration, duration > 0 {
                            Text(formattedDuration(duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text("Audio Tracks")
                Spacer()
                Text("\(viewModel.tracks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let formatter = duration >= 3600 ? Self.longDurationFormatter : Self.shortDurationFormatter
        return formatter.string(from: duration) ?? "0:00"
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}

#Preview {
    let book = Audiobook.mockLibrary.first!
    return NavigationStack {
        BookDetailView(
            viewModel: BookDetailViewModel(
                book: book,
                apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
                authStore: AuthStore.previewAuthenticated,
                logger: Logger()
            ),
            makePlayerViewModel: { chapter in
                PlayerViewModel(audiobook: book, chapter: chapter, playerService: PlayerService(), nowPlayingService: NowPlayingService())
            }
        )
    }
}
