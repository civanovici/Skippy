import SwiftUI

struct BookCardView: View {
    let book: Audiobook
    var isDownloaded: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cover

            LinearGradient(
                colors: [.clear, .black.opacity(0.28), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(clean(book.title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(clean(book.author))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 7)
            .padding(.top, 28)

            if book.progress > 0 {
                Text("\(Int(book.progress * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.red.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if isDownloaded {
                Label("Offline", systemImage: "arrow.down.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(BookCardImageLayout.cardAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    @ViewBuilder
    private var cover: some View {
        AsyncImage(url: book.coverURL) { phase in
            switch phase {
            case let .success(image):
                ZStack {
                    Color.black.opacity(0.75)
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            default:
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.34, green: 0.16, blue: 0.08), Color(red: 0.12, green: 0.08, blue: 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    BookCardView(book: Audiobook.mockLibrary.first!)
        .padding()
        .background(Color(.systemGroupedBackground))
}
