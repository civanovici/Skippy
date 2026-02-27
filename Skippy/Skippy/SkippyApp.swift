//
//  SkippyApp.swift
//  Skippy
//
//  Created by Lupu Cristian on 27.02.2026.
//

import SwiftUI

@main
struct SkippyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}
