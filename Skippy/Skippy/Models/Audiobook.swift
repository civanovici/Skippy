import Foundation

struct Audiobook: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let progress: Double
    let coverURL: URL?
    let chapters: [Chapter]
}

extension Audiobook {
    static let mockLibrary: [Audiobook] = [
        Audiobook(
            id: "book-columbus-day",
            title: "Columbus Day",
            author: "Craig Alanson",
            progress: 0.35,
            coverURL: nil,
            chapters: [
                Chapter(id: "cd-1", title: "Chapter 1", duration: 980),
                Chapter(id: "cd-2", title: "Chapter 2", duration: 1120),
            ]
        ),
        Audiobook(
            id: "book-spec-ops",
            title: "SpecOps",
            author: "Craig Alanson",
            progress: 0.08,
            coverURL: nil,
            chapters: [
                Chapter(id: "so-1", title: "Chapter 1", duration: 1030),
                Chapter(id: "so-2", title: "Chapter 2", duration: 1180),
            ]
        ),
    ]
}
