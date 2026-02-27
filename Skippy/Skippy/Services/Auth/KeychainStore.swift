import Foundation

protocol KeychainStoring {
    func save(token: String) throws
    func loadToken() throws -> String?
    func clearToken() throws
}

final class KeychainStore: KeychainStoring {
    private var cachedToken: String?

    func save(token: String) throws {
        cachedToken = token
    }

    func loadToken() throws -> String? {
        cachedToken
    }

    func clearToken() throws {
        cachedToken = nil
    }
}
