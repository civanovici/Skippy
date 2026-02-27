import Foundation

protocol AudiobookshelfAPI {
    func login(serverURL: String, username: String, password: String) async throws -> UserSession
    func fetchLibrary(session: UserSession) async throws -> [Audiobook]
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

enum APIError: LocalizedError {
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
