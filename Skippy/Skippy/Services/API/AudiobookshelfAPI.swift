import Foundation

protocol AudiobookshelfAPI {
    func login(serverURL: String, username: String, password: String) async throws -> UserSession
    func fetchLibrary(session: UserSession) async throws -> [Audiobook]
    func fetchBookDetails(session: UserSession, itemID: String) async throws -> AudiobookDetails
    func fetchPersonalizedShelves(session: UserSession) async throws -> [HomeShelf]
    func fetchSeries(session: UserSession) async throws -> [HomeShelf]
    func fetchCollections(session: UserSession) async throws -> [HomeShelf]
    func search(session: UserSession, query: String) async throws -> SearchResult
}

struct AudiobookshelfHTTPAPI: AudiobookshelfAPI {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func login(serverURL: String, username: String, password: String) async throws -> UserSession {
        guard let baseURL = URL(string: serverURL), baseURL.host != nil else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: baseURL.appending(path: "/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginRequest(username: username, password: password))

        let response: LoginResponse = try await decode(request, expecting: LoginResponse.self)
        guard !response.token.isEmpty else {
            throw APIError.invalidCredentials
        }

        return UserSession(serverURL: baseURL, username: username, token: response.token)
    }

    func fetchLibrary(session userSession: UserSession) async throws -> [Audiobook] {
        let targetLibraries = try await targetAudiobookLibraries(session: userSession)
        guard !targetLibraries.isEmpty else {
            return []
        }

        var booksByID: [String: Audiobook] = [:]
        for library in targetLibraries {
            let items = try await fetchAllLibraryItems(libraryID: library.id, userSession: userSession)
            for item in items where (item.mediaType ?? "book") == "book" {
                booksByID[item.id] = mapAudiobook(item, userSession: userSession)
            }
        }

        return booksByID.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func fetchBookDetails(session userSession: UserSession, itemID: String) async throws -> AudiobookDetails {
        let itemURL = userSession.serverURL
            .appending(path: "/api/items")
            .appending(path: itemID)
        let request = makeAuthedRequest(
            itemURL,
            token: userSession.token,
            queryItems: [
                URLQueryItem(name: "expanded", value: "1"),
            ]
        )

        let payload: ItemDetailsResponse = try await decode(request, expecting: ItemDetailsResponse.self)
        return mapBookDetails(payload, itemID: itemID)
    }

    func fetchPersonalizedShelves(session userSession: UserSession) async throws -> [HomeShelf] {
        let libraries: [LibrarySummary] = try await fetchLibraries(session: userSession)
        let audiobookLibrary = libraries.first(where: { $0.mediaType == "book" }) ?? libraries.first
        guard let libraryID = audiobookLibrary?.id else {
            return []
        }

        let request = makeAuthedRequest(
            userSession.serverURL.appending(path: "/api/libraries/\(libraryID)/personalized"),
            token: userSession.token
        )

        let sections: [PersonalizedShelf]
        do {
            sections = try await decode(request, expecting: [PersonalizedShelf].self)
        } catch let error as APIError where error.isAPIMismatchLike {
            struct Wrapped: Decodable {
                let results: [PersonalizedShelf]
            }
            let wrapped: Wrapped = try await decode(request, expecting: Wrapped.self)
            sections = wrapped.results
        }

        return sections.compactMap { section in
            let mapped = section.entities
                .filter { ($0.mediaType ?? "book") == "book" }
                .map { mapAudiobook($0, userSession: userSession) }
            guard !mapped.isEmpty else {
                return nil
            }
            return HomeShelf(id: section.id, title: section.label, books: mapped)
        }
    }

    func fetchSeries(session userSession: UserSession) async throws -> [HomeShelf] {
        try await fetchGroupedShelves(
            session: userSession,
            endpoint: "series"
        )
    }

    func fetchCollections(session userSession: UserSession) async throws -> [HomeShelf] {
        try await fetchGroupedShelves(
            session: userSession,
            endpoint: "collections"
        )
    }

    func search(session userSession: UserSession, query: String) async throws -> SearchResult {
        let targetLibraries = try await targetAudiobookLibraries(session: userSession)
        guard !targetLibraries.isEmpty else {
            return SearchResult(books: [], series: [])
        }

        var booksByID: [String: Audiobook] = [:]
        var seriesByID: [String: HomeShelf] = [:]

        for library in targetLibraries {
            let paged = try await searchAllPages(libraryID: library.id, query: query, userSession: userSession)

            for item in paged.books where (item.mediaType ?? "book") == "book" {
                booksByID[item.id] = mapAudiobook(item, userSession: userSession)
            }

            for entry in paged.series {
                let mappedBooks = entry.books
                    .filter { ($0.mediaType ?? "book") == "book" }
                    .map { mapAudiobook($0, userSession: userSession) }
                guard !mappedBooks.isEmpty else {
                    continue
                }

                if var existing = seriesByID[entry.series.id] {
                    var seenBookIDs = Set(existing.books.map(\.id))
                    var mergedBooks = existing.books
                    for book in mappedBooks where seenBookIDs.insert(book.id).inserted {
                        mergedBooks.append(book)
                    }
                    seriesByID[entry.series.id] = HomeShelf(
                        id: existing.id,
                        title: existing.title,
                        books: mergedBooks
                    )
                } else {
                    seriesByID[entry.series.id] = HomeShelf(
                        id: entry.series.id,
                        title: entry.series.name,
                        books: mappedBooks
                    )
                }
            }
        }

        let books = booksByID.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        let series = seriesByID.values
            .map { shelf in
                HomeShelf(
                    id: shelf.id,
                    title: shelf.title,
                    books: shelf.books.sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

        return SearchResult(books: books, series: series)
    }

    private func mapAudiobook(_ item: LibraryItem, userSession: UserSession) -> Audiobook {
        let title = item.media?.metadata?.title ?? item.media?.title ?? "Untitled"
        let author = item.media?.metadata?.authorName
            ?? item.media?.metadata?.authors?.first?.name
            ?? "Unknown Author"

        let chapters = (item.media?.chapters ?? []).enumerated().map { index, chapter in
            let id = chapter.id ?? "\(item.id)-ch-\(index)"
            let start = chapter.start ?? 0
            let end = chapter.end ?? start
            let chapterTitle = chapter.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Chapter(
                id: id,
                title: (chapterTitle?.isEmpty == false ? chapterTitle : nil) ?? "Chapter \(index + 1)",
                duration: max(end - start, 0)
            )
        }

        let progress = item.userMediaProgress?.progress
            ?? item.mediaProgress?.progress
            ?? item.progress
            ?? 0

        return Audiobook(
            id: item.id,
            title: title,
            author: author,
            progress: min(max(progress, 0), 1),
            coverURL: makeCoverURL(baseURL: userSession.serverURL, itemID: item.id, token: userSession.token),
            chapters: chapters
        )
    }

    private func mapBookDetails(_ item: ItemDetailsResponse, itemID: String) -> AudiobookDetails {
        let media = item.media
        let metadata = media?.metadata
        let chapters = (media?.chapters ?? []).enumerated().map { index, chapter in
            Chapter(
                id: chapter.id ?? "\(itemID)-ch-\(index)",
                title: chapter.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Chapter \(index + 1)",
                duration: max((chapter.end ?? 0) - (chapter.start ?? 0), 0)
            )
        }
        let tracks = (media?.tracks ?? []).enumerated().map { index, track in
            AudiobookTrack(
                id: track.ino ?? "\(itemID)-track-\(index)",
                title: track.title?.nonEmpty
                    ?? track.metadata?.filename?.nonEmpty
                    ?? "Track \(index + 1)",
                duration: track.duration
            )
        }

        return AudiobookDetails(
            subtitle: metadata?.subtitle?.nonEmpty,
            narrators: metadata?.narrators ?? [],
            publishedYear: metadata?.publishedYear?.nonEmpty,
            publisher: metadata?.publisher?.nonEmpty,
            genres: metadata?.genres ?? [],
            description: metadata?.descriptionPlain?.nonEmpty ?? metadata?.description?.nonEmpty,
            duration: media?.duration,
            sizeBytes: media?.size,
            chapters: chapters,
            tracks: tracks
        )
    }

    private func fetchAllLibraryItems(libraryID: String, userSession: UserSession) async throws -> [LibraryItem] {
        let pageSize = 200
        let maxPages = 200

        var allItems: [LibraryItem] = []
        var seenIDs: Set<String> = []

        for page in 0..<maxPages {
            let request = makeAuthedRequest(
                userSession.serverURL.appending(path: "/api/libraries/\(libraryID)/items"),
                token: userSession.token,
                queryItems: [
                    URLQueryItem(name: "minified", value: "1"),
                    URLQueryItem(name: "limit", value: "\(pageSize)"),
                    URLQueryItem(name: "page", value: "\(page)"),
                ]
            )

            let pageItems = try await fetchLibraryItems(request: request)
            if pageItems.isEmpty {
                break
            }

            let newItems = pageItems.filter { seenIDs.insert($0.id).inserted }
            allItems.append(contentsOf: newItems)

            // Stop if server starts repeating the same page or returned a partial page.
            if newItems.isEmpty || pageItems.count < pageSize {
                break
            }
        }

        return allItems
    }

    private func fetchLibraryItems(request: URLRequest) async throws -> [LibraryItem] {
        do {
            let wrapped: LibraryItemsResponse = try await decode(request, expecting: LibraryItemsResponse.self)
            return wrapped.results
        } catch let error as APIError where error.isAPIMismatchLike {
            struct Alternate: Decodable {
                let libraryItems: [LibraryItem]
            }
            do {
                let alternate: Alternate = try await decode(request, expecting: Alternate.self)
                return alternate.libraryItems
            } catch let nested as APIError where nested.isAPIMismatchLike {
                return try await decode(request, expecting: [LibraryItem].self)
            }
        }
    }

    private func fetchLibraries(session: UserSession) async throws -> [LibrarySummary] {
        let request = makeAuthedRequest(
            session.serverURL.appending(path: "/api/libraries"),
            token: session.token
        )

        do {
            return try await decode(request, expecting: [LibrarySummary].self)
        } catch let error as APIError where error.isAPIMismatchLike {
            struct Wrapped: Decodable {
                let libraries: [LibrarySummary]
            }
            let wrapped: Wrapped = try await decode(request, expecting: Wrapped.self)
            return wrapped.libraries
        }
    }

    private func fetchGroupedShelves(session userSession: UserSession, endpoint: String) async throws -> [HomeShelf] {
        let targetLibraries = try await targetAudiobookLibraries(session: userSession)
        guard !targetLibraries.isEmpty else {
            return []
        }

        var shelvesByID: [String: HomeShelf] = [:]
        for library in targetLibraries {
            let grouped = try await fetchAllGroupedShelves(
                libraryID: library.id,
                endpoint: endpoint,
                userSession: userSession
            )
            var libraryItemsByID: [String: LibraryItem]?

            for section in grouped {
                var mapped = section.books
                    .filter { ($0.mediaType ?? "book") == "book" }
                    .map { mapAudiobook($0, userSession: userSession) }

                if mapped.isEmpty, !section.bookIDs.isEmpty {
                    if libraryItemsByID == nil {
                        let items = try await fetchAllLibraryItems(libraryID: library.id, userSession: userSession)
                        libraryItemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
                    }
                    mapped = section.bookIDs
                        .compactMap { libraryItemsByID?[$0] }
                        .filter { ($0.mediaType ?? "book") == "book" }
                        .map { mapAudiobook($0, userSession: userSession) }
                }

                guard !mapped.isEmpty else {
                    continue
                }

                if var existing = shelvesByID[section.id] {
                    var seenBookIDs = Set(existing.books.map(\.id))
                    var mergedBooks = existing.books
                    for book in mapped where seenBookIDs.insert(book.id).inserted {
                        mergedBooks.append(book)
                    }
                    shelvesByID[section.id] = HomeShelf(
                        id: existing.id,
                        title: existing.title,
                        books: mergedBooks
                    )
                } else {
                    shelvesByID[section.id] = HomeShelf(id: section.id, title: section.name, books: mapped)
                }
            }
        }

        return shelvesByID.values
            .map { shelf in
                HomeShelf(
                    id: shelf.id,
                    title: shelf.title,
                    books: shelf.books.sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private func targetAudiobookLibraries(session userSession: UserSession) async throws -> [LibrarySummary] {
        let libraries: [LibrarySummary] = try await fetchLibraries(session: userSession)
        let audiobookLibraries = libraries.filter { $0.mediaType == "book" }
        return audiobookLibraries.isEmpty ? libraries : audiobookLibraries
    }

    private func fetchAllGroupedShelves(libraryID: String, endpoint: String, userSession: UserSession) async throws -> [GroupedShelf] {
        let pageSize = 100
        let maxPages = 200

        var allShelves: [GroupedShelf] = []
        var seenEntries: Set<String> = []

        for page in 0..<maxPages {
            let request = makeAuthedRequest(
                userSession.serverURL.appending(path: "/api/libraries/\(libraryID)/\(endpoint)"),
                token: userSession.token,
                queryItems: [
                    URLQueryItem(name: "limit", value: "\(pageSize)"),
                    URLQueryItem(name: "page", value: "\(page)"),
                ]
            )

            let wrapped: GroupedShelfResponse = try await decode(request, expecting: GroupedShelfResponse.self)
            let pageShelves = wrapped.results
            if pageShelves.isEmpty {
                break
            }

            let newShelves = pageShelves.filter { seenEntries.insert(groupedShelfEntryKey($0)).inserted }
            allShelves.append(contentsOf: newShelves)
            if newShelves.isEmpty || pageShelves.count < pageSize {
                break
            }
        }

        return allShelves
    }

    private func searchAllPages(libraryID: String, query: String, userSession: UserSession) async throws -> SearchPages {
        let pageSize = 50
        let maxPages = 100

        var allBooks: [LibraryItem] = []
        var allSeries: [SearchSeriesItem] = []
        var seenBookIDs: Set<String> = []
        var seenSeriesEntries: Set<String> = []

        for page in 0..<maxPages {
            let request = makeAuthedRequest(
                userSession.serverURL.appending(path: "/api/libraries/\(libraryID)/search"),
                token: userSession.token,
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: "\(pageSize)"),
                    URLQueryItem(name: "page", value: "\(page)"),
                ]
            )

            let response: LibrarySearchResponse = try await decode(request, expecting: LibrarySearchResponse.self)
            let pageBooks = response.book.compactMap(\.libraryItem)
            let pageSeries = response.series
            if pageBooks.isEmpty, pageSeries.isEmpty {
                break
            }

            let newBooks = pageBooks.filter { seenBookIDs.insert($0.id).inserted }
            let newSeries = pageSeries.filter { seenSeriesEntries.insert(searchSeriesEntryKey($0)).inserted }

            allBooks.append(contentsOf: newBooks)
            allSeries.append(contentsOf: newSeries)

            let pageTotalCount = pageBooks.count + pageSeries.count
            let newTotalCount = newBooks.count + newSeries.count
            if newTotalCount == 0 || pageTotalCount < pageSize {
                break
            }
        }

        return SearchPages(books: allBooks, series: allSeries)
    }

    private func groupedShelfEntryKey(_ shelf: GroupedShelf) -> String {
        let bookIDs = shelf.books.map(\.id).sorted().joined(separator: ",")
        return "\(shelf.id)|\(bookIDs)"
    }

    private func searchSeriesEntryKey(_ series: SearchSeriesItem) -> String {
        let bookIDs = series.books.map(\.id).sorted().joined(separator: ",")
        return "\(series.series.id)|\(bookIDs)"
    }

    private func makeCoverURL(baseURL: URL, itemID: String, token: String) -> URL? {
        var components = URLComponents(url: baseURL.appending(path: "/api/items/\(itemID)/cover"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    private func makeAuthedRequest(_ url: URL, token: String, queryItems: [URLQueryItem] = []) -> URLRequest {
        var finalURL = url
        let allQueryItems = queryItems + [URLQueryItem(name: "token", value: token)]
        if !allQueryItems.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = allQueryItems
            finalURL = components?.url ?? url
        }
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func decode<T: Decodable>(_ request: URLRequest, expecting _: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .notConnectedToInternet || urlError.code == .cannotFindHost || urlError.code == .timedOut {
                throw APIError.networkUnreachable
            }
            throw APIError.serverAPIMismatch
        } catch {
            throw APIError.serverAPIMismatch
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverAPIMismatch
        }

        switch http.statusCode {
        case 200 ..< 300:
            break
        case 401, 403:
            throw APIError.invalidCredentials
        case 404, 405:
            throw APIError.serverAPIMismatch
        default:
            throw APIError.serverAPIMismatch
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            throw APIError.decodingFailed(String(describing: decodingError))
        } catch {
            throw APIError.serverAPIMismatch
        }
    }
}

private struct SearchPages {
    let books: [LibraryItem]
    let series: [SearchSeriesItem]
}

struct MockAudiobookshelfAPI: AudiobookshelfAPI {
    func login(serverURL: String, username: String, password: String) async throws -> UserSession {
        let normalized = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalized), let host = url.host else {
            throw APIError.invalidURL
        }

        if host.contains("offline") || username == "offline" {
            throw APIError.networkUnreachable
        }

        if host.contains("badapi") {
            throw APIError.serverAPIMismatch
        }

        guard username == "reader", password == "password" else {
            throw APIError.invalidCredentials
        }

        return UserSession(serverURL: url, username: username, token: "mock-token")
    }

    func fetchLibrary(session: UserSession) async throws -> [Audiobook] {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        return Audiobook.mockLibrary
    }

    func fetchBookDetails(session: UserSession, itemID: String) async throws -> AudiobookDetails {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        return AudiobookDetails(
            subtitle: "Expeditionary Force, Book 1",
            narrators: ["R.C. Bray"],
            publishedYear: "2016",
            publisher: "Podium Audio",
            genres: ["Audiobook"],
            description: "The merry band of pirates starts here.",
            duration: Audiobook.mockLibrary.first?.chapters.reduce(0) { $0 + $1.duration },
            sizeBytes: 1_110_000_000,
            chapters: Audiobook.mockLibrary.first?.chapters ?? [],
            tracks: [
                AudiobookTrack(id: "track-1", title: "Columbus Day.m4b", duration: 3600),
            ]
        )
    }

    func fetchPersonalizedShelves(session: UserSession) async throws -> [HomeShelf] {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        return [
            HomeShelf(id: "recent", title: "Recently Added", books: Array(Audiobook.mockLibrary.prefix(1))),
            HomeShelf(id: "discover", title: "Discover", books: Audiobook.mockLibrary),
        ]
    }

    func fetchSeries(session: UserSession) async throws -> [HomeShelf] {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        return [
            HomeShelf(id: "series-1", title: "Expeditionary Force", books: Audiobook.mockLibrary),
        ]
    }

    func fetchCollections(session: UserSession) async throws -> [HomeShelf] {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        return [
            HomeShelf(id: "collection-1", title: "Sci-Fi Favorites", books: Audiobook.mockLibrary),
        ]
    }

    func search(session: UserSession, query: String) async throws -> SearchResult {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        let filtered = Audiobook.mockLibrary.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query)
        }
        return SearchResult(
            books: filtered,
            series: [HomeShelf(id: "series-1", title: "Expeditionary Force", books: filtered)]
        )
    }
}

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case networkUnreachable
    case invalidCredentials
    case serverAPIMismatch
    case decodingFailed(String)
    case unauthorized

    var isAPIMismatchLike: Bool {
        switch self {
        case .serverAPIMismatch, .decodingFailed:
            return true
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL."
        case .networkUnreachable:
            return "Network unreachable."
        case .invalidCredentials:
            return "Invalid credentials."
        case .serverAPIMismatch:
            return "Server/API mismatch."
        case .decodingFailed:
            return "Server/API mismatch."
        case .unauthorized:
            return "Unauthorized session."
        }
    }
}

private struct LoginRequest: Encodable {
    let username: String
    let password: String
}

private struct LoginResponse: Decodable {
    let token: String

    private struct UserPayload: Decodable {
        let token: String?
        let accessToken: String?
    }

    private enum CodingKeys: String, CodingKey {
        case token
        case user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let topLevelToken = try container.decodeIfPresent(String.self, forKey: .token), !topLevelToken.isEmpty {
            token = topLevelToken
            return
        }

        if let user = try container.decodeIfPresent(UserPayload.self, forKey: .user) {
            if let nested = user.token, !nested.isEmpty {
                token = nested
                return
            }
            if let access = user.accessToken, !access.isEmpty {
                token = access
                return
            }
        }

        token = ""
    }
}

private struct LibrarySummary: Decodable {
    let id: String
    let mediaType: String?
}

private struct LibraryItemsResponse: Decodable {
    let results: [LibraryItem]
}

private struct LibraryItem: Decodable {
    let id: String
    let mediaType: String?
    let progress: Double?
    let mediaProgress: ProgressPayload?
    let userMediaProgress: ProgressPayload?
    let media: LibraryItemMedia?
}

private struct ProgressPayload: Decodable {
    let progress: Double?
}

private struct LibraryItemMedia: Decodable {
    let title: String?
    let metadata: LibraryItemMetadata?
    let chapters: [LibraryItemChapter]?
}

private struct LibraryItemMetadata: Decodable {
    let title: String?
    let authorName: String?
    let authors: [LibraryItemAuthor]?
}

private struct LibraryItemAuthor: Decodable {
    let name: String?
}

private struct LibraryItemChapter: Decodable {
    let id: String?
    let title: String?
    let start: TimeInterval?
    let end: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case start
        case end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringID = try? container.decodeIfPresent(String.self, forKey: .id) {
            id = stringID
        } else if let intID = try? container.decodeIfPresent(Int.self, forKey: .id) {
            id = String(intID)
        } else if let doubleID = try? container.decodeIfPresent(Double.self, forKey: .id) {
            id = String(Int(doubleID))
        } else {
            id = nil
        }

        title = try container.decodeIfPresent(String.self, forKey: .title)
        start = try container.decodeIfPresent(TimeInterval.self, forKey: .start)
        end = try container.decodeIfPresent(TimeInterval.self, forKey: .end)
    }
}

private struct ItemDetailsResponse: Decodable {
    let media: ItemDetailsMedia?
}

private struct ItemDetailsMedia: Decodable {
    let metadata: ItemDetailsMetadata?
    let duration: TimeInterval?
    let size: Int64?
    let chapters: [LibraryItemChapter]?
    let tracks: [ItemDetailsTrack]?
}

private struct ItemDetailsMetadata: Decodable {
    let subtitle: String?
    let narrators: [String]?
    let genres: [String]?
    let publishedYear: String?
    let publisher: String?
    let description: String?
    let descriptionPlain: String?

    private enum CodingKeys: String, CodingKey {
        case subtitle
        case narrators
        case genres
        case publishedYear
        case publisher
        case description
        case descriptionPlain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        narrators = try container.decodeIfPresent([String].self, forKey: .narrators)
        genres = try container.decodeIfPresent([String].self, forKey: .genres)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        descriptionPlain = try container.decodeIfPresent(String.self, forKey: .descriptionPlain)

        if let yearString = try container.decodeIfPresent(String.self, forKey: .publishedYear) {
            publishedYear = yearString
        } else if let yearInt = try container.decodeIfPresent(Int.self, forKey: .publishedYear) {
            publishedYear = String(yearInt)
        } else {
            publishedYear = nil
        }
    }
}

private struct ItemDetailsTrack: Decodable {
    let ino: String?
    let title: String?
    let duration: TimeInterval?
    let metadata: ItemDetailsTrackMetadata?
}

private struct ItemDetailsTrackMetadata: Decodable {
    let filename: String?
}

private struct PersonalizedShelf: Decodable {
    let id: String
    let label: String
    let entities: [LibraryItem]
}

private struct GroupedShelfResponse: Decodable {
    let results: [GroupedShelf]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let direct = try? container.decode([GroupedShelf].self)
        {
            results = direct
            return
        }

        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        results = try keyed.decodeIfPresent([GroupedShelf].self, forKey: .results) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case results
    }
}

private struct GroupedShelf: Decodable {
    let id: String
    let name: String
    let books: [LibraryItem]
    let bookIDs: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .label)
            ?? "Untitled"

        if let directBooks = try? container.decodeIfPresent([LibraryItem].self, forKey: .books) {
            books = directBooks
            bookIDs = directBooks.map(\.id)
            return
        }
        if let directItems = try? container.decodeIfPresent([LibraryItem].self, forKey: .libraryItems) {
            books = directItems
            bookIDs = directItems.map(\.id)
            return
        }
        if let wrappedBooks = try? container.decodeIfPresent([LibraryItemWrapper].self, forKey: .books) {
            books = wrappedBooks.compactMap(\.libraryItem)
            bookIDs = books.map(\.id)
            return
        }
        if let wrappedItems = try? container.decodeIfPresent([LibraryItemWrapper].self, forKey: .libraryItems) {
            books = wrappedItems.compactMap(\.libraryItem)
            bookIDs = books.map(\.id)
            return
        }
        if let idBooks = try? container.decodeIfPresent([String].self, forKey: .books) {
            books = []
            bookIDs = idBooks
            return
        }
        if let idItems = try? container.decodeIfPresent([String].self, forKey: .libraryItems) {
            books = []
            bookIDs = idItems
            return
        }
        books = []
        bookIDs = []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case label
        case books
        case libraryItems
    }
}

private struct LibraryItemWrapper: Decodable {
    let libraryItem: LibraryItem?
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SearchResult {
    let books: [Audiobook]
    let series: [HomeShelf]
}

private struct LibrarySearchResponse: Decodable {
    let book: [SearchBookItem]
    let series: [SearchSeriesItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        book = try container.decodeIfPresent([SearchBookItem].self, forKey: .book) ?? []
        series = try container.decodeIfPresent([SearchSeriesItem].self, forKey: .series) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case book
        case series
    }
}

private struct SearchBookItem: Decodable {
    let libraryItem: LibraryItem?
}

private struct SearchSeriesItem: Decodable {
    let series: SearchSeries
    let books: [LibraryItem]
}

private struct SearchSeries: Decodable {
    let id: String
    let name: String
}
