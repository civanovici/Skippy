import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    private enum StorageKey {
        static let playbackProgress = "skippy.playback.progress.v1"
        static let bookmarks = "skippy.playback.bookmarks.v1"
    }

    private let userDefaults: UserDefaults
    private var playbackProgress: [String: PlaybackProgress]
    private var bookmarksByBookID: [String: [AudioBookmark]]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        playbackProgress = Self.load(
            key: StorageKey.playbackProgress,
            from: userDefaults,
            fallback: [:]
        )
        bookmarksByBookID = Self.load(
            key: StorageKey.bookmarks,
            from: userDefaults,
            fallback: [:]
        )
    }

    func save(_ progress: PlaybackProgress) {
        playbackProgress[progress.audiobookID] = progress
        persistPlaybackProgress()
    }

    func loadProgress(for audiobookID: String) -> PlaybackProgress? {
        playbackProgress[audiobookID]
    }

    func saveBookmarks(_ bookmarks: [AudioBookmark], for audiobookID: String) {
        bookmarksByBookID[audiobookID] = bookmarks
        persistBookmarks()
    }

    func loadBookmarks(for audiobookID: String) -> [AudioBookmark] {
        bookmarksByBookID[audiobookID] ?? []
    }

    private func persistPlaybackProgress() {
        guard let data = try? JSONEncoder().encode(playbackProgress) else {
            return
        }
        userDefaults.set(data, forKey: StorageKey.playbackProgress)
    }

    private func persistBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarksByBookID) else {
            return
        }
        userDefaults.set(data, forKey: StorageKey.bookmarks)
    }

    private static func load<T: Decodable>(
        key: String,
        from userDefaults: UserDefaults,
        fallback: T
    ) -> T {
        guard let data = userDefaults.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data)
        else {
            return fallback
        }
        return value
    }
}
