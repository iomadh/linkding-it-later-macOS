//
//  SettingsView.swift
//  Linkding It Later
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $viewModel.serverURL)
                    .autocorrectionDisabled()

                SecureField("API Token", text: $viewModel.apiToken)
                    .autocorrectionDisabled()
            } header: {
                Text("Linkding Server")
            } footer: {
                Text("Enter your Linkding server URL (e.g., https://links.example.com) and API token from your Linkding settings.")
            }

            Section {
                Button {
                    Task { await viewModel.testConnection() }
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        if viewModel.isTesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(!viewModel.isValid || viewModel.isTesting)
            }

            Section {
                Picker("Sort Order", selection: $viewModel.sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.displayName).tag(order)
                    }
                }
            } header: {
                Text("Display")
            }

            Section {
                Picker("Font Size", selection: $viewModel.readerFontSize) {
                    ForEach(ReaderFontSize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }

                Picker("Theme", selection: $viewModel.readerTheme) {
                    ForEach(ReaderTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            } header: {
                Text("Reader Mode")
            }

            Section {
                NavigationLink {
                    FilterListView()
                } label: {
                    HStack {
                        Text("Manage Filters")
                        Spacer()
                        Text("\(SettingsManager.shared.bookmarkFilters.count)")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Filters")
            }

            Section {
                Button("Clear All Data", role: .destructive) {
                    viewModel.clearCredentials()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save()
                }
                .disabled(!viewModel.isValid)
            }
        }
        .alert("Connection Test", isPresented: $viewModel.showTestResult) {
            Button("OK", role: .cancel) { }
        } message: {
            if viewModel.testResultSuccess {
                Text("Successfully connected to your Linkding server!")
            } else {
                Text(viewModel.errorMessage ?? "Connection failed.")
            }
        }
    }
}
