import SwiftUI

struct CollectionsView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Collections Coming Next",
                systemImage: "rectangle.stack",
                description: Text("Phase 3d will load real collections from Audiobookshelf.")
            )
            .navigationTitle("Collections")
            .searchable(text: $searchText, prompt: "Search collections")
        }
    }
}

#Preview {
    CollectionsView()
}
