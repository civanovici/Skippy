import Foundation

struct DownloadRecord: Equatable {
    enum State: Equatable {
        case queued
        case downloading
        case paused
        case completed
        case failed
    }

    let audiobookID: String
    var state: State
    var progress: Double
}
