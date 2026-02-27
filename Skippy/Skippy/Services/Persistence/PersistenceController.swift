import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    private var playbackProgress: [String: PlaybackProgress] = [:]

    private init() {}

    func save(_ progress: PlaybackProgress) {
        playbackProgress[progress.audiobookID] = progress
    }

    func loadProgress(for audiobookID: String) -> PlaybackProgress? {
        playbackProgress[audiobookID]
    }
}
