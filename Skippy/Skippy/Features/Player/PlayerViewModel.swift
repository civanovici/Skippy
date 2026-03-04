import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    struct ProgressConflict: Identifiable, Equatable {
        let id = UUID()
        let local: PlaybackProgress
        let remote: PlaybackProgress
    }

    enum SleepTimerOption: CaseIterable, Equatable {
        case off
        case minutes15
        case minutes30
        case minutes60

        var title: String {
            switch self {
            case .off: "Off"
            case .minutes15: "15 min"
            case .minutes30: "30 min"
            case .minutes60: "60 min"
            }
        }

        var duration: TimeInterval? {
            switch self {
            case .off: nil
            case .minutes15: 15 * 60
            case .minutes30: 30 * 60
            case .minutes60: 60 * 60
            }
        }
    }

    private let audiobook: Audiobook
    private var currentChapter: Chapter?
    private let playerService: PlayerServiceProtocol
    private let nowPlayingService: NowPlayingServiceProtocol
    private let apiClient: APIClientProtocol
    private let authStore: AuthStore
    private let downloadManager: DownloadManaging
    private let connectivityStore: ConnectivityStore
    private let persistenceController: PersistenceController
    private let logger: Logger

    private(set) var isPlaying = false
    private(set) var isSyncing = false
    private(set) var syncStatusText = "Local"
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var bookmarks: [AudioBookmark] = []
    private(set) var hasStarted = false
    var errorMessage: String?
    var progressConflict: ProgressConflict?
    var selectedSleepTimer: SleepTimerOption = .off
    var selectedRate: Float = 1.0
    let availableRates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
    private var tracks: [AudiobookTrack] = []

    private var sleepEndDate: Date?
    private var sleepTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var syncRequestID = 0
    private var lastTickSyncTime: TimeInterval = 0
    private var remoteSyncDisabled = false

    var title: String { audiobook.title }
    var subtitle: String {
        if let currentChapter {
            return currentChapter.title
        }
        return audiobook.author
    }

    var hasPreviousChapter: Bool {
        guard let chapterIndex else {
            return false
        }
        return chapterIndex > 0
    }

    var hasNextChapter: Bool {
        guard let chapterIndex else {
            return false
        }
        return chapterIndex < (audiobook.chapters.count - 1)
    }

    var progressFraction: Double {
        guard duration > 0, duration.isFinite else {
            return 0
        }
        return min(max(currentTime / duration, 0), 1)
    }

    var progressPercentText: String {
        "\(Int((progressFraction * 100).rounded()))%"
    }

    var remainingTimeText: String {
        formatTime(max(duration - currentTime, 0))
    }

    var currentTimeText: String {
        formatTime(currentTime)
    }

    var sleepRemainingText: String? {
        guard let sleepEndDate else {
            return nil
        }
        let remaining = max(sleepEndDate.timeIntervalSinceNow, 0)
        return remaining > 0 ? "Sleep in \(formatTime(remaining))" : nil
    }

    init(
        audiobook: Audiobook,
        chapter: Chapter?,
        playerService: PlayerServiceProtocol,
        nowPlayingService: NowPlayingServiceProtocol,
        apiClient: APIClientProtocol,
        authStore: AuthStore,
        downloadManager: DownloadManaging,
        connectivityStore: ConnectivityStore,
        persistenceController: PersistenceController,
        logger: Logger
    ) {
        self.audiobook = audiobook
        self.currentChapter = chapter
        self.playerService = playerService
        self.nowPlayingService = nowPlayingService
        self.apiClient = apiClient
        self.authStore = authStore
        self.downloadManager = downloadManager
        self.connectivityStore = connectivityStore
        self.persistenceController = persistenceController
        self.logger = logger
    }

    func stop() {
        sleepTask?.cancel()
        syncTask?.cancel()
        playerService.onTick = nil
        playerService.onError = nil
    }

    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        nowPlayingService.update(audiobook: audiobook, chapter: currentChapter)
        nowPlayingService.updatePlayback(currentTime: currentTime, duration: duration, rate: selectedRate, isPlaying: false)
        playerService.onTick = { [weak self] newTime in
            guard let self else { return }
            Task { @MainActor in
                self.onPlayerTick(newTime)
            }
        }
        playerService.onError = { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                switch error {
                case .noPlayableTracks:
                    self.errorMessage = "Playback unavailable: no playable tracks were returned by the server."
                case .failedToLoadTrack:
                    self.errorMessage = "Playback failed while loading an audio track. Please retry."
                }
                self.isPlaying = false
                self.syncStatusText = "Playback error"
            }
        }

        let local = persistenceController.loadProgress(for: audiobook.id)
        var remoteProgress: PlaybackProgress?
        var remoteBookmarks: [AudioBookmark] = []
        var remoteTracks: [AudiobookTrack] = []
        let localTracks = downloadManager.localTracks(for: audiobook.id)
        let shouldUseOffline = connectivityStore.isOfflineEffective

        if !shouldUseOffline, let session = authStore.session {
            remoteProgress = try? await apiClient.audiobookshelf.fetchMediaProgress(
                session: session,
                itemID: audiobook.id
            )
            if let details = try? await apiClient.audiobookshelf.fetchBookDetails(
                session: session,
                itemID: audiobook.id
            ) {
                if remoteProgress == nil {
                    remoteProgress = details.userProgress
                }
                remoteBookmarks = details.bookmarks
                remoteTracks = details.tracks
            }
            if remoteProgress != nil || !remoteTracks.isEmpty {
                connectivityStore.markServerReachable()
            }
        }

        if let local, let remoteProgress, abs(local.positionSeconds - remoteProgress.positionSeconds) > 60 {
            progressConflict = ProgressConflict(local: local, remote: remoteProgress)
        }

        let chosenProgress = (local ?? remoteProgress)
            ?? PlaybackProgress(
                audiobookID: audiobook.id,
                chapterID: currentChapter?.id,
                positionSeconds: 0,
                durationSeconds: resolvedDurationHint(),
                isFinished: false,
                updatedAt: Date(),
                lastServerSyncAt: nil
            )

        bookmarks = mergedBookmarks(
            local: persistenceController.loadBookmarks(for: audiobook.id),
            remote: remoteBookmarks
        )
        persistenceController.saveBookmarks(bookmarks, for: audiobook.id)

        playerService.configure(
            audiobook: audiobook,
            chapter: currentChapter,
            initialTime: chosenProgress.positionSeconds,
            tracks: localTracks.isEmpty ? remoteTracks : localTracks
        )
        tracks = localTracks.isEmpty ? remoteTracks : localTracks
        duration = max(playerService.duration, chosenProgress.durationSeconds)
        currentTime = min(chosenProgress.positionSeconds, max(duration, chosenProgress.positionSeconds))
        isPlaying = false

        persistLocalProgress()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        if let conflict = progressConflict {
            errorMessage = "Playback position mismatch (>1 min). Choose app time (\(formatTime(conflict.local.positionSeconds))) or server time (\(formatTime(conflict.remote.positionSeconds)))."
            return
        }
        playerService.play()
        isPlaying = playerService.isPlaying
        nowPlayingService.updatePlayback(currentTime: currentTime, duration: duration, rate: selectedRate, isPlaying: isPlaying)
        scheduleSync(immediate: true)
    }

    func pause() {
        playerService.pause()
        isPlaying = playerService.isPlaying
        nowPlayingService.updatePlayback(currentTime: currentTime, duration: duration, rate: selectedRate, isPlaying: isPlaying)
        scheduleSync(immediate: true)
    }

    func seekBack() {
        seek(to: currentTime - 15)
    }

    func seekForward() {
        seek(to: currentTime + 15)
    }

    func seek(to value: TimeInterval) {
        playerService.seek(to: value)
        currentTime = playerService.currentTime
        persistLocalProgress()
        scheduleSync(immediate: true)
    }

    func markAsPlayed() {
        seek(to: duration > 0 ? duration : currentTime)
        pause()
        persistLocalProgress(forceFinished: true)
        scheduleSync(immediate: true, forceFinished: true)
    }

    func setRate(_ rate: Float) {
        selectedRate = rate
        playerService.setRate(rate)
        nowPlayingService.updatePlayback(currentTime: currentTime, duration: duration, rate: selectedRate, isPlaying: isPlaying)
    }

    func previousChapter() {
        guard let chapterIndex, chapterIndex > 0 else {
            return
        }
        switchToChapter(at: chapterIndex - 1)
    }

    func nextChapter() {
        guard let chapterIndex, chapterIndex < (audiobook.chapters.count - 1) else {
            return
        }
        switchToChapter(at: chapterIndex + 1)
    }

    func selectChapter(_ chapter: Chapter) {
        if let index = audiobook.chapters.firstIndex(where: { $0.id == chapter.id }) {
            switchToChapter(at: index)
        }
    }

    func addBookmark() async {
        let newBookmark = AudioBookmark(
            audiobookID: audiobook.id,
            title: "Bookmark \(currentTimeText)",
            time: currentTime,
            createdAt: Date()
        )

        if !bookmarks.contains(where: { abs($0.time - newBookmark.time) < 0.5 }) {
            bookmarks.append(newBookmark)
            bookmarks.sort { $0.time < $1.time }
            persistenceController.saveBookmarks(bookmarks, for: audiobook.id)
        }

        guard let session = authStore.session else {
            return
        }

        do {
            let remote = try await apiClient.audiobookshelf.createBookmark(
                session: session,
                itemID: audiobook.id,
                time: newBookmark.time,
                title: newBookmark.title
            )
            bookmarks.removeAll { abs($0.time - remote.time) < 0.5 }
            bookmarks.append(remote)
            bookmarks.sort { $0.time < $1.time }
            persistenceController.saveBookmarks(bookmarks, for: audiobook.id)
        } catch {
            logger.error("Failed to sync bookmark create: \(error.localizedDescription)")
            errorMessage = "Saved locally. Bookmark sync failed."
        }
    }

    func removeBookmark(_ bookmark: AudioBookmark) async {
        bookmarks.removeAll { abs($0.time - bookmark.time) < 0.5 }
        persistenceController.saveBookmarks(bookmarks, for: audiobook.id)

        guard let session = authStore.session else {
            return
        }

        do {
            try await apiClient.audiobookshelf.removeBookmark(
                session: session,
                itemID: audiobook.id,
                time: bookmark.time
            )
        } catch {
            logger.error("Failed to sync bookmark removal: \(error.localizedDescription)")
            errorMessage = "Bookmark removed locally. Remote removal failed."
        }
    }

    func jumpToBookmark(_ bookmark: AudioBookmark) {
        seek(to: bookmark.time)
    }

    func setSleepTimer(_ option: SleepTimerOption) {
        selectedSleepTimer = option
        sleepTask?.cancel()
        sleepTask = nil
        sleepEndDate = nil

        guard let duration = option.duration else {
            return
        }
        sleepEndDate = Date().addingTimeInterval(duration)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self else { return }
            await MainActor.run {
                self.pause()
                self.selectedSleepTimer = .off
                self.sleepEndDate = nil
            }
        }
    }

    private func onPlayerTick(_ newTime: TimeInterval) {
        currentTime = newTime
        duration = max(duration, playerService.duration)
        if duration > 0, currentTime >= duration {
            isPlaying = false
        }
        nowPlayingService.updatePlayback(currentTime: currentTime, duration: duration, rate: selectedRate, isPlaying: isPlaying)
        persistLocalProgress()
        if (currentTime - lastTickSyncTime) >= 15 {
            lastTickSyncTime = currentTime
            scheduleSync()
        }
    }

    private func mergedBookmarks(local: [AudioBookmark], remote: [AudioBookmark]) -> [AudioBookmark] {
        var byBucket: [Int: AudioBookmark] = [:]
        for bookmark in local + remote {
            let key = Int(bookmark.time.rounded(.towardZero))
            if let existing = byBucket[key] {
                let existingDate = existing.createdAt ?? .distantPast
                let incomingDate = bookmark.createdAt ?? .distantPast
                byBucket[key] = incomingDate >= existingDate ? bookmark : existing
            } else {
                byBucket[key] = bookmark
            }
        }
        return byBucket.values.sorted { $0.time < $1.time }
    }

    private func persistLocalProgress(forceFinished: Bool = false) {
        let entry = PlaybackProgress(
            audiobookID: audiobook.id,
            chapterID: currentChapter?.id,
            positionSeconds: currentTime,
            durationSeconds: max(duration, resolvedDurationHint()),
            isFinished: forceFinished || (duration > 0 && currentTime >= duration),
            updatedAt: Date(),
            lastServerSyncAt: persistenceController.loadProgress(for: audiobook.id)?.lastServerSyncAt
        )
        persistenceController.save(entry)
    }

    private func scheduleSync(immediate: Bool = false, forceFinished: Bool = false) {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: .seconds(2))
            }
            guard let self else { return }
            await self.syncProgress(forceFinished: forceFinished)
        }
    }

    private func syncProgress(forceFinished: Bool = false) async {
        guard !remoteSyncDisabled else {
            syncStatusText = "Local only"
            return
        }
        guard let session = authStore.session else {
            syncStatusText = "Local only"
            return
        }

        syncRequestID += 1
        let requestID = syncRequestID
        isSyncing = true

        do {
            let synced = try await apiClient.audiobookshelf.updateMediaProgress(
                session: session,
                itemID: audiobook.id,
                currentTime: currentTime,
                duration: max(duration, resolvedDurationHint()),
                isFinished: forceFinished || (duration > 0 && currentTime >= duration)
            )
            guard requestID == syncRequestID else {
                return
            }
            persistenceController.save(synced)
            syncStatusText = "Synced"
            errorMessage = nil
        } catch {
            if let apiError = error as? APIError, apiError.isAPIMismatchLike {
                remoteSyncDisabled = true
                syncStatusText = "Local only"
                logger.info("Progress sync disabled for this session due to server/API mismatch.")
                return
            }
            guard requestID == syncRequestID else {
                return
            }
            logger.error("Progress sync failed: \(error.localizedDescription)")
            syncStatusText = "Pending sync"
        }

        if requestID == syncRequestID {
            isSyncing = false
        }
    }

    private func resolvedDurationHint() -> TimeInterval {
        if let currentChapter {
            return currentChapter.duration
        }
        return audiobook.chapters.reduce(0) { $0 + $1.duration }
    }

    private var chapterIndex: Int? {
        guard let currentChapter else {
            return nil
        }
        return audiobook.chapters.firstIndex(where: { $0.id == currentChapter.id })
    }

    private func switchToChapter(at index: Int) {
        guard audiobook.chapters.indices.contains(index) else {
            return
        }

        syncTask?.cancel()
        let wasPlaying = isPlaying
        currentChapter = audiobook.chapters[index]
        playerService.configure(
            audiobook: audiobook,
            chapter: currentChapter,
            initialTime: 0,
            tracks: tracks
        )
        currentTime = 0
        duration = max(playerService.duration, resolvedDurationHint())
        nowPlayingService.update(audiobook: audiobook, chapter: currentChapter)
        persistLocalProgress()
        if wasPlaying {
            playerService.play()
            isPlaying = true
        } else {
            playerService.pause()
            isPlaying = false
        }
        nowPlayingService.updatePlayback(currentTime: currentTime, duration: duration, rate: selectedRate, isPlaying: isPlaying)
        scheduleSync(immediate: true)
    }

    func resolveProgressConflict(useServer: Bool) {
        guard let conflict = progressConflict else {
            return
        }

        let chosen = useServer ? conflict.remote : conflict.local
        if let chapterID = chosen.chapterID,
           let chapter = audiobook.chapters.first(where: { $0.id == chapterID }) {
            currentChapter = chapter
        }

        playerService.configure(
            audiobook: audiobook,
            chapter: currentChapter,
            initialTime: chosen.positionSeconds,
            tracks: tracks
        )
        duration = max(playerService.duration, chosen.durationSeconds, resolvedDurationHint())
        currentTime = min(chosen.positionSeconds, max(duration, chosen.positionSeconds))
        isPlaying = false
        progressConflict = nil
        nowPlayingService.update(audiobook: audiobook, chapter: currentChapter)
        nowPlayingService.updatePlayback(currentTime: currentTime, duration: duration, rate: selectedRate, isPlaying: false)
        persistLocalProgress()
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
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
