import Foundation

protocol AudiobookshelfAPI {
    func login(serverURL: String, username: String, password: String) async throws -> UserSession
    func fetchLibrary(session: UserSession) async throws -> [Audiobook]
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
        let libraries: [LibrarySummary] = try await fetchLibraries(session: userSession)
        let audiobookLibraries = libraries.filter { $0.mediaType == "book" }
        let targetLibraries = audiobookLibraries.isEmpty ? libraries : audiobookLibraries
        guard !targetLibraries.isEmpty else {
            return []
        }

        var booksByID: [String: Audiobook] = [:]
        for library in targetLibraries {
            let request = makeAuthedRequest(
                userSession.serverURL.appending(path: "/api/libraries/\(library.id)/items"),
                token: userSession.token,
                queryItems: [
                    URLQueryItem(name: "minified", value: "1"),
                    URLQueryItem(name: "limit", value: "1000"),
                ]
            )

            let items = try await fetchLibraryItems(request: request)
            for item in items where (item.mediaType ?? "book") == "book" {
                booksByID[item.id] = mapAudiobook(item, userSession: userSession)
            }
        }

        return booksByID.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
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

    private func fetchLibraryItems(request: URLRequest) async throws -> [LibraryItem] {
        do {
            let wrapped: LibraryItemsResponse = try await decode(request, expecting: LibraryItemsResponse.self)
            return wrapped.results
        } catch let error as APIError where error == .serverAPIMismatch {
            struct Alternate: Decodable {
                let libraryItems: [LibraryItem]
            }
            do {
                let alternate: Alternate = try await decode(request, expecting: Alternate.self)
                return alternate.libraryItems
            } catch let nested as APIError where nested == .serverAPIMismatch {
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
        } catch let error as APIError where error == .serverAPIMismatch {
            struct Wrapped: Decodable {
                let libraries: [LibrarySummary]
            }
            let wrapped: Wrapped = try await decode(request, expecting: Wrapped.self)
            return wrapped.libraries
        }
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
        } catch {
            throw APIError.serverAPIMismatch
        }
    }
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
}

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case networkUnreachable
    case invalidCredentials
    case serverAPIMismatch
    case unauthorized

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
}
