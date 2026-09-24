import SwiftUI

struct BookDetailView: View {
    @State var viewModel: BookDetailViewModel
    let makePlayerViewModel: (Chapter?) -> PlayerViewModel
    @State private var chaptersExpanded = true
    @State private var tracksExpanded = false
    @State private var inlinePlayerViewModel: PlayerViewModel?
    @State private var scrubTime: TimeInterval?
    @State private var isScrubbing = false
    @State private var deleteDownloadConfirmationPresented = false

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
        .toolbar {
            if viewModel.isOfflineMode {
                ToolbarItem(placement: .topBarTrailing) {
                    Label("Offline", systemImage: "wifi.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading details…")
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            await viewModel.load()
            ensureInlinePlayerInitialized()
        }
        .alert("Unable to Load Details", isPresented: errorAlertIsPresented) {
            Button("Retry") {
                Task {
                    await viewModel.load()
                    ensureInlinePlayerInitialized()
                }
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .alert("Playback Position Mismatch", isPresented: inlineConflictIsPresented) {
            Button("Use App Time") {
                inlinePlayerViewModel?.resolveProgressConflict(useServer: false)
            }
            Button("Use Server Time") {
                inlinePlayerViewModel?.resolveProgressConflict(useServer: true)
            }
        } message: {
            if let conflict = inlinePlayerViewModel?.progressConflict {
                Text("App: \(timeText(conflict.local.positionSeconds))  Server: \(timeText(conflict.remote.positionSeconds))")
            } else {
                Text("Choose which position to keep.")
            }
        }
        .alert("Delete Download?", isPresented: $deleteDownloadConfirmationPresented) {
            Button("Delete", role: .destructive) {
                viewModel.deleteDownload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the downloaded audio from this device.")
        }
    }

    private var topSummary: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCardView(book: viewModel.book)
                .overlay(alignment: .bottomTrailing) {
                    if viewModel.isDownloaded {
                        Label("Offline", systemImage: "arrow.down.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.9))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(6)
                    }
                }
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
        VStack(alignment: .leading, spacing: 14) {
            downloadControls

            if let player = inlinePlayerViewModel {
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { scrubTime ?? player.currentTime },
                            set: { scrubTime = $0 }
                        ),
                        in: 0...max(player.duration, 1),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing {
                                if let scrubTime {
                                    player.seek(to: scrubTime)
                                }
                                scrubTime = nil
                            }
                        }
                    )

                    HStack {
                        Text(isScrubbing ? timeText(scrubTime ?? player.currentTime) : player.currentTimeText)
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(player.progressPercentText)
                            .font(.caption.weight(.semibold).monospacedDigit())
                        Spacer()
                        Text("-\(player.remainingTimeText)")
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 20) {
                    if player.hasPreviousChapter {
                        Button {
                            player.previousChapter()
                        } label: {
                            Image(systemName: "backward.end.fill")
                        }
                    }

                    Button {
                        player.seekBack()
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title2)
                    }

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2.weight(.semibold))
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(.tint))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.seekForward()
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.title2)
                    }

                    if player.hasNextChapter {
                        Button {
                            player.nextChapter()
                        } label: {
                            Image(systemName: "forward.end.fill")
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.title3)

                HStack(spacing: 10) {
                    Menu(rateLabel(for: player.selectedRate)) {
                        ForEach(player.availableRates, id: \.self) { rate in
                            Button(rateLabel(for: rate)) {
                                player.setRate(rate)
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Menu("Sleep: \(player.selectedSleepTimer.title)") {
                        ForEach(PlayerViewModel.SleepTimerOption.allCases, id: \.self) { option in
                            Button(option.title) {
                                player.setSleepTimer(option)
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Bookmark") {
                        Task { await player.addBookmark() }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ProgressView("Preparing player…")
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var downloadControls: some View {
        let record = viewModel.downloadRecord
        let progressPercent = Int((record?.progress ?? 0) * 100)

        HStack(spacing: 10) {
            if viewModel.isDownloaded {
                Button(role: .destructive) {
                    deleteDownloadConfirmationPresented = true
                } label: {
                    Label("Delete Download", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            } else {
                switch record?.state {
                case .downloading:
                    Button {
                        viewModel.pauseDownload()
                    } label: {
                        Label("Pause Download", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                case .paused:
                    Button {
                        viewModel.resumeDownload()
                    } label: {
                        Label("Resume Download", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                default:
                    Button {
                        viewModel.startDownload()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.tracks.isEmpty)
                }
            }

            if let record, record.state != .completed {
                Text("\(progressPercent)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
                    Button {
                        if inlinePlayerViewModel == nil {
                            startInlinePlayer(with: chapter, autoplay: true)
                        } else {
                            inlinePlayerViewModel?.selectChapter(chapter)
                            inlinePlayerViewModel?.play()
                        }
                    } label: {
                        HStack {
                            Image(systemName: chapterStatusIcon(for: chapter))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(chapterStatusColor(for: chapter))
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
                    .buttonStyle(.plain)
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

    private var inlineConflictIsPresented: Binding<Bool> {
        Binding(
            get: { inlinePlayerViewModel?.progressConflict != nil },
            set: { _ in }
        )
    }

    private func startInlinePlayer(with chapter: Chapter?, autoplay: Bool) {
        inlinePlayerViewModel?.stop()
        let playerViewModel = makePlayerViewModel(chapter)
        inlinePlayerViewModel = playerViewModel
        Task {
            await playerViewModel.start()
            if autoplay {
                playerViewModel.play()
            }
        }
    }

    private func ensureInlinePlayerInitialized() {
        guard inlinePlayerViewModel == nil else { return }
        startInlinePlayer(with: viewModel.resumeChapter, autoplay: false)
    }

    private func rateLabel(for rate: Float) -> String {
        String(format: "%.2gx", rate)
    }

    private func chapterStatusIcon(for chapter: Chapter) -> String {
        switch viewModel.chapterProgressState(for: chapter) {
        case .completed:
            return "checkmark.circle.fill"
        case .inProgress:
            return "play.circle.fill"
        case .upcoming:
            return "circle"
        }
    }

    private func chapterStatusColor(for chapter: Chapter) -> Color {
        switch viewModel.chapterProgressState(for: chapter) {
        case .completed:
            return .green
        case .inProgress:
            return .accentColor
        case .upcoming:
            return .secondary
        }
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

#Preview {
    let book = Audiobook.mockLibrary.first!
    let downloadManager = DownloadManager()
    let connectivityStore = ConnectivityStore()
    return NavigationStack {
        BookDetailView(
            viewModel: BookDetailViewModel(
                book: book,
                apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
                authStore: AuthStore.previewAuthenticated,
                downloadManager: downloadManager,
                connectivityStore: connectivityStore,
                persistenceController: PersistenceController(),
                logger: Logger()
            ),
            makePlayerViewModel: { chapter in
                PlayerViewModel(
                    audiobook: book,
                    chapter: chapter,
                    playerService: PlayerService(),
                    nowPlayingService: NowPlayingService(),
                    apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
                    authStore: AuthStore.previewAuthenticated,
                    downloadManager: downloadManager,
                    connectivityStore: connectivityStore,
                    persistenceController: PersistenceController(),
                    logger: Logger()
                )
            }
        )
    }
}
