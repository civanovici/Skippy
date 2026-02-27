import SwiftUI

struct HomeView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Home Shelves Coming Next",
                systemImage: "house",
                description: Text("Phase 3b will load personalized shelves from Audiobookshelf.")
            )
            .navigationTitle("Home")
            .searchable(text: $searchText, prompt: "Search home")
        }
    }
}

#Preview {
    HomeView()
}
