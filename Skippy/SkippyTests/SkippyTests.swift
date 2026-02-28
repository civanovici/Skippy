import Foundation
import Testing
@testable import Skippy

@MainActor
@Suite(.serialized)
struct SkippyTests {
    @Test
    func loginParsesNestedUserToken() async throws {
        let session = makeSession { request in
            #expect(request.url?.path == "/login")
            let payload = """
            {
              "user": {
                "token": "nested-token-value"
              }
            }
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(payload.utf8)
            )
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let userSession = try await api.login(
            serverURL: "http://example.test:1234",
            username: "u",
            password: "p"
        )

        #expect(userSession.token == "nested-token-value")
    }

    @Test
    func fetchLibraryAggregatesAcrossMultipleLibraries() async throws {
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let page = Int(query.first(where: { $0.name == "page" })?.value ?? "0") ?? 0

            switch (path, page) {
            case ("/api/libraries", _):
                let payload = """
                {"libraries":[
                  {"id":"lib-a","mediaType":"book"},
                  {"id":"lib-b","mediaType":"book"}
                ]}
                """
                return ok(request.url!, payload)
            case ("/api/libraries/lib-a/items", 0):
                let payload = """
                {"results":[
                  {"id":"a1","mediaType":"book","media":{"metadata":{"title":"Alpha","authorName":"Author A"}}},
                  {"id":"a2","mediaType":"book","media":{"metadata":{"title":"Bravo","authorName":"Author B"}}}
                ]}
                """
                return ok(request.url!, payload)
            case ("/api/libraries/lib-b/items", 0):
                let payload = """
                {"results":[
                  {"id":"b1","mediaType":"book","media":{"metadata":{"title":"Charlie","authorName":"Author C"}}}
                ]}
                """
                return ok(request.url!, payload)
            default:
                return ok(request.url!, #"{"results":[]}"#)
            }
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let books = try await api.fetchLibrary(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        #expect(books.count == 3)
        #expect(books.map(\.title) == ["Alpha", "Bravo", "Charlie"])
    }

    @Test
    func fetchLibraryPaginatesBeyondFirstPage() async throws {
        let page0Items = (0..<200).map { index in
            """
            {"id":"book-\(index)","mediaType":"book","media":{"metadata":{"title":"Book \(index)","authorName":"A"}}}
            """
        }.joined(separator: ",")

        let session = makeSession { request in
            let path = request.url?.path ?? ""
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let page = Int(query.first(where: { $0.name == "page" })?.value ?? "0") ?? 0

            if path == "/api/libraries" {
                return ok(request.url!, #"{"libraries":[{"id":"lib-a","mediaType":"book"}]}"#)
            }
            if path == "/api/libraries/lib-a/items", page == 0 {
                return ok(request.url!, #"{"results":[\#(page0Items)]}"#)
            }
            if path == "/api/libraries/lib-a/items", page == 1 {
                return ok(request.url!, #"{"results":[{"id":"book-200","mediaType":"book","media":{"metadata":{"title":"Book 200","authorName":"A"}}}]}"#)
            }
            return ok(request.url!, #"{"results":[]}"#)
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let books = try await api.fetchLibrary(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        #expect(books.count == 201)
        #expect(books.contains(where: { $0.id == "book-200" }))
    }

    @Test
    func fetchPersonalizedShelvesMapsSections() async throws {
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            if path == "/api/libraries" {
                return ok(request.url!, #"{"libraries":[{"id":"lib-a","mediaType":"book"}]}"#)
            }
            if path == "/api/libraries/lib-a/personalized" {
                let payload = """
                [
                  {
                    "id":"recently-added",
                    "label":"Recently Added",
                    "entities":[
                      {"id":"a1","mediaType":"book","media":{"metadata":{"title":"Alpha","authorName":"Author A"}}}
                    ]
                  },
                  {
                    "id":"discover",
                    "label":"Discover",
                    "entities":[
                      {"id":"b1","mediaType":"book","media":{"metadata":{"title":"Bravo","authorName":"Author B"}}},
                      {"id":"b2","mediaType":"podcast","media":{"metadata":{"title":"Ignore","authorName":"Nope"}}}
                    ]
                  }
                ]
                """
                return ok(request.url!, payload)
            }
            return ok(request.url!, #"[]"#)
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let shelves = try await api.fetchPersonalizedShelves(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        #expect(shelves.count == 2)
        #expect(shelves[0].title == "Recently Added")
        #expect(shelves[0].books.map(\.title) == ["Alpha"])
        #expect(shelves[1].books.map(\.title) == ["Bravo"])
    }

    @Test
    func fetchSeriesMapsGroupedBooks() async throws {
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            if path == "/api/libraries" {
                return ok(request.url!, #"{"libraries":[{"id":"lib-a","mediaType":"book"}]}"#)
            }
            if path == "/api/libraries/lib-a/series" {
                let payload = """
                {
                  "results":[
                    {
                      "id":"series-1",
                      "name":"Foundation",
                      "books":[
                        {"id":"s1","mediaType":"book","media":{"metadata":{"title":"Book One","authorName":"Isaac Asimov"}}}
                      ]
                    }
                  ]
                }
                """
                return ok(request.url!, payload)
            }
            return ok(request.url!, #"{"results":[]}"#)
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let series = try await api.fetchSeries(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        #expect(series.count == 1)
        #expect(series[0].title == "Foundation")
        #expect(series[0].books.map(\.title) == ["Book One"])
    }

    @Test
    func fetchCollectionsMapsGroupedBooks() async throws {
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            if path == "/api/libraries" {
                return ok(request.url!, #"{"libraries":[{"id":"lib-a","mediaType":"book"}]}"#)
            }
            if path == "/api/libraries/lib-a/collections" {
                let payload = """
                {
                  "results":[
                    {
                      "id":"collection-1",
                      "name":"Sci-Fi",
                      "books":[
                        {"id":"c1","mediaType":"book","media":{"metadata":{"title":"Dune","authorName":"Frank Herbert"}}}
                      ]
                    }
                  ]
                }
                """
                return ok(request.url!, payload)
            }
            return ok(request.url!, #"{"results":[]}"#)
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let collections = try await api.fetchCollections(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        #expect(collections.count == 1)
        #expect(collections[0].title == "Sci-Fi")
        #expect(collections[0].books.map(\.title) == ["Dune"])
    }

    @Test
    func fetchCollectionsSupportsWrappedLibraryItems() async throws {
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            if path == "/api/libraries" {
                return ok(request.url!, #"{"libraries":[{"id":"lib-a","mediaType":"book"}]}"#)
            }
            if path == "/api/libraries/lib-a/collections" {
                let payload = """
                {
                  "results":[
                    {
                      "id":"collection-2",
                      "name":"Favorites",
                      "books":[
                        {
                          "libraryItem":{
                            "id":"c2",
                            "mediaType":"book",
                            "media":{"metadata":{"title":"Hyperion","authorName":"Dan Simmons"}}
                          }
                        }
                      ]
                    }
                  ]
                }
                """
                return ok(request.url!, payload)
            }
            return ok(request.url!, #"{"results":[]}"#)
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let collections = try await api.fetchCollections(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        #expect(collections.count == 1)
        #expect(collections[0].title == "Favorites")
        #expect(collections[0].books.map(\.title) == ["Hyperion"])
    }

    @Test
    func fetchCollectionsSupportsBookIDArrays() async throws {
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let page = Int(query.first(where: { $0.name == "page" })?.value ?? "0") ?? 0

            if path == "/api/libraries" {
                return ok(request.url!, #"{"libraries":[{"id":"lib-a","mediaType":"book"}]}"#)
            }
            if path == "/api/libraries/lib-a/collections", page == 0 {
                let payload = """
                {
                  "results":[
                    {"id":"collection-3","name":"By IDs","books":["c3"]}
                  ]
                }
                """
                return ok(request.url!, payload)
            }
            if path == "/api/libraries/lib-a/items", page == 0 {
                let payload = """
                {
                  "results":[
                    {"id":"c3","mediaType":"book","media":{"metadata":{"title":"Children of Time","authorName":"Adrian Tchaikovsky"}}}
                  ]
                }
                """
                return ok(request.url!, payload)
            }
            return ok(request.url!, #"{"results":[]}"#)
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let collections = try await api.fetchCollections(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        #expect(collections.count == 1)
        #expect(collections[0].title == "By IDs")
        #expect(collections[0].books.map(\.title) == ["Children of Time"])
    }

    @Test
    func fetchCollectionsSupportsNumericChapterIDs() async throws {
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            if path == "/api/libraries" {
                return ok(request.url!, #"{"libraries":[{"id":"lib-a","mediaType":"book"}]}"#)
            }
            if path == "/api/libraries/lib-a/collections" {
                let payload = """
                {
                  "results":[
                    {
                      "id":"collection-4",
                      "name":"Numeric Chapter IDs",
                      "books":[
                        {
                          "id":"c4",
                          "mediaType":"book",
                          "media":{
                            "metadata":{"title":"Project Hail Mary","authorName":"Andy Weir"},
                            "chapters":[{"id":1,"title":"Chapter 1","start":0,"end":12.5}]
                          }
                        }
                      ]
                    }
                  ]
                }
                """
                return ok(request.url!, payload)
            }
            return ok(request.url!, #"{"results":[]}"#)
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let collections = try await api.fetchCollections(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        #expect(collections.count == 1)
        #expect(collections[0].books.count == 1)
        #expect(collections[0].books[0].chapters.count == 1)
        #expect(collections[0].books[0].chapters[0].id == "1")
    }

    @Test
    func searchMapsBooksAndSeries() async throws {
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            if path == "/api/libraries" {
                return ok(request.url!, #"{"libraries":[{"id":"lib-a","mediaType":"book"}]}"#)
            }
            if path == "/api/libraries/lib-a/search" {
                let payload = """
                {
                  "book":[
                    {
                      "libraryItem":{
                        "id":"b1",
                        "mediaType":"book",
                        "media":{"metadata":{"title":"Book Match","authorName":"Author A"}}
                      }
                    }
                  ],
                  "series":[
                    {
                      "series":{"id":"s1","name":"Series Match"},
                      "books":[
                        {"id":"sb1","mediaType":"book","media":{"metadata":{"title":"Series Book","authorName":"Author B"}}}
                      ]
                    }
                  ]
                }
                """
                return ok(request.url!, payload)
            }
            return ok(request.url!, #"{}"#)
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let result = try await api.search(
            session: UserSession(
                serverURL: URL(string: "http://example.test:1234")!,
                username: "u",
                token: "tkn"
            ),
            query: "foundation"
        )

        #expect(result.books.map(\.title) == ["Book Match"])
        #expect(result.series.count == 1)
        #expect(result.series[0].title == "Series Match")
        #expect(result.series[0].books.map(\.title) == ["Series Book"])
    }

    @Test
    func searchAggregatesAcrossLibrariesAndPages() async throws {
        let page0Books = (0..<50).map { index in
            """
            {"libraryItem":{"id":"a\(index)","mediaType":"book","media":{"metadata":{"title":"A \(index)","authorName":"Author A"}}}}
            """
        }.joined(separator: ",")

        let session = makeSession { request in
            let path = request.url?.path ?? ""
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let page = Int(query.first(where: { $0.name == "page" })?.value ?? "0") ?? 0

            if path == "/api/libraries" {
                return ok(request.url!, #"{"libraries":[{"id":"lib-a","mediaType":"book"},{"id":"lib-b","mediaType":"book"}]}"#)
            }
            if path == "/api/libraries/lib-a/search", page == 0 {
                return ok(request.url!, #"{"book":[\#(page0Books)],"series":[]}"#)
            }
            if path == "/api/libraries/lib-a/search", page == 1 {
                return ok(request.url!, #"{"book":[{"libraryItem":{"id":"a50","mediaType":"book","media":{"metadata":{"title":"A 50","authorName":"Author A"}}}}],"series":[]}"#)
            }
            if path == "/api/libraries/lib-b/search", page == 0 {
                return ok(request.url!, #"{"book":[{"libraryItem":{"id":"b1","mediaType":"book","media":{"metadata":{"title":"B 1","authorName":"Author B"}}}}],"series":[]}"#)
            }
            return ok(request.url!, #"{"book":[],"series":[]}"#)
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let result = try await api.search(
            session: UserSession(
                serverURL: URL(string: "http://example.test:1234")!,
                username: "u",
                token: "tkn"
            ),
            query: "a"
        )

        #expect(result.books.count == 52)
        #expect(result.books.contains(where: { $0.id == "a50" }))
        #expect(result.books.contains(where: { $0.id == "b1" }))
    }

    @Test
    func fetchBookDetailsMapsMetadataAndMedia() async throws {
        let session = makeSession { request in
            let path = request.url?.path ?? ""
            if path == "/api/items/book-1" {
                let payload = """
                {
                  "media":{
                    "metadata":{
                      "subtitle":"Series 1",
                      "narrators":["R.C. Bray"],
                      "genres":["Audiobook","Sci-Fi"],
                      "publishedYear":2026,
                      "publisher":"Podium Audio",
                      "descriptionPlain":"Details description"
                    },
                    "duration":7200,
                    "size":1073741824,
                    "chapters":[
                      {"id":1,"title":"Chapter One","start":0,"end":60}
                    ],
                    "tracks":[
                      {"ino":"track-1","duration":3600,"metadata":{"filename":"part1.m4b"}}
                    ]
                  }
                }
                """
                return ok(request.url!, payload)
            }
            return ok(request.url!, #"{}"#)
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let details = try await api.fetchBookDetails(
            session: UserSession(
                serverURL: URL(string: "http://example.test:1234")!,
                username: "u",
                token: "tkn"
            ),
            itemID: "book-1"
        )

        #expect(details.subtitle == "Series 1")
        #expect(details.narrators == ["R.C. Bray"])
        #expect(details.publishedYear == "2026")
        #expect(details.publisher == "Podium Audio")
        #expect(details.description == "Details description")
        #expect(details.duration == 7200)
        #expect(details.sizeBytes == 1073741824)
        #expect(details.chapters.count == 1)
        #expect(details.chapters[0].id == "1")
        #expect(details.tracks.count == 1)
        #expect(details.tracks[0].title == "part1.m4b")
        #expect(details.userProgress == nil)
        #expect(details.bookmarks.isEmpty)
    }

    @Test
    func fetchSeriesAggregatesAcrossLibrariesAndPages() async throws {
        let firstPageSeries = (0..<100).map { index in
            """
            {"id":"s\(index)","name":"Series \(index)","books":[{"id":"book-\(index)","mediaType":"book","media":{"metadata":{"title":"Book \(index)","authorName":"Author"}}}]}
            """
        }.joined(separator: ",")

        let session = makeSession { request in
            let path = request.url?.path ?? ""
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let page = Int(query.first(where: { $0.name == "page" })?.value ?? "0") ?? 0

            if path == "/api/libraries" {
                return ok(request.url!, #"{"libraries":[{"id":"lib-a","mediaType":"book"},{"id":"lib-b","mediaType":"book"}]}"#)
            }
            if path == "/api/libraries/lib-a/series", page == 0 {
                return ok(request.url!, #"{"results":[\#(firstPageSeries)]}"#)
            }
            if path == "/api/libraries/lib-a/series", page == 1 {
                return ok(request.url!, #"{"results":[{"id":"s100","name":"Series 100","books":[{"id":"book-100","mediaType":"book","media":{"metadata":{"title":"Book 100","authorName":"Author"}}}]}]}"#)
            }
            if path == "/api/libraries/lib-b/series", page == 0 {
                return ok(request.url!, #"{"results":[{"id":"sb1","name":"Series B","books":[{"id":"book-b1","mediaType":"book","media":{"metadata":{"title":"Book B1","authorName":"Author B"}}}]}]}"#)
            }
            return ok(request.url!, #"{"results":[]}"#)
        }

        let api = AudiobookshelfHTTPAPI(session: session)
        let series = try await api.fetchSeries(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        #expect(series.count == 102)
        #expect(series.contains(where: { $0.id == "s100" }))
        #expect(series.contains(where: { $0.id == "sb1" }))
    }

    @Test
    func libraryViewModelSignedOutShowsError() async throws {
        let authStore = AuthStore(keychainStore: InMemoryKeychainStore(), logger: Logger())
        let viewModel = LibraryViewModel(
            apiClient: StubAPIClient(audiobookshelf: StubAudiobookshelfAPI()),
            authStore: authStore,
            logger: Logger()
        )

        await viewModel.load()

        #expect(viewModel.books.isEmpty)
        #expect(viewModel.errorMessage == "You are not signed in.")
        #expect(viewModel.isLoading == false)
    }

    @Test
    func libraryViewModelLoadSuccessSetsBooks() async throws {
        let authStore = AuthStore(keychainStore: InMemoryKeychainStore(), logger: Logger())
        authStore.signIn(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        let expected = [
            Audiobook(id: "b1", title: "One", author: "A", progress: 0.0, coverURL: nil, chapters: []),
            Audiobook(id: "b2", title: "Two", author: "B", progress: 0.5, coverURL: nil, chapters: []),
        ]
        let api = StubAudiobookshelfAPI(fetchLibraryImpl: { _ in expected })
        let viewModel = LibraryViewModel(
            apiClient: StubAPIClient(audiobookshelf: api),
            authStore: authStore,
            logger: Logger()
        )

        await viewModel.load()

        #expect(viewModel.books == expected)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test
    func libraryViewModelLoadFailureSetsError() async throws {
        let authStore = AuthStore(keychainStore: InMemoryKeychainStore(), logger: Logger())
        authStore.signIn(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        let api = StubAudiobookshelfAPI(fetchLibraryImpl: { _ in
            throw APIError.networkUnreachable
        })
        let viewModel = LibraryViewModel(
            apiClient: StubAPIClient(audiobookshelf: api),
            authStore: authStore,
            logger: Logger()
        )

        await viewModel.load()

        #expect(viewModel.books.isEmpty)
        #expect(viewModel.errorMessage == APIError.networkUnreachable.errorDescription)
        #expect(viewModel.isLoading == false)
    }

    @Test
    func libraryViewModelSearchIgnoresStaleResults() async throws {
        let authStore = AuthStore(keychainStore: InMemoryKeychainStore(), logger: Logger())
        authStore.signIn(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        let oldResult = SearchResult(
            books: [Audiobook(id: "old", title: "Old", author: "A", progress: 0, coverURL: nil, chapters: [])],
            series: []
        )
        let newResult = SearchResult(
            books: [Audiobook(id: "new", title: "New", author: "B", progress: 0, coverURL: nil, chapters: [])],
            series: []
        )

        let api = StubAudiobookshelfAPI(searchImpl: { _, query in
            if query == "old" {
                try await Task.sleep(for: .milliseconds(120))
                return oldResult
            }
            try await Task.sleep(for: .milliseconds(20))
            return newResult
        })
        let viewModel = LibraryViewModel(
            apiClient: StubAPIClient(audiobookshelf: api),
            authStore: authStore,
            logger: Logger()
        )

        async let first: Void = viewModel.search(query: "old")
        try await Task.sleep(for: .milliseconds(10))
        async let second: Void = viewModel.search(query: "new")
        _ = await (first, second)

        #expect(viewModel.searchResults.map(\.id) == ["new"])
        #expect(viewModel.isSearching == false)
    }

    @Test
    func audiobookshelfFirst20FixtureIsValid() throws {
        let fixture = try loadFirst20Fixture()
        #expect(fixture.items.count == 20)
        #expect(fixture.items.allSatisfy { !$0.id.isEmpty && !$0.title.isEmpty && !$0.author.isEmpty })
    }

    @Test
    func bookCardLayoutFitsInsideContainerForObservedImageSizes() throws {
        let fixture = try loadFirst20Fixture()
        let observedSizes = fixture.items.compactMap { item -> CGSize? in
            guard let width = item.coverWidth, let height = item.coverHeight else { return nil }
            return CGSize(width: width, height: height)
        }

        let additionalRealSizes: [CGSize] = [
            CGSize(width: 400, height: 671),
            CGSize(width: 400, height: 644),
            CGSize(width: 400, height: 342),
            CGSize(width: 72, height: 96),
            CGSize(width: 1200, height: 800),
        ]

        let allSizes = observedSizes + additionalRealSizes
        let container = CGSize(width: 170, height: 170 / BookCardImageLayout.cardAspectRatio)

        #expect(!allSizes.isEmpty)
        for size in allSizes {
            #expect(BookCardImageLayout.fitsInsideContainer(image: size, container: container))
        }
    }

    @Test
    func persistenceControllerPersistsProgressAndBookmarks() throws {
        let defaultsName = "skippy.tests.persistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)

        let controller = PersistenceController(userDefaults: defaults)
        let progress = PlaybackProgress(
            audiobookID: "book-1",
            chapterID: "ch-1",
            positionSeconds: 321,
            durationSeconds: 900,
            isFinished: false,
            updatedAt: Date(timeIntervalSince1970: 100),
            lastServerSyncAt: Date(timeIntervalSince1970: 95)
        )
        let bookmarks = [
            AudioBookmark(audiobookID: "book-1", title: "A", time: 12, createdAt: Date(timeIntervalSince1970: 50)),
            AudioBookmark(audiobookID: "book-1", title: "B", time: 99, createdAt: Date(timeIntervalSince1970: 60)),
        ]

        controller.save(progress)
        controller.saveBookmarks(bookmarks, for: "book-1")

        let reloaded = PersistenceController(userDefaults: defaults)
        #expect(reloaded.loadProgress(for: "book-1") == progress)
        #expect(reloaded.loadBookmarks(for: "book-1") == bookmarks)
    }

    @Test
    func playerViewModelPrefersNewerServerProgress() async throws {
        let authStore = AuthStore(keychainStore: InMemoryKeychainStore(), logger: Logger())
        authStore.signIn(session: UserSession(
            serverURL: URL(string: "http://example.test:1234")!,
            username: "u",
            token: "tkn"
        ))

        let defaultsName = "skippy.tests.player.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        let persistence = PersistenceController(userDefaults: defaults)
        persistence.save(
            PlaybackProgress(
                audiobookID: "book-1",
                chapterID: nil,
                positionSeconds: 120,
                durationSeconds: 500,
                isFinished: false,
                updatedAt: Date(timeIntervalSince1970: 100),
                lastServerSyncAt: nil
            )
        )

        let api = StubAudiobookshelfAPI(
            fetchBookDetailsImpl: { _, _ in
                AudiobookDetails(
                    subtitle: nil,
                    narrators: [],
                    publishedYear: nil,
                    publisher: nil,
                    genres: [],
                    description: nil,
                    duration: 500,
                    sizeBytes: nil,
                    chapters: [],
                    tracks: [],
                    userProgress: nil,
                    bookmarks: []
                )
            },
            fetchMediaProgressImpl: { _, _ in
                PlaybackProgress(
                    audiobookID: "book-1",
                    chapterID: nil,
                    positionSeconds: 300,
                    durationSeconds: 500,
                    isFinished: false,
                    updatedAt: Date(timeIntervalSince1970: 200),
                    lastServerSyncAt: Date(timeIntervalSince1970: 200)
                )
            }
        )

        let viewModel = PlayerViewModel(
            audiobook: Audiobook(
                id: "book-1",
                title: "Book One",
                author: "Author",
                progress: 0,
                coverURL: nil,
                chapters: [Chapter(id: "c1", title: "Chapter 1", duration: 500)]
            ),
            chapter: nil,
            playerService: PlayerService(),
            nowPlayingService: NowPlayingService(),
            apiClient: StubAPIClient(audiobookshelf: api),
            authStore: authStore,
            persistenceController: persistence,
            logger: Logger()
        )

        await viewModel.start()
        #expect(viewModel.currentTime == 300)
    }
}

private func makeSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    MockURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func ok(_ url: URL, _ json: String) -> (HTTPURLResponse, Data) {
    (
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!,
        Data(json.utf8)
    )
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct StubAPIClient: APIClientProtocol {
    let audiobookshelf: AudiobookshelfAPI
}

private struct StubAudiobookshelfAPI: AudiobookshelfAPI {
    var loginImpl: ((String, String, String) async throws -> UserSession)?
    var fetchLibraryImpl: ((UserSession) async throws -> [Audiobook])?
    var fetchBookDetailsImpl: ((UserSession, String) async throws -> AudiobookDetails)?
    var fetchPersonalizedShelvesImpl: ((UserSession) async throws -> [HomeShelf])?
    var fetchSeriesImpl: ((UserSession) async throws -> [HomeShelf])?
    var fetchCollectionsImpl: ((UserSession) async throws -> [HomeShelf])?
    var searchImpl: ((UserSession, String) async throws -> SearchResult)?
    var fetchMediaProgressImpl: ((UserSession, String) async throws -> PlaybackProgress?)?
    var updateMediaProgressImpl: ((UserSession, String, TimeInterval, TimeInterval, Bool) async throws -> PlaybackProgress)?
    var createBookmarkImpl: ((UserSession, String, TimeInterval, String) async throws -> AudioBookmark)?
    var removeBookmarkImpl: ((UserSession, String, TimeInterval) async throws -> Void)?

    func login(serverURL: String, username: String, password: String) async throws -> UserSession {
        if let loginImpl {
            return try await loginImpl(serverURL, username, password)
        }
        return UserSession(
            serverURL: URL(string: serverURL)!,
            username: username,
            token: "stub-token"
        )
    }

    func fetchLibrary(session: UserSession) async throws -> [Audiobook] {
        if let fetchLibraryImpl {
            return try await fetchLibraryImpl(session)
        }
        return []
    }

    func fetchBookDetails(session: UserSession, itemID: String) async throws -> AudiobookDetails {
        if let fetchBookDetailsImpl {
            return try await fetchBookDetailsImpl(session, itemID)
        }
        return AudiobookDetails(
            subtitle: nil,
            narrators: [],
            publishedYear: nil,
            publisher: nil,
            genres: [],
            description: nil,
            duration: nil,
            sizeBytes: nil,
            chapters: [],
            tracks: [],
            userProgress: nil,
            bookmarks: []
        )
    }

    func fetchPersonalizedShelves(session: UserSession) async throws -> [HomeShelf] {
        if let fetchPersonalizedShelvesImpl {
            return try await fetchPersonalizedShelvesImpl(session)
        }
        return []
    }

    func fetchSeries(session: UserSession) async throws -> [HomeShelf] {
        if let fetchSeriesImpl {
            return try await fetchSeriesImpl(session)
        }
        return []
    }

    func fetchCollections(session: UserSession) async throws -> [HomeShelf] {
        if let fetchCollectionsImpl {
            return try await fetchCollectionsImpl(session)
        }
        return []
    }

    func search(session: UserSession, query: String) async throws -> SearchResult {
        if let searchImpl {
            return try await searchImpl(session, query)
        }
        return SearchResult(books: [], series: [])
    }

    func fetchMediaProgress(session: UserSession, itemID: String) async throws -> PlaybackProgress? {
        if let fetchMediaProgressImpl {
            return try await fetchMediaProgressImpl(session, itemID)
        }
        return nil
    }

    func updateMediaProgress(
        session: UserSession,
        itemID: String,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isFinished: Bool
    ) async throws -> PlaybackProgress {
        if let updateMediaProgressImpl {
            return try await updateMediaProgressImpl(session, itemID, currentTime, duration, isFinished)
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
        if let createBookmarkImpl {
            return try await createBookmarkImpl(session, itemID, time, title)
        }
        return AudioBookmark(audiobookID: itemID, title: title, time: time, createdAt: Date())
    }

    func removeBookmark(session: UserSession, itemID: String, time: TimeInterval) async throws {
        if let removeBookmarkImpl {
            return try await removeBookmarkImpl(session, itemID, time)
        }
    }
}

private final class InMemoryKeychainStore: KeychainStoring {
    private var stored: UserSession?

    func save(session: UserSession) throws {
        stored = session
    }

    func loadSession() throws -> UserSession? {
        stored
    }

    func clearSession() throws {
        stored = nil
    }
}

private struct First20Fixture: Decodable {
    struct Item: Decodable {
        let id: String
        let title: String
        let author: String
        let coverPath: String?
        let coverURL: String
        let progress: Double
        let coverWidth: Double?
        let coverHeight: Double?
    }

    let items: [Item]
}

private func loadFirst20Fixture() throws -> First20Fixture {
    let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let fixtureURL = testsDir.appendingPathComponent("Fixtures/audiobookshelf_first20.json")
    let data = try Data(contentsOf: fixtureURL)
    return try JSONDecoder().decode(First20Fixture.self, from: data)
}
