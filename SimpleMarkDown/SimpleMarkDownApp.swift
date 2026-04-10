//
//  SimpleMarkDownApp.swift
//  SimpleMarkDown
//

import SwiftUI

@main
struct SimpleMarkDownApp: App {

    var body: some Scene {
        // Multiple document windows (#20)
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 820, height: 600)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // File menu additions
            CommandGroup(after: .newItem) {
                Button("Open Recent") { }
                    .disabled(true)
                Divider()
                Button("Save As…") {
                    // Keyboard shortcut ⌘⇧S is already wired via ContentView's background buttons
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Export to HTML…") { }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(true) // Handled inside ContentView
                Divider()
                Button("Print…") { }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(true) // Handled inside ContentView
            }

            // View menu additions
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Toggle Focus Mode") { }
                    .keyboardShortcut("f", modifiers: [.command, .control])
                Button("Toggle Outline") { }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Toggle Quick Insert") { }
            }

            // Format menu
            CommandMenu("Format") {
                Button("Bold")          { }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic")        { }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Strikethrough") { }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Inline Code")   { }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Link")          { }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Heading 1")     { }.keyboardShortcut("1", modifiers: .command)
                Button("Heading 2")     { }.keyboardShortcut("2", modifiers: .command)
                Button("Heading 3")     { }.keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("Copy as Rich Text") { }
                    .keyboardShortcut("c", modifiers: [.command, .option])
            }
        }

        // Settings scene — accessible via ⌘, or SimpleMarkDown > Settings…
        Settings {
            SettingsView()
        }
    }
}
