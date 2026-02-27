import Foundation

struct AudiobookDetails: Hashable {
    let subtitle: String?
    let narrators: [String]
    let publishedYear: String?
    let publisher: String?
    let genres: [String]
    let description: String?
    let duration: TimeInterval?
    let sizeBytes: Int64?
    let chapters: [Chapter]
    let tracks: [AudiobookTrack]
}

struct AudiobookTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let duration: TimeInterval?
}
