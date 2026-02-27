import Foundation
import Security

protocol KeychainStoring {
    func save(session: UserSession) throws
    func loadSession() throws -> UserSession?
    func clearSession() throws
}

final class KeychainStore: KeychainStoring {
    private let service: String
    private let account = "userSession"

    init(service: String = "com.example.skippy.auth") {
        self.service = service
    }

    func save(session: UserSession) throws {
        let encoded = try JSONEncoder().encode(session)
        try clearSession()

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: encoded,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.osStatus(status)
        }
    }

    func loadSession() throws -> UserSession? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.osStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return try JSONDecoder().decode(UserSession.self, from: data)
    }

    func clearSession() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case invalidData
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Stored keychain data is invalid."
        case let .osStatus(status):
            return "Keychain OSStatus error: \(status)"
        }
    }
}
