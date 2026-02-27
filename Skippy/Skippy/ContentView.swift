//
//  ContentView.swift
//  Skippy
//
//  Created by Lupu Cristian on 27.02.2026.
//

import SwiftUI

@Observable
final class AppState {
    var isAuthenticated = false
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.isAuthenticated {
            AuthenticatedPlaceholderView()
        } else {
            UnauthenticatedPlaceholderView()
        }
    }
}

struct AuthenticatedPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Library placeholder (Phase 1)")
                .navigationTitle("Library")
        }
    }
}

struct UnauthenticatedPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
                Text("Skippy")
                    .font(.title2.weight(.semibold))
                Text("MVP foundation is in place. Login flow will be added next.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Welcome")
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
