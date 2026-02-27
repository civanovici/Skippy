import Foundation

struct PlaybackProgress: Equatable {
    let audiobookID: String
    let chapterID: String?
    let positionSeconds: TimeInterval
    let updatedAt: Date
}
