import Foundation

struct AudioBookmark: Identifiable, Hashable, Codable {
    let audiobookID: String
    let title: String
    let time: TimeInterval
    let createdAt: Date?

    var id: String {
        "\(audiobookID)-\(Int((time * 1000).rounded(.towardZero)))"
    }
}
