import SwiftUI

struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Group {
            if dependencies.authStore.isAuthenticated {
                AuthenticatedTabView()
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
