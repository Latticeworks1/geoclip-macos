//
//  GeoCLIPApp.swift
//  GeoCLIP
//
//  Main app entry point
//

import SwiftUI

@main
struct GeoCLIPApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
        }
    }
}
