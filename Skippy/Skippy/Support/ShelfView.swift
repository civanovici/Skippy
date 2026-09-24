import SwiftUI

struct ShelfView<Destination: View>: View {
    let title: String
    let books: [Audiobook]
    let downloadedBookIDs: Set<String>
    let destination: (Audiobook) -> Destination

    init(
        title: String,
        books: [Audiobook],
        downloadedBookIDs: Set<String> = [],
        destination: @escaping (Audiobook) -> Destination
    ) {
        self.title = title
        self.books = books
        self.downloadedBookIDs = downloadedBookIDs
        self.destination = destination
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(books) { book in
                        NavigationLink {
                            destination(book)
                        } label: {
                            BookCardView(book: book, isDownloaded: downloadedBookIDs.contains(book.id))
                                .frame(width: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}
