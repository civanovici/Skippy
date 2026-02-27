import Foundation
import Observation

@Observable
final class AuthStore {
    var session: UserSession?

    var isAuthenticated: Bool {
        session != nil
    }

    func signIn(session: UserSession) {
        self.session = session
    }

    func signOut() {
        session = nil
    }
}

extension AuthStore {
    static var previewAuthenticated: AuthStore {
        let store = AuthStore()
        store.session = UserSession(
            serverURL: URL(string: "https://demo.audiobookshelf.org")!,
            username: "reader",
            token: "preview"
        )
        return store
    }
}
