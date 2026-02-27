import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    var serverURL = "https://demo.audiobookshelf.org"
    var username = "reader"
    var password = "password"
    var isLoading = false
    var errorMessage: String?

    private let apiClient: APIClientProtocol
    private let authStore: AuthStore
    private let logger: Logger

    init(apiClient: APIClientProtocol, authStore: AuthStore, logger: Logger) {
        self.apiClient = apiClient
        self.authStore = authStore
        self.logger = logger
    }

    func login() async {
        errorMessage = nil
        let normalizedURL = normalizeServerURL(serverURL)
        guard isValidServerURL(normalizedURL) else {
            errorMessage = APIError.invalidURL.errorDescription
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await apiClient.audiobookshelf.login(
                serverURL: normalizedURL,
                username: username,
                password: password
            )
            authStore.signIn(session: session)
            serverURL = normalizedURL
            logger.info("User signed in: \(username)")
        } catch let apiError as APIError {
            errorMessage = apiError.errorDescription
            logger.error("Login failed: \(apiError.localizedDescription)")
        } catch {
            errorMessage = "Unexpected error. Please try again."
            logger.error("Login failed: \(error.localizedDescription)")
        }
    }

    private func normalizeServerURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private func isValidServerURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let host = url.host else {
            return false
        }
        return !host.isEmpty
    }
}
