import SwiftUI

struct AuthenticatedTabView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppState.Tab.home)

            LibraryView(
                viewModel: LibraryViewModel(
                    apiClient: dependencies.apiClient,
                    authStore: dependencies.authStore,
                    logger: dependencies.logger
                ),
                onLogout: {
                    dependencies.authStore.signOut()
                },
                makeBookDetailViewModel: { book in
                    BookDetailViewModel(book: book)
                },
                makePlayerViewModel: { book, chapter in
                    PlayerViewModel(
                        audiobook: book,
                        chapter: chapter,
                        playerService: dependencies.playerService,
                        nowPlayingService: dependencies.nowPlayingService
                    )
                }
            )
            .tabItem {
                Label("Library", systemImage: "books.vertical.fill")
            }
            .tag(AppState.Tab.library)

            SeriesView()
                .tabItem {
                    Label("Series", systemImage: "square.stack.3d.up.fill")
                }
                .tag(AppState.Tab.series)

            CollectionsView()
                .tabItem {
                    Label("Collections", systemImage: "rectangle.stack.fill")
                }
                .tag(AppState.Tab.collections)
        }
    }
}

#Preview {
    AuthenticatedTabView()
        .environment(AppDependencies.makeMock())
        .environment(AppState())
}
