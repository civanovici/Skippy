import Foundation

struct UserSession: Equatable, Codable {
    let serverURL: URL
    let username: String
    let token: String
}
