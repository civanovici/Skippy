import Foundation
import Observation

@MainActor
@Observable
final class BookDetailViewModel {
    enum ChapterProgressState: Equatable {
        case completed
        case inProgress
        case upcoming
    }

    let book: Audiobook

    var details: AudiobookDetails?
    var isLoading = false
    var errorMessage: String?

    private let apiClient: APIClientProtocol
    private let authStore: AuthStore
    private let persistenceController: PersistenceController
    private let logger: Logger
    private var loadRequestID = 0

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()

    init(
        book: Audiobook,
        apiClient: APIClientProtocol,
        authStore: AuthStore,
        persistenceController: PersistenceController,
        logger: Logger
    ) {
        self.book = book
        self.apiClient = apiClient
        self.authStore = authStore
        self.persistenceController = persistenceController
        self.logger = logger
    }

    func load() async {
        loadRequestID += 1
        let requestID = loadRequestID

        guard let session = authStore.session else {
            if requestID == loadRequestID {
                errorMessage = "You are not signed in."
                isLoading = false
            }
            return
        }

        if requestID == loadRequestID {
            isLoading = true
            errorMessage = nil
        }

        do {
            let fetched = try await apiClient.audiobookshelf.fetchBookDetails(session: session, itemID: book.id)
            guard requestID == loadRequestID else {
                return
            }
            details = fetched
        } catch {
            guard requestID == loadRequestID else {
                return
            }
            logger.error("Book details fetch failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        if requestID == loadRequestID {
            isLoading = false
        }
    }

    var subtitle: String? {
        details?.subtitle
    }

    var narratorsText: String {
        let narrators = details?.narrators ?? []
        return narrators.isEmpty ? "Unknown" : narrators.joined(separator: ", ")
    }

    var publishedYearText: String {
        details?.publishedYear ?? "Unknown"
    }

    var publisherText: String {
        details?.publisher ?? "Unknown"
    }

    var genresText: String {
        let genres = details?.genres ?? []
        return genres.isEmpty ? "Unknown" : genres.joined(separator: ", ")
    }

    var durationText: String {
        let total = details?.duration ?? displayChapters.reduce(0) { $0 + $1.duration }
        guard total > 0 else {
            return "Unknown"
        }
        let totalText = Self.durationFormatter.string(from: total) ?? "Unknown"
        let elapsed = resolvedProgressSeconds(totalDuration: total)
        let elapsedText = Self.durationFormatter.string(from: elapsed) ?? "0m"
        let percent = Int((min(max(elapsed / total, 0), 1) * 100).rounded())
        return "\(totalText) / \(elapsedText) / \(percent)%"
    }

    var sizeText: String {
        guard let size = details?.sizeBytes, size > 0 else {
            return "Unknown"
        }
        return Self.sizeFormatter.string(fromByteCount: size)
    }

    var descriptionText: String {
        details?.description ?? "No description available."
    }

    var displayChapters: [Chapter] {
        if let detailed = details?.chapters, !detailed.isEmpty {
            return detailed
        }
        return book.chapters
    }

    var tracks: [AudiobookTrack] {
        details?.tracks ?? []
    }

    var resumeChapter: Chapter? {
        displayChapters.first
    }

    func chapterProgressState(for chapter: Chapter) -> ChapterProgressState {
        guard let chapterIndex = displayChapters.firstIndex(where: { $0.id == chapter.id }) else {
            return .upcoming
        }
        let elapsed = resolvedProgressSeconds(totalDuration: details?.duration ?? displayChapters.reduce(0) { $0 + $1.duration })
        let chapterStart = displayChapters.prefix(chapterIndex).reduce(0) { $0 + max($1.duration, 0) }
        let chapterEnd = chapterStart + max(chapter.duration, 0)

        if elapsed >= chapterEnd, chapter.duration > 0 {
            return .completed
        }
        if elapsed > chapterStart {
            return .inProgress
        }
        return .upcoming
    }

    private func resolvedProgressSeconds(totalDuration: TimeInterval) -> TimeInterval {
        let local = persistenceController.loadProgress(for: book.id)
        let remote = details?.userProgress
        let progress = chooseMostRecent(local: local, remote: remote)

        if let progress {
            if progress.isFinished {
                return max(totalDuration, progress.durationSeconds)
            }
            return max(progress.positionSeconds, 0)
        }
        return max(min(book.progress, 1), 0) * max(totalDuration, 0)
    }

    private func chooseMostRecent(local: PlaybackProgress?, remote: PlaybackProgress?) -> PlaybackProgress? {
        switch (local, remote) {
        case let (lhs?, rhs?):
            return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }
}
