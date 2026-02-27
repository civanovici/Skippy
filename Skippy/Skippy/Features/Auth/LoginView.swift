import SwiftUI

struct LoginView: View {
    @State var viewModel: LoginViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("https://audiobookshelf.example", text: $viewModel.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section("Credentials") {
                    TextField("Username", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $viewModel.password)
                }

                Section {
                    Button {
                        Task {
                            await viewModel.login()
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign In")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.serverURL.isEmpty || viewModel.username.isEmpty || viewModel.password.isEmpty)
                }

                if let error = viewModel.errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sign In")
        }
    }
}

#Preview {
    LoginView(
        viewModel: LoginViewModel(
            apiClient: APIClient(),
            authStore: AuthStore(),
            logger: Logger()
        )
    )
}
