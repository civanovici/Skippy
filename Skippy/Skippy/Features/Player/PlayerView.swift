import SwiftUI

struct PlayerView: View {
    @State var viewModel: PlayerViewModel
    @State private var scrubTime: TimeInterval?
    @State private var isScrubbing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.title)
                        .font(.title2.weight(.bold))
                    Text(viewModel.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { scrubTime ?? viewModel.currentTime },
                            set: { scrubTime = $0 }
                        ),
                        in: 0...max(viewModel.duration, 1),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing {
                                if let scrubTime {
                                    viewModel.seek(to: scrubTime)
                                }
                                scrubTime = nil
                            }
                        }
                    )

                    HStack {
                        Text(displayedCurrentTimeText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("-\(viewModel.remainingTimeText)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if let scrubTime, isScrubbing {
                        Text(timeText(scrubTime))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 18) {
                    if viewModel.hasPreviousChapter {
                        Button {
                            viewModel.previousChapter()
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.title3)
                        }
                    }

                    Button {
                        viewModel.seekBack()
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title2)
                    }

                    Button {
                        viewModel.togglePlayPause()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2.weight(.semibold))
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(.tint))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.seekForward()
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.title2)
                    }

                    if viewModel.hasNextChapter {
                        Button {
                            viewModel.nextChapter()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.title3)
                        }
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    Menu("Sleep: \(viewModel.selectedSleepTimer.title)") {
                        ForEach(PlayerViewModel.SleepTimerOption.allCases, id: \.self) { option in
                            Button(option.title) {
                                viewModel.setSleepTimer(option)
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Mark Played") {
                        viewModel.markAsPlayed()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let sleep = viewModel.sleepRemainingText {
                    Text(sleep)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(viewModel.syncStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if viewModel.isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Bookmarks")
                            .font(.headline)
                        Spacer()
                        Button("Add Current") {
                            Task { await viewModel.addBookmark() }
                        }
                        .buttonStyle(.bordered)
                    }

                    if viewModel.bookmarks.isEmpty {
                        Text("No bookmarks yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.bookmarks) { bookmark in
                            HStack {
                                Button(bookmark.title) {
                                    viewModel.jumpToBookmark(bookmark)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Text(timeText(bookmark.time))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    Task { await viewModel.removeBookmark(bookmark) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Player")
        .task {
            await viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        .alert("Player Notice", isPresented: errorAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Playback Position Mismatch", isPresented: progressConflictPresented) {
            Button("Use App Time") {
                viewModel.resolveProgressConflict(useServer: false)
            }
            Button("Use Server Time") {
                viewModel.resolveProgressConflict(useServer: true)
            }
        } message: {
            if let conflict = viewModel.progressConflict {
                Text("App: \(timeText(conflict.local.positionSeconds))  Server: \(timeText(conflict.remote.positionSeconds))")
            } else {
                Text("Choose which position to keep.")
            }
        }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private var progressConflictPresented: Binding<Bool> {
        Binding(
            get: { viewModel.progressConflict != nil },
            set: { _ in }
        )
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

    private var displayedCurrentTimeText: String {
        guard let scrubTime, isScrubbing else {
            return viewModel.currentTimeText
        }
        return timeText(scrubTime)
    }
}

#Preview {
    NavigationStack {
        PlayerView(
            viewModel: PlayerViewModel(
                audiobook: Audiobook.mockLibrary.first!,
                chapter: Audiobook.mockLibrary.first?.chapters.first,
                playerService: PlayerService(),
                nowPlayingService: NowPlayingService(),
                apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
                authStore: AuthStore.previewAuthenticated,
                persistenceController: PersistenceController(),
                logger: Logger()
            )
        )
    }
}
