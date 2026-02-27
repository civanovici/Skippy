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
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await apiClient.audiobookshelf.login(
                serverURL: serverURL,
                username: username,
                password: password
            )
            authStore.signIn(session: session)
            logger.info("User signed in: \(username)")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Login failed: \(error.localizedDescription)")
        }
    }
}
