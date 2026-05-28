//
//  XKeyApp.swift
//  XKey
//
//  Main app entry point
//

import SwiftUI
import Foundation

@main
struct XKeyApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AppLanguage.applyLanguage()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Bảng điều khiển...") {
                    AppDelegate.shared?.openPreferences()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

