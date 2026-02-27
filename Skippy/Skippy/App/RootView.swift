import SwiftUI

struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Group {
            if dependencies.authStore.isAuthenticated {
                LibraryView(
                    viewModel: LibraryViewModel(
                        apiClient: dependencies.apiClient,
                        authStore: dependencies.authStore,
                        logger: dependencies.logger
                    ),
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
            } else {
                LoginView(
                    viewModel: LoginViewModel(
                        apiClient: dependencies.apiClient,
                        authStore: dependencies.authStore,
                        logger: dependencies.logger
                    )
                )
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppDependencies.makeMock())
}
