import Foundation

struct HomeShelf: Identifiable, Hashable {
    let id: String
    let title: String
    let books: [Audiobook]
}
