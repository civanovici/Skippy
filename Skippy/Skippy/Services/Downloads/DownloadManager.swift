import Foundation

protocol DownloadManaging {
    func enqueue(_ audiobook: Audiobook)
    func record(for audiobookID: String) -> DownloadRecord?
}

final class DownloadManager: DownloadManaging {
    private var records: [String: DownloadRecord] = [:]

    func enqueue(_ audiobook: Audiobook) {
        records[audiobook.id] = DownloadRecord(audiobookID: audiobook.id, state: .queued, progress: 0)
    }

    func record(for audiobookID: String) -> DownloadRecord? {
        records[audiobookID]
    }
}
