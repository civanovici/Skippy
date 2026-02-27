import Foundation

protocol NowPlayingServiceProtocol {
    func update(audiobook: Audiobook, chapter: Chapter?)
}

final class NowPlayingService: NowPlayingServiceProtocol {
    private(set) var currentTitle: String?

    func update(audiobook: Audiobook, chapter: Chapter?) {
        if let chapter {
            currentTitle = "\(audiobook.title) • \(chapter.title)"
        } else {
            currentTitle = audiobook.title
        }
    }
}
