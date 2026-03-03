import Foundation

protocol AudiobookshelfAPI {
    func login(serverURL: String, username: String, password: String) async throws -> UserSession
    func fetchLibrary(session: UserSession) async throws -> [Audiobook]
    func fetchBookDetails(session: UserSession, itemID: String) async throws -> AudiobookDetails
    func fetchPersonalizedShelves(session: UserSession) async throws -> [HomeShelf]
    func fetchSeries(session: UserSession) async throws -> [HomeShelf]
    func fetchCollections(session: UserSession) async throws -> [HomeShelf]
    func search(session: UserSession, query: String) async throws -> SearchResult
    func fetchMyListeningStats(session: UserSession, days: Int?) async throws -> UserListeningStats
    func fetchPrimaryLibraryStats(session: UserSession) async throws -> LibraryStatsSnapshot?
    func fetchLibraryStats(session: UserSession, libraryID: String) async throws -> LibraryStatsSnapshot
    func fetchMediaProgress(session: UserSession, itemID: String) async throws -> PlaybackProgress?
    func updateMediaProgress(
        session: UserSession,
        itemID: String,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isFinished: Bool
    ) async throws -> PlaybackProgress
    func createBookmark(
        session: UserSession,
        itemID: String,
        time: TimeInterval,
        title: String
    ) async throws -> AudioBookmark
    func removeBookmark(session: UserSession, itemID: String, time: TimeInterval) async throws
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
        return mapBookDetails(payload, itemID: itemID, userSession: userSession)
    }

    func fetchMediaProgress(session userSession: UserSession, itemID: String) async throws -> PlaybackProgress? {
        let request = makeAuthedRequest(
            userSession.serverURL
                .appending(path: "/api/me/progress")
                .appending(path: itemID),
            token: userSession.token
        )

        do {
            let response: MediaProgressResponse = try await decode(request, expecting: MediaProgressResponse.self)
            return mapPlaybackProgress(
                itemID: itemID,
                payload: response,
                durationHint: response.duration ?? 0
            )
        } catch APIError.serverAPIMismatch {
            return nil
        } catch APIError.decodingFailed {
            return nil
        }
    }

    func updateMediaProgress(
        session userSession: UserSession,
        itemID: String,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isFinished: Bool
    ) async throws -> PlaybackProgress {
        let url = userSession.serverURL
            .appending(path: "/api/me/progress")
            .appending(path: itemID)
        let body = ProgressUpdateRequest(
            duration: duration,
            progress: duration > 0 ? min(max(currentTime / duration, 0), 1) : nil,
            currentTime: currentTime,
            isFinished: isFinished,
            finishedAt: isFinished ? Date().millisecondsSinceEpoch : nil
        )
        let request = try makeAuthedJSONRequest(
            url,
            token: userSession.token,
            method: "PATCH",
            body: body
        )
        let responseData = try await requestData(request)
        if let response = parseMediaProgressResponse(responseData) {
            return mapPlaybackProgress(itemID: itemID, payload: response, durationHint: duration)
        }

        // Some server versions respond with empty body or non-progress envelope for successful updates.
        return PlaybackProgress(
            audiobookID: itemID,
            chapterID: nil,
            positionSeconds: currentTime,
            durationSeconds: duration,
            isFinished: isFinished,
            updatedAt: Date(),
            lastServerSyncAt: Date()
        )
    }

    func createBookmark(
        session userSession: UserSession,
        itemID: String,
        time: TimeInterval,
        title: String
    ) async throws -> AudioBookmark {
        let url = userSession.serverURL
            .appending(path: "/api/me/item")
            .appending(path: itemID)
            .appending(path: "bookmark")
        let request = try makeAuthedJSONRequest(
            url,
            token: userSession.token,
            method: "POST",
            body: BookmarkRequest(time: time, title: title)
        )
        let response: BookmarkResponse = try await decode(request, expecting: BookmarkResponse.self)
        return mapBookmark(itemID: itemID, bookmark: response)
    }

    func removeBookmark(session userSession: UserSession, itemID: String, time: TimeInterval) async throws {
        let encodedTime = String(Int(time.rounded(.towardZero)))
        let request = makeAuthedRequest(
            userSession.serverURL
                .appending(path: "/api/me/item")
                .appending(path: itemID)
                .appending(path: "bookmark")
                .appending(path: encodedTime),
            token: userSession.token,
            method: "DELETE"
        )
        _ = try await requestData(request)
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

    func fetchMyListeningStats(session userSession: UserSession, days: Int?) async throws -> UserListeningStats {
        var queryItems: [URLQueryItem] = []
        if let days, days > 0 {
            queryItems.append(URLQueryItem(name: "days", value: String(days)))
        }
        let request = makeAuthedRequest(
            userSession.serverURL.appending(path: "/api/me/listening-stats"),
            token: userSession.token,
            queryItems: queryItems
        )

        let payload: ListeningStatsResponse = try await decode(request, expecting: ListeningStatsResponse.self)
        return mapListeningStats(payload)
    }

    func fetchPrimaryLibraryStats(session userSession: UserSession) async throws -> LibraryStatsSnapshot? {
        let libraries = try await targetAudiobookLibraries(session: userSession)
        guard let primaryLibrary = libraries.first else {
            return nil
        }
        return try await fetchLibraryStats(
            session: userSession,
            libraryID: primaryLibrary.id,
            libraryName: primaryLibrary.name ?? "Library"
        )
    }

    func fetchLibraryStats(session userSession: UserSession, libraryID: String) async throws -> LibraryStatsSnapshot {
        try await fetchLibraryStats(
            session: userSession,
            libraryID: libraryID,
            libraryName: "Library"
        )
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

    private func mapBookDetails(_ item: ItemDetailsResponse, itemID: String, userSession: UserSession) -> AudiobookDetails {
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
                startOffset: max(track.startOffset ?? 0, 0),
                duration: track.duration,
                streamURL: makeTrackURL(
                    baseURL: userSession.serverURL,
                    contentURL: track.contentURL,
                    token: userSession.token
                )
            )
        }

        let progressPayload = item.userMediaProgress ?? item.mediaProgress
        let mappedProgress = progressPayload.flatMap {
            mapPlaybackProgress(itemID: itemID, payload: $0, durationHint: media?.duration ?? 0)
        }
        let mappedBookmarks = (item.bookmarks ?? []).map { mapBookmark(itemID: itemID, bookmark: $0) }

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
            tracks: tracks,
            userProgress: mappedProgress,
            bookmarks: mappedBookmarks
        )
    }

    private func mapPlaybackProgress(
        itemID: String,
        payload: MediaProgressPayload,
        durationHint: TimeInterval
    ) -> PlaybackProgress {
        let duration = max(payload.duration ?? durationHint, 0)
        let currentTime = max(payload.currentTime ?? 0, 0)
        let updatedAt = payload.lastUpdate.flatMap { Date(millisecondsSinceEpoch: $0) } ?? Date()
        let finished = payload.isFinished
            ?? ((payload.progress ?? 0) >= 1
                || (duration > 0 && currentTime >= duration))

        return PlaybackProgress(
            audiobookID: itemID,
            chapterID: nil,
            positionSeconds: duration > 0 ? min(currentTime, duration) : currentTime,
            durationSeconds: duration,
            isFinished: finished,
            updatedAt: updatedAt,
            lastServerSyncAt: Date()
        )
    }

    private func mapBookmark(itemID: String, bookmark: BookmarkPayload) -> AudioBookmark {
        AudioBookmark(
            audiobookID: itemID,
            title: bookmark.title?.nonEmpty ?? "Bookmark",
            time: max(bookmark.time ?? 0, 0),
            createdAt: bookmark.createdAt.flatMap { Date(millisecondsSinceEpoch: $0) }
        )
    }

    private func mapListeningStats(_ payload: ListeningStatsResponse) -> UserListeningStats {
        let heatmap = payload.dayOfWeek.mapValues { max($0, 0) }

        let dailyTotals = payload.days.reduce(into: [DailyListeningPoint]()) { result, entry in
            guard let date = Date.fromDayKey(entry.key) else {
                return
            }
            result.append(DailyListeningPoint(date: date, seconds: max(entry.value, 0)))
        }
        .sorted { lhs, rhs in
            lhs.date > rhs.date
        }

        let topItems = payload.items.map { key, value in
            ListeningItemStat(
                itemID: value.itemID ?? key,
                title: value.title?.nonEmpty ?? "Unknown Item",
                author: value.author?.nonEmpty,
                seconds: max(value.timeListening, 0),
                percentOfTotal: nil
            )
        }
        .sorted { $0.seconds > $1.seconds }
        .map { item in
            var mutable = item
            if payload.totalTime > 0 {
                mutable.percentOfTotal = min(max(item.seconds / payload.totalTime, 0), 1)
            }
            return mutable
        }

        let recentSessions = payload.recentSessions
            .map { session in
                let id = session.id?.nonEmpty
                    ?? "\(session.itemID ?? "unknown")-\(session.startedAt ?? 0)-\(session.updatedAt ?? 0)"
                return ListeningSession(
                    id: id,
                    itemID: session.itemID,
                    itemTitle: session.title?.nonEmpty,
                    itemAuthor: session.author?.nonEmpty,
                    seconds: max(session.timeListening, 0),
                    startTime: session.startTime,
                    currentTime: session.currentTime,
                    startedAt: session.startedAt.map { Date(millisecondsSinceEpoch: $0) },
                    updatedAt: session.updatedAt.map { Date(millisecondsSinceEpoch: $0) }
                )
            }
            .sorted {
                ($0.updatedAt ?? $0.startedAt ?? .distantPast) > ($1.updatedAt ?? $1.startedAt ?? .distantPast)
            }

        return UserListeningStats(
            totalTimeSeconds: max(payload.totalTime, 0),
            todayTimeSeconds: max(payload.today, 0),
            dayOfWeekHeatmap: heatmap,
            dailyTotals: dailyTotals,
            topItems: topItems,
            recentSessions: recentSessions
        )
    }

    private func fetchLibraryStats(
        session userSession: UserSession,
        libraryID: String,
        libraryName: String
    ) async throws -> LibraryStatsSnapshot {
        let request = makeAuthedRequest(
            userSession.serverURL.appending(path: "/api/libraries/\(libraryID)/stats"),
            token: userSession.token
        )

        let payload: LibraryStatsResponse = try await decode(request, expecting: LibraryStatsResponse.self)

        return LibraryStatsSnapshot(
            libraryID: libraryID,
            libraryName: libraryName,
            totalItems: max(payload.totalItems, 0),
            totalDurationSeconds: max(payload.totalDuration, 0),
            totalSizeBytes: max(payload.totalSize, 0),
            totalAuthors: max(payload.totalAuthors, 0),
            totalGenres: max(payload.totalGenres, 0),
            numAudioTracks: max(payload.numAudioTracks, 0),
            largestItems: payload.largestItems.map {
                LibraryItemStat(
                    itemID: $0.id,
                    title: $0.title.nonEmpty ?? "Unknown Item",
                    sizeBytes: $0.size.map { max($0, 0) },
                    durationSeconds: $0.duration.map { max($0, 0) }
                )
            },
            longestItems: payload.longestItems.map {
                LibraryItemStat(
                    itemID: $0.id,
                    title: $0.title.nonEmpty ?? "Unknown Item",
                    sizeBytes: $0.size.map { max($0, 0) },
                    durationSeconds: $0.duration.map { max($0, 0) }
                )
            },
            authorsWithCount: payload.authorsWithCount.map {
                NamedCountStat(
                    id: $0.id ?? $0.name,
                    name: $0.name,
                    count: max($0.count, 0)
                )
            },
            genresWithCount: payload.genresWithCount.map {
                NamedCountStat(
                    id: $0.id ?? $0.genre,
                    name: $0.genre,
                    count: max($0.count, 0)
                )
            }
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

    private func makeTrackURL(baseURL: URL, contentURL: String?, token: String) -> URL? {
        guard let contentURL, !contentURL.isEmpty else {
            return nil
        }

        let rawURL: URL?
        if contentURL.hasPrefix("http://") || contentURL.hasPrefix("https://") {
            rawURL = URL(string: contentURL)
        } else {
            rawURL = URL(string: contentURL, relativeTo: baseURL)?.absoluteURL
        }
        guard let rawURL else {
            return nil
        }

        var components = URLComponents(url: rawURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "token" }) {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        components?.queryItems = queryItems
        return components?.url ?? rawURL
    }

    private func makeAuthedRequest(
        _ url: URL,
        token: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) -> URLRequest {
        var finalURL = url
        let allQueryItems = queryItems + [URLQueryItem(name: "token", value: token)]
        if !allQueryItems.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = allQueryItems
            finalURL = components?.url ?? url
        }
        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func makeAuthedJSONRequest<T: Encodable>(
        _ url: URL,
        token: String,
        method: String,
        body: T
    ) throws -> URLRequest {
        var request = makeAuthedRequest(url, token: token, method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func decode<T: Decodable>(_ request: URLRequest, expecting _: T.Type) async throws -> T {
        let data = try await requestData(request)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            throw APIError.decodingFailed(String(describing: decodingError))
        } catch {
            throw APIError.serverAPIMismatch
        }
    }

    private func parseMediaProgressResponse(_ data: Data) -> MediaProgressPayload? {
        guard !data.isEmpty else {
            return nil
        }

        if let direct = try? JSONDecoder().decode(MediaProgressPayload.self, from: data) {
            return direct
        }

        if let wrapped = try? JSONDecoder().decode(MediaProgressEnvelope.self, from: data) {
            return wrapped.mediaProgress
                ?? wrapped.progress
                ?? wrapped.result
        }

        return nil
    }

    private func requestData(_ request: URLRequest) async throws -> Data {
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
            return data
        case 401, 403:
            throw APIError.invalidCredentials
        case 404, 405:
            throw APIError.serverAPIMismatch
        default:
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
                AudiobookTrack(
                    id: "track-1",
                    title: "Columbus Day.m4b",
                    startOffset: 0,
                    duration: 3600,
                    streamURL: URL(string: "https://example.com/audio/mock.m4b")
                ),
            ],
            userProgress: PlaybackProgress(
                audiobookID: itemID,
                chapterID: nil,
                positionSeconds: 120,
                durationSeconds: 3600,
                isFinished: false,
                updatedAt: Date(),
                lastServerSyncAt: Date()
            ),
            bookmarks: []
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

    func fetchMyListeningStats(session: UserSession, days _: Int?) async throws -> UserListeningStats {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        return UserListeningStats(
            totalTimeSeconds: 24_000,
            todayTimeSeconds: 1_200,
            dayOfWeekHeatmap: [1: 3_600, 2: 4_200, 3: 2_400],
            dailyTotals: [
                DailyListeningPoint(date: Date(timeIntervalSince1970: 1_772_000_000), seconds: 1_200),
                DailyListeningPoint(date: Date(timeIntervalSince1970: 1_771_913_600), seconds: 3_600),
            ],
            topItems: [
                ListeningItemStat(
                    itemID: "book-columbus-day",
                    title: "Columbus Day",
                    author: "Craig Alanson",
                    seconds: 9_000,
                    percentOfTotal: 0.375
                ),
            ],
            recentSessions: [
                ListeningSession(
                    id: "session-1",
                    itemID: "book-columbus-day",
                    itemTitle: "Columbus Day",
                    itemAuthor: "Craig Alanson",
                    seconds: 1_200,
                    startTime: 120,
                    currentTime: 1_320,
                    startedAt: Date(timeIntervalSince1970: 1_772_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_772_001_200)
                ),
            ]
        )
    }

    func fetchPrimaryLibraryStats(session: UserSession) async throws -> LibraryStatsSnapshot? {
        try await fetchLibraryStats(session: session, libraryID: "library-1")
    }

    func fetchLibraryStats(session: UserSession, libraryID: String) async throws -> LibraryStatsSnapshot {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        return LibraryStatsSnapshot(
            libraryID: libraryID,
            libraryName: "Audiobooks",
            totalItems: 444,
            totalDurationSeconds: 22_055_931,
            totalSizeBytes: 214_133_179_595,
            totalAuthors: 119,
            totalGenres: 53,
            numAudioTracks: 13_576,
            largestItems: [
                LibraryItemStat(
                    itemID: "book-columbus-day",
                    title: "Columbus Day",
                    sizeBytes: 1_110_000_000,
                    durationSeconds: nil
                ),
            ],
            longestItems: [
                LibraryItemStat(
                    itemID: "book-columbus-day",
                    title: "Columbus Day",
                    sizeBytes: nil,
                    durationSeconds: 57_600
                ),
            ],
            authorsWithCount: [
                NamedCountStat(id: "author-1", name: "Craig Alanson", count: 2),
            ],
            genresWithCount: [
                NamedCountStat(id: "genre-1", name: "Audiobook", count: 10),
            ]
        )
    }

    func fetchMediaProgress(session: UserSession, itemID: String) async throws -> PlaybackProgress? {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        return PlaybackProgress(
            audiobookID: itemID,
            chapterID: nil,
            positionSeconds: 0,
            durationSeconds: 0,
            isFinished: false,
            updatedAt: Date(),
            lastServerSyncAt: Date()
        )
    }

    func updateMediaProgress(
        session: UserSession,
        itemID: String,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isFinished: Bool
    ) async throws -> PlaybackProgress {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        return PlaybackProgress(
            audiobookID: itemID,
            chapterID: nil,
            positionSeconds: currentTime,
            durationSeconds: duration,
            isFinished: isFinished,
            updatedAt: Date(),
            lastServerSyncAt: Date()
        )
    }

    func createBookmark(
        session: UserSession,
        itemID: String,
        time: TimeInterval,
        title: String
    ) async throws -> AudioBookmark {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        return AudioBookmark(
            audiobookID: itemID,
            title: title,
            time: time,
            createdAt: Date()
        )
    }

    func removeBookmark(session: UserSession, itemID: String, time: TimeInterval) async throws {
        guard !session.token.isEmpty else {
            throw APIError.unauthorized
        }
        _ = (itemID, time)
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
    let name: String?
    let mediaType: String?
}

private struct LibraryItemsResponse: Decodable {
    let results: [LibraryItem]
}

private struct LibraryItem: Decodable {
    let id: String
    let mediaType: String?
    let progress: Double?
    let mediaProgress: MediaProgressPayload?
    let userMediaProgress: MediaProgressPayload?
    let media: LibraryItemMedia?
}

private struct ListeningStatsResponse: Decodable {
    let totalTime: TimeInterval
    let today: TimeInterval
    let dayOfWeek: [Int: TimeInterval]
    let days: [String: TimeInterval]
    let items: [String: ListeningStatsItemPayload]
    let recentSessions: [ListeningSessionPayload]

    private enum CodingKeys: String, CodingKey {
        case totalTime
        case today
        case dayOfWeek
        case days
        case items
        case recentSessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalTime = container.decodeLossyTimeInterval(forKey: .totalTime) ?? 0
        today = container.decodeLossyTimeInterval(forKey: .today) ?? 0
        dayOfWeek = container.decodeLossyDayOfWeekMap(forKey: .dayOfWeek)
        days = container.decodeLossyTimeIntervalMap(forKey: .days)
        items = container.decodeLossyDictionary(forKey: .items)
        recentSessions = container.decodeLossyArray(forKey: .recentSessions)
    }
}

private struct ListeningStatsItemPayload: Decodable {
    let itemID: String?
    let timeListening: TimeInterval
    let title: String?
    let author: String?

    private enum CodingKeys: String, CodingKey {
        case itemID = "id"
        case timeListening
        case mediaMetadata
        case title
        case author
        case authorName
    }

    private struct MediaMetadata: Decodable {
        let title: String?
        let author: String?
        let authorName: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try container.decodeIfPresent(String.self, forKey: .itemID)
        timeListening = container.decodeLossyTimeInterval(forKey: .timeListening) ?? 0

        let metadata = try container.decodeIfPresent(MediaMetadata.self, forKey: .mediaMetadata)
        let fallbackTitle = try container.decodeIfPresent(String.self, forKey: .title)
        title = metadata?.title ?? fallbackTitle

        if let authorFromMetadata = metadata?.author ?? metadata?.authorName {
            author = authorFromMetadata
        } else {
            let authorValue = try container.decodeIfPresent(String.self, forKey: .author)
            let authorNameValue = try container.decodeIfPresent(String.self, forKey: .authorName)
            author = authorValue ?? authorNameValue
        }
    }
}

private struct ListeningSessionPayload: Decodable {
    let id: String?
    let itemID: String?
    let title: String?
    let author: String?
    let timeListening: TimeInterval
    let startTime: TimeInterval?
    let currentTime: TimeInterval?
    let startedAt: Int64?
    let updatedAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case id
        case itemID = "libraryItemId"
        case itemIDAlternate = "itemId"
        case mediaMetadata
        case title
        case author
        case authorName
        case displayTitle
        case displayAuthor
        case timeListening
        case startTime
        case currentTime
        case startedAt
        case updatedAt
    }

    private struct SessionMetadata: Decodable {
        let title: String?
        let author: String?
        let authorName: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        itemID = try container.decodeIfPresent(String.self, forKey: .itemID)
            ?? container.decodeIfPresent(String.self, forKey: .itemIDAlternate)

        let metadata = try container.decodeIfPresent(SessionMetadata.self, forKey: .mediaMetadata)
        let displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        let titleValue = try container.decodeIfPresent(String.self, forKey: .title)
        let displayAuthor = try container.decodeIfPresent(String.self, forKey: .displayAuthor)
        let authorValue = try container.decodeIfPresent(String.self, forKey: .author)
        let authorNameValue = try container.decodeIfPresent(String.self, forKey: .authorName)

        title = metadata?.title ?? displayTitle ?? titleValue
        author = metadata?.author
            ?? metadata?.authorName
            ?? displayAuthor
            ?? authorValue
            ?? authorNameValue

        timeListening = container.decodeLossyTimeInterval(forKey: .timeListening) ?? 0
        startTime = container.decodeLossyTimeInterval(forKey: .startTime)
        currentTime = container.decodeLossyTimeInterval(forKey: .currentTime)
        startedAt = container.decodeLossyInt64(forKey: .startedAt)
        updatedAt = container.decodeLossyInt64(forKey: .updatedAt)
    }
}

private struct LibraryStatsResponse: Decodable {
    let totalItems: Int
    let totalDuration: TimeInterval
    let totalSize: Int64
    let totalAuthors: Int
    let totalGenres: Int
    let numAudioTracks: Int
    let longestItems: [LibraryStatsItemPayload]
    let largestItems: [LibraryStatsItemPayload]
    let authorsWithCount: [LibraryNamedCountPayload]
    let genresWithCount: [LibraryGenreCountPayload]

    private enum CodingKeys: String, CodingKey {
        case totalItems
        case totalDuration
        case totalSize
        case totalAuthors
        case totalGenres
        case numAudioTracks
        case numAudioTrack
        case longestItems
        case largestItems
        case authorsWithCount
        case genresWithCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalItems = container.decodeLossyInt(forKey: .totalItems) ?? 0
        totalDuration = container.decodeLossyTimeInterval(forKey: .totalDuration) ?? 0
        totalSize = container.decodeLossyInt64(forKey: .totalSize) ?? 0
        totalAuthors = container.decodeLossyInt(forKey: .totalAuthors) ?? 0
        totalGenres = container.decodeLossyInt(forKey: .totalGenres) ?? 0
        numAudioTracks = container.decodeLossyInt(forKey: .numAudioTracks)
            ?? container.decodeLossyInt(forKey: .numAudioTrack)
            ?? 0
        longestItems = container.decodeLossyArray(forKey: .longestItems)
        largestItems = container.decodeLossyArray(forKey: .largestItems)
        authorsWithCount = container.decodeLossyArray(forKey: .authorsWithCount)
        genresWithCount = container.decodeLossyArray(forKey: .genresWithCount)
    }
}

private struct LibraryStatsItemPayload: Decodable {
    let id: String
    let title: String
    let size: Int64?
    let duration: TimeInterval?
}

private struct LibraryNamedCountPayload: Decodable {
    let id: String?
    let name: String
    let count: Int
}

private struct LibraryGenreCountPayload: Decodable {
    let id: String?
    let genre: String
    let count: Int
}

private typealias MediaProgressResponse = MediaProgressPayload

private struct MediaProgressPayload: Decodable {
    let duration: TimeInterval?
    let progress: Double?
    let currentTime: TimeInterval?
    let isFinished: Bool?
    let finishedAt: Int64?
    let lastUpdate: Int64?
}

private struct MediaProgressEnvelope: Decodable {
    let mediaProgress: MediaProgressPayload?
    let progress: MediaProgressPayload?
    let result: MediaProgressPayload?
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
    let mediaProgress: MediaProgressPayload?
    let userMediaProgress: MediaProgressPayload?
    let bookmarks: [BookmarkPayload]?
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

        if let yearString = (try? container.decodeIfPresent(String.self, forKey: .publishedYear)) ?? nil {
            publishedYear = yearString
        } else if let yearInt = (try? container.decodeIfPresent(Int.self, forKey: .publishedYear)) ?? nil {
            publishedYear = String(yearInt)
        } else if let yearDouble = (try? container.decodeIfPresent(Double.self, forKey: .publishedYear)) ?? nil {
            publishedYear = String(Int(yearDouble.rounded()))
        } else {
            publishedYear = nil
        }
    }
}

private struct ItemDetailsTrack: Decodable {
    let ino: String?
    let title: String?
    let startOffset: TimeInterval?
    let duration: TimeInterval?
    let contentURL: String?
    let metadata: ItemDetailsTrackMetadata?

    private enum CodingKeys: String, CodingKey {
        case ino
        case title
        case startOffset
        case duration
        case contentURL = "contentUrl"
        case metadata
    }
}

private struct ItemDetailsTrackMetadata: Decodable {
    let filename: String?
}

private typealias BookmarkResponse = BookmarkPayload

private struct BookmarkPayload: Decodable {
    let title: String?
    let time: TimeInterval?
    let createdAt: Int64?
}

private struct ProgressUpdateRequest: Encodable {
    let duration: TimeInterval
    let progress: Double?
    let currentTime: TimeInterval
    let isFinished: Bool
    let finishedAt: Int64?
}

private struct BookmarkRequest: Encodable {
    let time: TimeInterval
    let title: String
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

private struct LossyNumber: Decodable {
    let value: TimeInterval

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
            return
        }
        if let intValue = try? container.decode(Int.self) {
            value = TimeInterval(intValue)
            return
        }
        if let int64Value = try? container.decode(Int64.self) {
            value = TimeInterval(int64Value)
            return
        }
        if let stringValue = try? container.decode(String.self),
           let parsed = TimeInterval(stringValue)
        {
            value = parsed
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected numeric value")
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyTimeInterval(forKey key: Key) -> TimeInterval? {
        guard let number = (try? decodeIfPresent(LossyNumber.self, forKey: key)) ?? nil else {
            return nil
        }
        return number.value
    }

    func decodeLossyInt(forKey key: Key) -> Int? {
        guard let raw = decodeLossyTimeInterval(forKey: key) else {
            return nil
        }
        return Int(raw.rounded())
    }

    func decodeLossyInt64(forKey key: Key) -> Int64? {
        guard let raw = decodeLossyTimeInterval(forKey: key) else {
            return nil
        }
        return Int64(raw.rounded())
    }

    func decodeLossyTimeIntervalMap(forKey key: Key) -> [String: TimeInterval] {
        guard let decoded = (try? decodeIfPresent([String: LossyNumber].self, forKey: key)) ?? nil else {
            return [:]
        }
        return decoded.mapValues(\.value)
    }

    func decodeLossyDayOfWeekMap(forKey key: Key) -> [Int: TimeInterval] {
        guard let decoded = (try? decodeIfPresent([String: LossyNumber].self, forKey: key)) ?? nil else {
            return [:]
        }
        return decoded.reduce(into: [Int: TimeInterval]()) { result, entry in
            if let weekday = Int(entry.key) {
                result[weekday] = entry.value.value
            }
        }
    }

    func decodeLossyArray<Element: Decodable>(forKey key: Key) -> [Element] {
        guard let decoded = (try? decodeIfPresent([LossyDecodable<Element>].self, forKey: key)) ?? nil else {
            return []
        }
        return decoded.compactMap(\.value)
    }

    func decodeLossyDictionary<Value: Decodable>(forKey key: Key) -> [String: Value] {
        guard let decoded = (try? decodeIfPresent([String: LossyDecodable<Value>].self, forKey: key)) ?? nil else {
            return [:]
        }
        return decoded.reduce(into: [String: Value]()) { result, entry in
            if let value = entry.value.value {
                result[entry.key] = value
            }
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Date {
    static func fromDayKey(_ value: String) -> Date? {
        let components = value.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2])
        else {
            return nil
        }

        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: .gregorian)
        dateComponents.timeZone = TimeZone(secondsFromGMT: 0)
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        return dateComponents.date
    }

    init(millisecondsSinceEpoch: Int64) {
        self = Date(timeIntervalSince1970: TimeInterval(millisecondsSinceEpoch) / 1000)
    }

    var millisecondsSinceEpoch: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
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
