import AVFoundation
import Foundation
import MediaPlayer
import UIKit

enum PlayerServiceError: Error, Equatable {
    case noPlayableTracks
    case failedToLoadTrack
}

@MainActor
protocol PlayerServiceProtocol: AnyObject {
    var currentBook: Audiobook? { get }
    var currentChapter: Chapter? { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    var rate: Float { get }
    var onTick: ((TimeInterval) -> Void)? { get set }
    var onError: ((PlayerServiceError) -> Void)? { get set }

    func configure(
        audiobook: Audiobook,
        chapter: Chapter?,
        initialTime: TimeInterval,
        tracks: [AudiobookTrack]
    )
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func seek(by seconds: TimeInterval)
    func setRate(_ rate: Float)
}

@MainActor
final class PlayerService: PlayerServiceProtocol {
    private struct TrackSource {
        let url: URL
        let startOffset: TimeInterval
        let duration: TimeInterval
    }

    private(set) var currentBook: Audiobook?
    private(set) var currentChapter: Chapter?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var rate: Float = 1.0
    var onTick: ((TimeInterval) -> Void)?
    var onError: ((PlayerServiceError) -> Void)?

    private let player = AVPlayer()
    private var tracks: [TrackSource] = []
    private var currentTrackIndex = 0
    private var timeObserverToken: Any?
    private var endObserverToken: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var interruptionObserverToken: NSObjectProtocol?
    private var routeChangeObserverToken: NSObjectProtocol?
    private var stalledObserverToken: NSObjectProtocol?
    private var failedToEndObserverToken: NSObjectProtocol?
    private var didEnterBackgroundObserverToken: NSObjectProtocol?
    private var reasonForWaitingObservation: NSKeyValueObservation?
    private var wasPlayingBeforeInterruption = false

    init() {
        configureAudioSession()
        player.automaticallyWaitsToMinimizeStalling = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        installTimeObserver()
        installAudioLifecycleObservers()
        configureRemoteCommands()
        installAppLifecycleObserver()
    }

    deinit {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        if let endObserverToken {
            NotificationCenter.default.removeObserver(endObserverToken)
        }
        if let interruptionObserverToken {
            NotificationCenter.default.removeObserver(interruptionObserverToken)
        }
        if let routeChangeObserverToken {
            NotificationCenter.default.removeObserver(routeChangeObserverToken)
        }
        if let stalledObserverToken {
            NotificationCenter.default.removeObserver(stalledObserverToken)
        }
        if let failedToEndObserverToken {
            NotificationCenter.default.removeObserver(failedToEndObserverToken)
        }
        if let didEnterBackgroundObserverToken {
            NotificationCenter.default.removeObserver(didEnterBackgroundObserverToken)
        }
        itemStatusObservation = nil
        reasonForWaitingObservation = nil
    }

    func configure(
        audiobook: Audiobook,
        chapter: Chapter?,
        initialTime: TimeInterval,
        tracks: [AudiobookTrack]
    ) {
        currentBook = audiobook
        currentChapter = chapter
        self.tracks = resolvedTracks(audiobook: audiobook, tracks: tracks)
        guard !self.tracks.isEmpty else {
            player.replaceCurrentItem(with: nil)
            currentTime = 0
            duration = 0
            isPlaying = false
            onError?(.noPlayableTracks)
            return
        }
        duration = resolvedDuration(audiobook: audiobook, tracks: self.tracks, chapter: chapter)
        currentTime = clamp(initialTime)

        let absoluteTime = absolutePlaybackTime(for: currentTime)
        let placement = trackPlacement(for: absoluteTime)
        currentTrackIndex = placement.trackIndex
        loadTrack(index: placement.trackIndex, seekTime: placement.localTime, autoplay: false)
    }

    func play() {
        guard player.currentItem != nil else {
            return
        }
        ensureAudioSessionIsActive()
        isPlaying = true
        player.play()
        player.rate = rate
    }

    func pause() {
        isPlaying = false
        player.pause()
    }

    func seek(to time: TimeInterval) {
        let clamped = clamp(time)
        let absoluteTime = absolutePlaybackTime(for: clamped)
        let placement = trackPlacement(for: absoluteTime)
        currentTime = clamped

        if placement.trackIndex == currentTrackIndex {
            seekCurrentTrack(to: placement.localTime)
            return
        }

        loadTrack(index: placement.trackIndex, seekTime: placement.localTime, autoplay: isPlaying)
    }

    func seek(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func setRate(_ rate: Float) {
        self.rate = min(max(rate, 0.5), 3.0)
        guard isPlaying else {
            return
        }
        player.rate = self.rate
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
        } catch {
            // Best-effort: playback can still start, but background behavior may be degraded.
        }
    }

    private func ensureAudioSessionIsActive() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Keep attempting playback even if re-activation fails.
        }
    }

    private func installTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.updateCurrentTime(using: time)
        }
    }

    private func installAudioLifecycleObservers() {
        interruptionObserverToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }

            switch type {
            case .began:
                self.wasPlayingBeforeInterruption = self.isPlaying
            case .ended:
                if self.wasPlayingBeforeInterruption {
                    self.play()
                }
                self.wasPlayingBeforeInterruption = false
            @unknown default:
                break
            }
        }

        routeChangeObserverToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.ensureAudioSessionIsActive()
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]

        let capturedPlayer = player
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            try? AVAudioSession.sharedInstance().setActive(true)
            capturedPlayer.play()
            capturedPlayer.rate = self.rate
            Task { @MainActor in self.isPlaying = true }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            capturedPlayer.pause()
            Task { @MainActor in self?.isPlaying = false }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if capturedPlayer.rate == 0 {
                try? AVAudioSession.sharedInstance().setActive(true)
                capturedPlayer.play()
                capturedPlayer.rate = self.rate
                Task { @MainActor in self.isPlaying = true }
            } else {
                capturedPlayer.pause()
                Task { @MainActor in self.isPlaying = false }
            }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.seek(by: 15) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.seek(by: -15) }
            return .success
        }
    }

    private func installAppLifecycleObserver() {
        didEnterBackgroundObserverToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.isPlaying {
                self.ensureAudioSessionIsActive()
                self.player.play()
                self.player.rate = self.rate
            }
        }
    }

    private func installEndObserver() {
        if let endObserverToken {
            NotificationCenter.default.removeObserver(endObserverToken)
        }
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.advanceToNextTrackOrFinish()
        }
    }

    private func loadTrack(index: Int, seekTime: TimeInterval, autoplay: Bool) {
        guard tracks.indices.contains(index) else {
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            return
        }

        currentTrackIndex = index
        let item = AVPlayerItem(url: tracks[index].url)
        disableVideoTracks(for: item)
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            Task { @MainActor in
                guard let self else { return }
                if observedItem.status == .failed {
                    self.pause()
                    self.onError?(.failedToLoadTrack)
                }
            }
        }
        player.replaceCurrentItem(with: item)
        installEndObserver()
        installItemObservers(item: item)

        seekCurrentTrack(to: seekTime) { [weak self] in
            guard let self else { return }
            if autoplay {
                self.player.play()
                self.player.rate = self.rate
                self.isPlaying = true
            } else {
                self.player.pause()
            }
        }
    }

    private func seekCurrentTrack(to seconds: TimeInterval, completion: (() -> Void)? = nil) {
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            completion?()
        }
    }

    private func updateCurrentTime(using localTrackTime: CMTime) {
        guard tracks.indices.contains(currentTrackIndex) else {
            return
        }

        let track = tracks[currentTrackIndex]
        let absolute = max(localTrackTime.seconds, 0) + track.startOffset
        currentTime = clamp(relativePlaybackTime(for: absolute))
        onTick?(currentTime)
    }

    private func advanceToNextTrackOrFinish() {
        let nextIndex = currentTrackIndex + 1
        guard tracks.indices.contains(nextIndex) else {
            isPlaying = false
            currentTime = duration
            onTick?(currentTime)
            return
        }
        loadTrack(index: nextIndex, seekTime: 0, autoplay: isPlaying)
    }

    private func installItemObservers(item: AVPlayerItem) {
        if let stalledObserverToken {
            NotificationCenter.default.removeObserver(stalledObserverToken)
        }
        if let failedToEndObserverToken {
            NotificationCenter.default.removeObserver(failedToEndObserverToken)
        }

        stalledObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.ensureAudioSessionIsActive()
            if self.isPlaying {
                self.player.play()
                self.player.rate = self.rate
            }
        }

        failedToEndObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.pause()
            self.onError?(.failedToLoadTrack)
        }
    }

    private func disableVideoTracks(for item: AVPlayerItem) {
        for track in item.tracks {
            if track.assetTrack?.mediaType == .video {
                track.isEnabled = false
            }
        }
    }

    private func resolvedTracks(audiobook: Audiobook, tracks: [AudiobookTrack]) -> [TrackSource] {
        let validRemoteTracks = tracks.compactMap { track -> TrackSource? in
            guard let url = track.streamURL else {
                return nil
            }
            let inferredDuration = max(track.duration ?? 0, 0)
            return TrackSource(
                url: url,
                startOffset: max(track.startOffset, 0),
                duration: inferredDuration
            )
        }
        if !validRemoteTracks.isEmpty {
            return validRemoteTracks.sorted { $0.startOffset < $1.startOffset }
        }
        return []
    }

    private func resolvedDuration(audiobook: Audiobook, tracks: [TrackSource], chapter: Chapter?) -> TimeInterval {
        if let chapter {
            return max(chapter.duration, 0)
        }
        if let lastTrack = tracks.last {
            let trackTail = lastTrack.startOffset + max(lastTrack.duration, 0)
            if trackTail > 0 {
                return trackTail
            }
        }
        let chapterTotal = audiobook.chapters.reduce(0) { $0 + max($1.duration, 0) }
        return max(chapterTotal, 0)
    }

    private func clamp(_ value: TimeInterval) -> TimeInterval {
        guard duration > 0 else {
            return max(0, value)
        }
        return min(max(value, 0), duration)
    }

    private func absolutePlaybackTime(for relativeTime: TimeInterval) -> TimeInterval {
        guard let chapter = currentChapter,
              let chapterIndex = currentBook?.chapters.firstIndex(where: { $0.id == chapter.id }) else {
            return relativeTime
        }

        let chapterStart = currentBook?.chapters
            .prefix(chapterIndex)
            .reduce(0) { $0 + max($1.duration, 0) } ?? 0
        return chapterStart + relativeTime
    }

    private func relativePlaybackTime(for absoluteTime: TimeInterval) -> TimeInterval {
        guard let chapter = currentChapter,
              let chapterIndex = currentBook?.chapters.firstIndex(where: { $0.id == chapter.id }) else {
            return absoluteTime
        }

        let chapterStart = currentBook?.chapters
            .prefix(chapterIndex)
            .reduce(0) { $0 + max($1.duration, 0) } ?? 0
        return max(absoluteTime - chapterStart, 0)
    }

    private func trackPlacement(for absoluteTime: TimeInterval) -> (trackIndex: Int, localTime: TimeInterval) {
        guard !tracks.isEmpty else {
            return (0, max(absoluteTime, 0))
        }

        let clampedAbsolute = max(absoluteTime, 0)
        var bestIndex = tracks.indices.last ?? 0
        for index in tracks.indices {
            let track = tracks[index]
            let nextOffset = tracks.indices.contains(index + 1) ? tracks[index + 1].startOffset : .greatestFiniteMagnitude
            if clampedAbsolute >= track.startOffset && clampedAbsolute < nextOffset {
                bestIndex = index
                break
            }
        }
        let local = max(clampedAbsolute - tracks[bestIndex].startOffset, 0)
        return (bestIndex, local)
    }
}
