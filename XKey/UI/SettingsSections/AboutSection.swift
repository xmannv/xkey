//
//  AboutSection.swift
//  XKey
//
//  Shared About Settings Section
//

import SwiftUI

struct AboutSection: View {
    @State private var showDonationDialog = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // App Logo
                if let logo = NSImage(named: "XKeyLogo") {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .padding(.top, 20)
                } else {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 50))
                        .foregroundColor(.accentColor)
                        .padding(.top, 20)
                }
                
                // App Name & Version
                VStack(spacing: 4) {
                    Text("XKey")
                        .font(.system(size: 24, weight: .bold))
                    
                    Text("Vietnamese Input Method for macOS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(AppVersion.fullVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                
                Divider()
                    .padding(.horizontal, 80)
                
                // Credits & Donation
                VStack(spacing: 8) {
                    Text("Made with ❤️ & ☕")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        showDonationDialog = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "cup.and.saucer.fill")
                            Text("Buy me a coffee")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Divider()
                    .padding(.horizontal, 80)

                // Update Check Section - Using Sparkle
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                        Text("Kiểm tra phiên bản mới")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Kiểm tra cập nhật") {
                        // Temporarily lower the Settings window level so Sparkle dialog appears on top
                        if let settingsWindow = NSApp.keyWindow {
                            settingsWindow.level = .normal
                        }
                        
                        // Use AppDelegate.shared for reliable access
                        if let appDelegate = AppDelegate.shared {
                            appDelegate.checkForUpdatesFromUI()
                        } else if let delegate = NSApplication.shared.delegate as? AppDelegate {
                            delegate.checkForUpdatesFromUI()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(10)
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Copyright
                Text("Inspired by Openkey & Unikey.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showDonationDialog) {
            DonationView()
        }
    }
}
