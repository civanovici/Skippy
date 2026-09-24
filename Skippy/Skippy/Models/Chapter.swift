import Foundation

struct Chapter: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let duration: TimeInterval
}
