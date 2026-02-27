import Foundation

protocol AudiobookshelfAPI {
    func login(serverURL: String, username: String, password: String) async throws -> UserSession
    func fetchLibrary(session: UserSession) async throws -> [Audiobook]
}

struct MockAudiobookshelfAPI: AudiobookshelfAPI {
    func login(serverURL: String, username: String, password: String) async throws -> UserSession {
        guard let url = URL(string: serverURL), !username.isEmpty, !password.isEmpty else {
            throw APIError.invalidCredentials
        }

        return UserSession(serverURL: url, username: username, token: "mock-token")
    }

    func fetchLibrary(session: UserSession) async throws -> [Audiobook] {
        _ = session
        return Audiobook.mockLibrary
    }
}

enum APIError: LocalizedError {
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid server URL or credentials."
        }
    }
}
