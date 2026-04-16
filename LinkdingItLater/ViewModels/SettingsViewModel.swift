//
//  SettingsViewModel.swift
//  LinkdingosApp
//

import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var serverURL: String
    @Published var apiToken: String
    @Published var sortOrder: SortOrder
    @Published var readerFontSize: ReaderFontSize
    @Published var readerTheme: ReaderTheme
    @Published var isTesting: Bool = false
    @Published var showTestResult: Bool = false
    @Published var testResultSuccess: Bool = false
    @Published var errorMessage: String?

    private let settings: SettingsManager
    private let linkdingService: LinkdingServiceProtocol

    init(settings: SettingsManager = .shared,
         linkdingService: LinkdingServiceProtocol = LinkdingService.shared) {
        self.settings = settings
        self.linkdingService = linkdingService
        self.serverURL = settings.serverURL
        self.apiToken = settings.apiToken ?? ""
        self.sortOrder = settings.sortOrder
        self.readerFontSize = settings.readerFontSize
        self.readerTheme = settings.readerTheme
    }

    func save() {
        settings.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.apiToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.sortOrder = sortOrder
        settings.readerFontSize = readerFontSize
        settings.readerTheme = readerTheme
    }

    func testConnection() async {
        isTesting = true
        errorMessage = nil

        let originalURL = settings.serverURL
        let originalToken = settings.apiToken

        settings.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.apiToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try await linkdingService.fetchBookmarks(unreadOnly: false)
            testResultSuccess = true
            showTestResult = true
        } catch {
            settings.serverURL = originalURL
            settings.apiToken = originalToken

            testResultSuccess = false
            errorMessage = error.localizedDescription
            showTestResult = true
        }

        isTesting = false
    }

    func clearCredentials() {
        settings.clearAll()
        serverURL = ""
        apiToken = ""
        sortOrder = .oldestFirst
    }

    var isValid: Bool {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedURL.isEmpty && !trimmedToken.isEmpty && URL(string: trimmedURL) != nil
    }
}
