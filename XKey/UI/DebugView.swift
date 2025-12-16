//
//  DebugView.swift
//  XKey
//
//  SwiftUI Debug Window
//

import SwiftUI

struct DebugView: View {
    @ObservedObject var viewModel: DebugViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            VStack(spacing: 4) {
                HStack {
                    Text(viewModel.statusText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                HStack {
                    Text("Log file: ~/XKey_Debug.log")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Input text area
            VStack(alignment: .leading, spacing: 4) {
                Text("Input Test Area:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $viewModel.inputText)
                    .font(.system(size: 16))
                    .frame(height: 200)
                    .border(Color.gray.opacity(0.3))
            }
            .padding()
            
            // Debug logs section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Debug Logs:")
                        .font(.system(size: 12, weight: .semibold))
                    
                    Spacer()
                    
                    Button("Read Word Before Cursor (⌘⇧R)") {
                        viewModel.readWordBeforeCursor()
                    }
                    
                    Toggle("Verbose", isOn: $viewModel.isVerboseLogging)
                        .toggleStyle(.checkbox)
                        .help("Show all debug messages (may cause lag)")
                    
                    Toggle("Enable Logging", isOn: $viewModel.isLoggingEnabled)
                        .toggleStyle(.checkbox)
                        .onChange(of: viewModel.isLoggingEnabled) { _ in
                            viewModel.toggleLogging()
                        }
                    
                    Button("Open Log File") {
                        viewModel.openLogFile()
                    }
                    .help("Open log file in Finder")
                    
                    Button("Clear") {
                        viewModel.clearLogs()
                    }
                    
                    Button("Copy") {
                        viewModel.copyLogs()
                    }
                }
                
                ScrollView {
                    ScrollViewReader { proxy in
                        Text(viewModel.logText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("logBottom")
                            .onChange(of: viewModel.logText) { _ in
                                proxy.scrollTo("logBottom", anchor: .bottom)
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color.gray.opacity(0.3))
            }
            .padding()
        }
        .frame(width: 800, height: 600)
    }
}

// MARK: - Preview

#Preview {
    DebugView(viewModel: DebugViewModel())
}
