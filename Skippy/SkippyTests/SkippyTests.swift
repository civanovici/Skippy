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
    var fetchPersonalizedShelvesImpl: ((UserSession) async throws -> [HomeShelf])?
    var fetchSeriesImpl: ((UserSession) async throws -> [HomeShelf])?
    var fetchCollectionsImpl: ((UserSession) async throws -> [HomeShelf])?
    var searchImpl: ((UserSession, String) async throws -> SearchResult)?

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
