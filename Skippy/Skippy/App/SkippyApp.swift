import SwiftUI

@main
struct SkippyApp: App {
    @State private var dependencies = AppDependencies.makeLive()
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(appState)
                .task {
                    dependencies.authStore.restoreSessionIfNeeded()
                }
        }
    }
}
