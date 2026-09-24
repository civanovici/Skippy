import Foundation

struct HomeShelf: Identifiable, Hashable {
    let id: String
    let title: String
    let books: [Audiobook]
    /// Series whose numbers label and order the books (the series itself, or a collection's main series).
    var seriesName: String? = nil
}
