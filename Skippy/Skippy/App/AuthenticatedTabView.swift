import SwiftUI

struct AuthenticatedTabView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
            HomeView(
                viewModel: HomeViewModel(
                    apiClient: dependencies.apiClient,
                    authStore: dependencies.authStore,
                    logger: dependencies.logger
                ),
                makeBookDetailViewModel: { book in
                    BookDetailViewModel(
                        book: book,
                        apiClient: dependencies.apiClient,
                        authStore: dependencies.authStore,
                        logger: dependencies.logger
                    )
                },
                makePlayerViewModel: { book, chapter in
                    PlayerViewModel(
                        audiobook: book,
                        chapter: chapter,
                        playerService: dependencies.playerService,
                        nowPlayingService: dependencies.nowPlayingService,
                        apiClient: dependencies.apiClient,
                        authStore: dependencies.authStore,
                        persistenceController: dependencies.persistenceController,
                        logger: dependencies.logger
                    )
                }
            )
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
                makeBookDetailViewModel: { book in
                    BookDetailViewModel(
                        book: book,
                        apiClient: dependencies.apiClient,
                        authStore: dependencies.authStore,
                        logger: dependencies.logger
                    )
                },
                makePlayerViewModel: { book, chapter in
                    PlayerViewModel(
                        audiobook: book,
                        chapter: chapter,
                        playerService: dependencies.playerService,
                        nowPlayingService: dependencies.nowPlayingService,
                        apiClient: dependencies.apiClient,
                        authStore: dependencies.authStore,
                        persistenceController: dependencies.persistenceController,
                        logger: dependencies.logger
                    )
                }
            )
            .tabItem {
                Label("Library", systemImage: "books.vertical.fill")
            }
            .tag(AppState.Tab.library)

            SeriesView(
                viewModel: SeriesViewModel(
                    apiClient: dependencies.apiClient,
                    authStore: dependencies.authStore,
                    logger: dependencies.logger
                ),
                makeBookDetailViewModel: { book in
                    BookDetailViewModel(
                        book: book,
                        apiClient: dependencies.apiClient,
                        authStore: dependencies.authStore,
                        logger: dependencies.logger
                    )
                },
                makePlayerViewModel: { book, chapter in
                    PlayerViewModel(
                        audiobook: book,
                        chapter: chapter,
                        playerService: dependencies.playerService,
                        nowPlayingService: dependencies.nowPlayingService,
                        apiClient: dependencies.apiClient,
                        authStore: dependencies.authStore,
                        persistenceController: dependencies.persistenceController,
                        logger: dependencies.logger
                    )
                }
            )
                .tabItem {
                    Label("Series", systemImage: "square.stack.3d.up.fill")
                }
                .tag(AppState.Tab.series)

            CollectionsView(
                viewModel: CollectionsViewModel(
                    apiClient: dependencies.apiClient,
                    authStore: dependencies.authStore,
                    logger: dependencies.logger
                ),
                makeBookDetailViewModel: { book in
                    BookDetailViewModel(
                        book: book,
                        apiClient: dependencies.apiClient,
                        authStore: dependencies.authStore,
                        logger: dependencies.logger
                    )
                },
                makePlayerViewModel: { book, chapter in
                    PlayerViewModel(
                        audiobook: book,
                        chapter: chapter,
                        playerService: dependencies.playerService,
                        nowPlayingService: dependencies.nowPlayingService,
                        apiClient: dependencies.apiClient,
                        authStore: dependencies.authStore,
                        persistenceController: dependencies.persistenceController,
                        logger: dependencies.logger
                    )
                }
            )
                .tabItem {
                    Label("Collections", systemImage: "rectangle.stack.fill")
                }
                .tag(AppState.Tab.collections)

            UserView(
                username: dependencies.authStore.session?.username ?? "Unknown",
                onLogout: {
                    dependencies.authStore.signOut()
                }
            )
                .tabItem {
                    Label("User", systemImage: "person.crop.circle")
                }
                .tag(AppState.Tab.user)
        }
    }
}

#Preview {
    AuthenticatedTabView()
        .environment(AppDependencies.makeMock())
        .environment(AppState())
}
