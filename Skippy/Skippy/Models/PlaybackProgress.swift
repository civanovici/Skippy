import Foundation

struct PlaybackProgress: Equatable, Hashable, Codable {
    let audiobookID: String
    let chapterID: String?
    var positionSeconds: TimeInterval
    var durationSeconds: TimeInterval
    var isFinished: Bool
    var updatedAt: Date
    var lastServerSyncAt: Date?

    var fraction: Double {
        guard durationSeconds > 0 else {
            return isFinished ? 1 : 0
        }
        return min(max(positionSeconds / durationSeconds, 0), 1)
    }
}
