import Foundation

struct UserListeningStats: Equatable {
    let totalTimeSeconds: TimeInterval
    let todayTimeSeconds: TimeInterval
    let dayOfWeekHeatmap: [Int: TimeInterval]
    let dailyTotals: [DailyListeningPoint]
    let topItems: [ListeningItemStat]
    let recentSessions: [ListeningSession]
}

struct DailyListeningPoint: Equatable, Identifiable {
    let date: Date
    let seconds: TimeInterval

    var id: Date { date }
}

struct ListeningItemStat: Equatable, Identifiable {
    let itemID: String
    let title: String
    let author: String?
    let seconds: TimeInterval

    var percentOfTotal: Double?
    var id: String { itemID }
}

struct ListeningSession: Equatable, Identifiable {
    let id: String
    let itemID: String?
    let itemTitle: String?
    let itemAuthor: String?
    let seconds: TimeInterval
    let startTime: TimeInterval?
    let currentTime: TimeInterval?
    let startedAt: Date?
    let updatedAt: Date?
}

struct LibraryStatsSnapshot: Equatable {
    let libraryID: String
    let libraryName: String
    let totalItems: Int
    let totalDurationSeconds: TimeInterval
    let totalSizeBytes: Int64
    let totalAuthors: Int
    let totalGenres: Int
    let numAudioTracks: Int
    let largestItems: [LibraryItemStat]
    let longestItems: [LibraryItemStat]
    let authorsWithCount: [NamedCountStat]
    let genresWithCount: [NamedCountStat]
}

struct LibraryItemStat: Equatable, Identifiable {
    let itemID: String
    let title: String
    let sizeBytes: Int64?
    let durationSeconds: TimeInterval?

    var id: String { itemID }
}

struct NamedCountStat: Equatable, Identifiable {
    let id: String
    let name: String
    let count: Int
}
