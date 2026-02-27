import Foundation
import Observation

@Observable
final class AuthStore {
    var session: UserSession?
    private(set) var hasAttemptedRestore = false

    private let keychainStore: KeychainStoring
    private let logger: Logger

    init(keychainStore: KeychainStoring, logger: Logger) {
        self.keychainStore = keychainStore
        self.logger = logger
    }

    var isAuthenticated: Bool {
        session != nil
    }

    func signIn(session: UserSession) {
        self.session = session
        do {
            try keychainStore.save(session: session)
        } catch {
            logger.error("Failed to persist auth session: \(error.localizedDescription)")
        }
    }

    func signOut() {
        session = nil
        do {
            try keychainStore.clearSession()
        } catch {
            logger.error("Failed to clear auth session: \(error.localizedDescription)")
        }
    }

    func restoreSessionIfNeeded() {
        guard !hasAttemptedRestore else {
            return
        }
        hasAttemptedRestore = true

        do {
            session = try keychainStore.loadSession()
        } catch {
            logger.error("Failed to restore auth session: \(error.localizedDescription)")
            session = nil
        }
    }
}

extension AuthStore {
    static var previewAuthenticated: AuthStore {
        let store = AuthStore(keychainStore: KeychainStore(), logger: Logger())
        store.signIn(
            session: UserSession(
                serverURL: URL(string: "https://demo.audiobookshelf.org")!,
                username: "reader",
                token: "preview"
            )
        )
        return store
    }
}
