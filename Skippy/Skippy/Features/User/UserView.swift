import SwiftUI

struct UserView: View {
    let username: String
    let makeStatsViewModel: () -> StatsViewModel
    let onLogout: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Username", value: username)
                }

                Section("Activity") {
                    NavigationLink("Stats") {
                        StatsView(viewModel: makeStatsViewModel())
                    }
                }

                Section {
                    Button("Logout", role: .destructive) {
                        onLogout()
                    }
                }
            }
            .navigationTitle("User")
        }
    }
}

#Preview {
    UserView(
        username: "skippy",
        makeStatsViewModel: {
            StatsViewModel(
                apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
                authStore: AuthStore.previewAuthenticated,
                logger: Logger()
            )
        },
        onLogout: {}
    )
}
