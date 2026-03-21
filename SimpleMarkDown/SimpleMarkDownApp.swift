//
//  SimpleMarkDownApp.swift
//  SimpleMarkDown
//

import SwiftUI

@main
struct SimpleMarkDownApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 820, height: 600)
        .windowToolbarStyle(.unified(showsTitle: true))

        // Settings scene = la fenêtre qui s'ouvre avec ⌘,
        // macOS l'ajoute automatiquement dans le menu "SimpleMarkDown > Settings…"
        Settings {
            SettingsView()
        }
    }
}
