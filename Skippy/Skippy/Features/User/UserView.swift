import SwiftUI

struct UserView: View {
    let username: String
    let onLogout: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Username", value: username)
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
    UserView(username: "skippy", onLogout: {})
}
