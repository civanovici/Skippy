import Foundation
import MediaPlayer

protocol NowPlayingServiceProtocol {
    func update(audiobook: Audiobook, chapter: Chapter?)
    func updatePlayback(currentTime: TimeInterval, duration: TimeInterval, rate: Float, isPlaying: Bool)
}

final class NowPlayingService: NowPlayingServiceProtocol {
    private(set) var currentTitle: String?
    private var currentBookTitle: String?
    private var currentChapterTitle: String?
    private var elapsedPlaybackTime: TimeInterval = 0
    private var playbackDuration: TimeInterval = 0
    private var playbackRate: Float = 1.0
    private var isPlaying = false

    func update(audiobook: Audiobook, chapter: Chapter?) {
        currentBookTitle = audiobook.title
        currentChapterTitle = chapter?.title
        if let chapter {
            currentTitle = "\(audiobook.title) • \(chapter.title)"
        } else {
            currentTitle = audiobook.title
        }
        publishNowPlayingInfo()
    }

    func updatePlayback(currentTime: TimeInterval, duration: TimeInterval, rate: Float, isPlaying: Bool) {
        elapsedPlaybackTime = currentTime.isFinite ? max(currentTime, 0) : 0
        playbackDuration = duration.isFinite ? max(duration, 0) : 0
        playbackRate = rate.isFinite ? max(rate, 0) : 1
        self.isPlaying = isPlaying
        publishNowPlayingInfo()
    }

    private func publishNowPlayingInfo() {
        guard let currentBookTitle else { return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentBookTitle
        if let currentChapterTitle {
            info[MPMediaItemPropertyAlbumTitle] = currentChapterTitle
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedPlaybackTime
        if playbackDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = playbackDuration
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(playbackRate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
