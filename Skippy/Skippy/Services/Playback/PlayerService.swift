import Foundation

protocol PlayerServiceProtocol {
    func play(audiobook: Audiobook, chapter: Chapter?)
    func pause()
    func seek(by seconds: TimeInterval)
}

final class PlayerService: PlayerServiceProtocol {
    private(set) var currentBook: Audiobook?
    private(set) var currentChapter: Chapter?

    func play(audiobook: Audiobook, chapter: Chapter?) {
        currentBook = audiobook
        currentChapter = chapter
    }

    func pause() {
        // Stub for Phase 1.
    }

    func seek(by seconds: TimeInterval) {
        _ = seconds
        // Stub for Phase 1.
    }
}
