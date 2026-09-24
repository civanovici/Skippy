import Foundation

struct DownloadRecord: Codable, Equatable {
    enum State: String, Codable, Equatable {
        case queued
        case downloading
        case paused
        case completed
        case failed
    }

    let audiobookID: String
    var state: State
    var progress: Double
    var downloadedBytes: Int64
    var totalBytes: Int64?
    var errorMessage: String?
}

struct DownloadedBookRecord: Codable, Equatable {
    let bookID: String
    let title: String
    let author: String
    let coverURL: URL?
    let chapters: [Chapter]
    var tracks: [DownloadedTrackRecord]
    var downloadedAt: Date?

    var isFullyDownloaded: Bool {
        !tracks.isEmpty && tracks.allSatisfy { $0.status == .completed }
    }
}

struct DownloadedTrackRecord: Codable, Equatable {
    enum Status: String, Codable, Equatable {
        case pending
        case downloading
        case paused
        case completed
        case failed
    }

    let trackID: String
    let title: String
    let startOffset: TimeInterval
    let duration: TimeInterval?
    var remoteURL: URL
    var localFilePath: String
    var bytesDownloaded: Int64
    var totalBytes: Int64?
    var status: Status
    var resumeData: Data?
    var errorMessage: String?

    var localFileURL: URL {
        URL(fileURLWithPath: localFilePath)
    }
}
