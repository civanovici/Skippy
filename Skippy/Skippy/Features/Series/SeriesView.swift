import SwiftUI

struct SeriesView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Series Coming Next",
                systemImage: "square.stack.3d.up",
                description: Text("Phase 3d will load real series data from Audiobookshelf.")
            )
            .navigationTitle("Series")
            .searchable(text: $searchText, prompt: "Search series")
        }
    }
}

#Preview {
    SeriesView()
}
