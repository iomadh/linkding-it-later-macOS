//
//  SettingsManager.swift
//  LinkdingosApp
//

import Foundation
import Combine

enum SortOrder: String, CaseIterable {
    case oldestFirst = "oldest"
    case newestFirst = "newest"

    var displayName: String {
        switch self {
        case .oldestFirst: return "Oldest First"
        case .newestFirst: return "Newest First"
        }
    }
}

enum ReaderFontSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var pixels: Int {
        switch self {
        case .small: return 16
        case .medium: return 18
        case .large: return 22
        }
    }
}

enum ReaderTheme: String, CaseIterable {
    case light = "light"
    case sepia = "sepia"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .dark: return "Dark"
        }
    }

    var colors: (bg: String, text: String, link: String) {
        switch self {
        case .light: return ("#ffffff", "#1c1c1e", "#007aff")
        case .sepia: return ("#f4ecd8", "#5b4636", "#8b4513")
        case .dark: return ("#1c1c1e", "#f5f5f7", "#6eb5ff")
        }
    }
}

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    static let appGroupID = "group.com.dellah.linkdingos"

    private let defaults = UserDefaults(suiteName: appGroupID) ?? UserDefaults.standard
    private let keychain = KeychainService.shared

    private enum Keys {
        static let serverURL = "linkding_server_url"
        static let sortOrder = "bookmark_sort_order"
        static let hideEmptyFilters = "hide_empty_filters"
        static let bookmarkFilters = "bookmark_filters"
        static let viaSourceURL = "via_source_url"
        static let readerFontSize = "reader_font_size"
        static let readerTheme = "reader_theme"
    }

    /// URL of the page the user is currently viewing in the app (for "via" links when sharing)
    var viaSourceURL: String? {
        get { defaults.string(forKey: Keys.viaSourceURL) }
        set { defaults.set(newValue, forKey: Keys.viaSourceURL) }
    }

    @Published var serverURL: String {
        didSet {
            defaults.set(serverURL, forKey: Keys.serverURL)
        }
    }

    @Published var sortOrder: SortOrder {
        didSet {
            defaults.set(sortOrder.rawValue, forKey: Keys.sortOrder)
        }
    }

    @Published var hideEmptyFilters: Bool {
        didSet {
            defaults.set(hideEmptyFilters, forKey: Keys.hideEmptyFilters)
        }
    }

    @Published var bookmarkFilters: [BookmarkFilter] {
        didSet {
            if let encoded = try? JSONEncoder().encode(bookmarkFilters) {
                defaults.set(encoded, forKey: Keys.bookmarkFilters)
            }
        }
    }

    @Published var readerFontSize: ReaderFontSize {
        didSet {
            defaults.set(readerFontSize.rawValue, forKey: Keys.readerFontSize)
        }
    }

    @Published var readerTheme: ReaderTheme {
        didSet {
            defaults.set(readerTheme.rawValue, forKey: Keys.readerTheme)
        }
    }

    var apiToken: String? {
        get { keychain.retrieve(for: .apiToken) }
        set {
            if let token = newValue, !token.isEmpty {
                try? keychain.save(token, for: .apiToken)
            } else {
                try? keychain.delete(.apiToken)
            }
        }
    }

    var isConfigured: Bool {
        !serverURL.isEmpty && apiToken != nil && !apiToken!.isEmpty
    }

    private init() {
        self.serverURL = defaults.string(forKey: Keys.serverURL) ?? ""
        let sortRaw = defaults.string(forKey: Keys.sortOrder) ?? SortOrder.oldestFirst.rawValue
        self.sortOrder = SortOrder(rawValue: sortRaw) ?? .oldestFirst
        self.hideEmptyFilters = defaults.bool(forKey: Keys.hideEmptyFilters)

        if let data = defaults.data(forKey: Keys.bookmarkFilters),
           let filters = try? JSONDecoder().decode([BookmarkFilter].self, from: data),
           !filters.isEmpty {
            self.bookmarkFilters = filters
        } else {
            self.bookmarkFilters = BookmarkFilter.defaultFilters
        }

        let fontSizeRaw = defaults.string(forKey: Keys.readerFontSize) ?? ReaderFontSize.medium.rawValue
        self.readerFontSize = ReaderFontSize(rawValue: fontSizeRaw) ?? .medium

        let themeRaw = defaults.string(forKey: Keys.readerTheme) ?? ReaderTheme.light.rawValue
        self.readerTheme = ReaderTheme(rawValue: themeRaw) ?? .light
    }

    func clearAll() {
        serverURL = ""
        sortOrder = .oldestFirst
        apiToken = nil
    }
}
