import Foundation

struct UserSession: Equatable {
    let serverURL: URL
    let username: String
    let token: String
}
