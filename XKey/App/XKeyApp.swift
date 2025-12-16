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
        // XKeyApp initialized
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

