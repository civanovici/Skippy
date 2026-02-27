import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    private let audiobook: Audiobook
    private let chapter: Chapter?
    private let playerService: PlayerServiceProtocol
    private let nowPlayingService: NowPlayingServiceProtocol

    var isPlaying = false

    var title: String { audiobook.title }
    var subtitle: String {
        if let chapter {
            return chapter.title
        }
        return audiobook.author
    }

    init(audiobook: Audiobook, chapter: Chapter?, playerService: PlayerServiceProtocol, nowPlayingService: NowPlayingServiceProtocol) {
        self.audiobook = audiobook
        self.chapter = chapter
        self.playerService = playerService
        self.nowPlayingService = nowPlayingService
    }

    func start() {
        playerService.play(audiobook: audiobook, chapter: chapter)
        nowPlayingService.update(audiobook: audiobook, chapter: chapter)
        isPlaying = true
    }

    func togglePlayPause() {
        if isPlaying {
            playerService.pause()
        } else {
            playerService.play(audiobook: audiobook, chapter: chapter)
        }
        isPlaying.toggle()
    }

    func seekBack() {
        playerService.seek(by: -15)
    }

    func seekForward() {
        playerService.seek(by: 30)
    }
}
