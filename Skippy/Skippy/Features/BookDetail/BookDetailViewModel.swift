import Foundation
import Observation

@MainActor
@Observable
final class BookDetailViewModel {
    let book: Audiobook

    var details: AudiobookDetails?
    var isLoading = false
    var errorMessage: String?

    private let apiClient: APIClientProtocol
    private let authStore: AuthStore
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

    init(book: Audiobook, apiClient: APIClientProtocol, authStore: AuthStore, logger: Logger) {
        self.book = book
        self.apiClient = apiClient
        self.authStore = authStore
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
        return Self.durationFormatter.string(from: total) ?? "Unknown"
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
}
