import SwiftUI

struct ShelfView<Destination: View>: View {
    let title: String
    let books: [Audiobook]
    let destination: (Audiobook) -> Destination

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
                            BookCardView(book: book)
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
