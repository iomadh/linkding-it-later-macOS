//
//  MainViewModel.swift
//  LinkdingosApp
//

import Foundation
import SwiftUI
import Combine

enum ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case error(String)
}

@MainActor
class MainViewModel: ObservableObject {
    @Published var viewState: ViewState<[Bookmark]> = .idle
    @Published var showSettings: Bool = false
    @Published var selectedFilter: BookmarkFilter = SettingsManager.shared.bookmarkFilters.first ?? BookmarkFilter.defaultFilters[0]
    @Published var lastRefreshDate: Date?

    // Offline status
    @Published var isOffline: Bool = false
    @Published var pendingUpdateCount: Int = 0
    @Published var isSyncing: Bool = false

    private let cacheManager: OfflineCacheManager
    private let settings: SettingsManager
    private var cancellables = Set<AnyCancellable>()

    var bookmarks: [Bookmark] {
        if case .loaded(let bookmarks) = viewState {
            return bookmarks
        }
        return []
    }

    var filteredBookmarks: [Bookmark] {
        selectedFilter.apply(to: bookmarks)
    }

    var isLoading: Bool {
        if case .loading = viewState { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let message) = viewState { return message }
        return nil
    }

    var isConfigured: Bool {
        settings.isConfigured
    }

    func lastRefreshText(trigger: Bool = false) -> String {
        _ = trigger
        guard let date = lastRefreshDate else {
            // Show cache date if available
            if let cacheDate = cacheManager.lastSyncDate {
                return isOffline ? "Cached \(formatTimeAgo(cacheDate))" : "Updated \(formatTimeAgo(cacheDate))"
            }
            return ""
        }
        return isOffline ? "Cached \(formatTimeAgo(date))" : "Updated \(formatTimeAgo(date))"
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else {
            let days = seconds / 86400
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }

    init(cacheManager: OfflineCacheManager = .shared,
         settings: SettingsManager = .shared) {
        self.cacheManager = cacheManager
        self.settings = settings

        setupCacheManagerBindings()
    }

    private func setupCacheManagerBindings() {
        cacheManager.$isOffline
            .receive(on: DispatchQueue.main)
            .assign(to: &$isOffline)

        cacheManager.$pendingUpdateCount
            .receive(on: DispatchQueue.main)
            .assign(to: &$pendingUpdateCount)

        cacheManager.$isSyncing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSyncing)

        cacheManager.$lastSyncDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                if let date = date, self?.lastRefreshDate == nil {
                    self?.lastRefreshDate = date
                }
            }
            .store(in: &cancellables)

        // Subscribe to background refresh updates
        cacheManager.bookmarksDidUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newBookmarks in
                guard let self = self else { return }
                let newUnreadBookmarks = newBookmarks.filter { $0.unread }

                // Merge with existing bookmarks to preserve local state (e.g., mark as read)
                // This prevents disrupting the UI when viewing a bookmark detail
                if case .loaded(let existingBookmarks) = self.viewState {
                    var mergedBookmarks = existingBookmarks

                    // Add new bookmarks that don't exist locally
                    let existingIds = Set(existingBookmarks.map { $0.id })
                    for bookmark in newUnreadBookmarks {
                        if !existingIds.contains(bookmark.id) {
                            mergedBookmarks.append(bookmark)
                        }
                    }

                    // Update existing bookmarks with new data (but preserve local unread status)
                    for i in mergedBookmarks.indices {
                        if let newBookmark = newUnreadBookmarks.first(where: { $0.id == mergedBookmarks[i].id }) {
                            // Preserve local unread status (user might have marked as read locally)
                            let localUnread = mergedBookmarks[i].unread
                            var updated = newBookmark
                            if !localUnread {
                                // Keep it marked as read locally
                                updated = Bookmark(
                                    id: newBookmark.id,
                                    url: newBookmark.url,
                                    title: newBookmark.title,
                                    description: newBookmark.description,
                                    notes: newBookmark.notes,
                                    isArchived: newBookmark.isArchived,
                                    unread: false,
                                    shared: newBookmark.shared,
                                    tagNames: newBookmark.tagNames,
                                    dateAdded: newBookmark.dateAdded,
                                    dateModified: newBookmark.dateModified,
                                    websiteTitle: newBookmark.websiteTitle,
                                    websiteDescription: newBookmark.websiteDescription,
                                    faviconUrl: newBookmark.faviconUrl
                                )
                            }
                            mergedBookmarks[i] = updated
                        }
                    }

                    let sortedBookmarks = self.sortBookmarks(mergedBookmarks)
                    self.viewState = .loaded(sortedBookmarks)
                } else {
                    // No existing state, just load the new bookmarks
                    let sortedBookmarks = self.sortBookmarks(newUnreadBookmarks)
                    self.viewState = .loaded(sortedBookmarks)
                }

                self.lastRefreshDate = Date()
            }
            .store(in: &cancellables)
    }

    func loadBookmarks() async {
        guard settings.isConfigured else {
            viewState = .error("Please configure your Linkding server in Settings.")
            return
        }

        viewState = .loading

        do {
            let bookmarks = try await cacheManager.fetchBookmarks(unreadOnly: true)
            let unreadBookmarks = bookmarks.filter { $0.unread }
            let sortedBookmarks = sortBookmarks(unreadBookmarks)
            viewState = .loaded(sortedBookmarks)
            lastRefreshDate = Date()
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }

    private func sortBookmarks(_ bookmarks: [Bookmark]) -> [Bookmark] {
        bookmarks.sorted { first, second in
            switch settings.sortOrder {
            case .oldestFirst:
                return first.dateAdded < second.dateAdded
            case .newestFirst:
                return first.dateAdded > second.dateAdded
            }
        }
    }

    func refresh() async {
        // Sync any pending updates first, then load fresh bookmarks
        await cacheManager.syncPendingUpdates()
        await loadBookmarks()
    }

    func syncPendingUpdates() async {
        await cacheManager.syncPendingUpdates()
    }

    func removeBookmark(id: Int) {
        if case .loaded(var bookmarks) = viewState {
            bookmarks.removeAll { $0.id == id }
            viewState = .loaded(bookmarks)
        }
    }

    func updateBookmarkTags(id: Int, tags: [String]) {
        if case .loaded(var bookmarks) = viewState {
            if let index = bookmarks.firstIndex(where: { $0.id == id }) {
                let oldBookmark = bookmarks[index]
                let updatedBookmark = Bookmark(
                    id: oldBookmark.id,
                    url: oldBookmark.url,
                    title: oldBookmark.title,
                    description: oldBookmark.description,
                    notes: oldBookmark.notes,
                    isArchived: oldBookmark.isArchived,
                    unread: oldBookmark.unread,
                    shared: oldBookmark.shared,
                    tagNames: tags,
                    dateAdded: oldBookmark.dateAdded,
                    dateModified: oldBookmark.dateModified,
                    websiteTitle: oldBookmark.websiteTitle,
                    websiteDescription: oldBookmark.websiteDescription,
                    faviconUrl: oldBookmark.faviconUrl
                )
                bookmarks[index] = updatedBookmark
                viewState = .loaded(bookmarks)
            }
        }
    }

    func updateBookmarkNotes(id: Int, notes: String) {
        if case .loaded(var bookmarks) = viewState {
            if let index = bookmarks.firstIndex(where: { $0.id == id }) {
                let oldBookmark = bookmarks[index]
                let updatedBookmark = Bookmark(
                    id: oldBookmark.id,
                    url: oldBookmark.url,
                    title: oldBookmark.title,
                    description: oldBookmark.description,
                    notes: notes,
                    isArchived: oldBookmark.isArchived,
                    unread: oldBookmark.unread,
                    shared: oldBookmark.shared,
                    tagNames: oldBookmark.tagNames,
                    dateAdded: oldBookmark.dateAdded,
                    dateModified: oldBookmark.dateModified,
                    websiteTitle: oldBookmark.websiteTitle,
                    websiteDescription: oldBookmark.websiteDescription,
                    faviconUrl: oldBookmark.faviconUrl
                )
                bookmarks[index] = updatedBookmark
                viewState = .loaded(bookmarks)
            }
        }
    }

    func toggleReadStatus(id: Int) async {
        guard case .loaded(let bookmarks) = viewState,
              let bookmark = bookmarks.first(where: { $0.id == id }) else { return }

        let isCurrentlyUnread = bookmark.unread
        do {
            try await cacheManager.setUnreadStatus(bookmarkId: id, unread: !isCurrentlyUnread)
            if isCurrentlyUnread {
                // Marked as read - remove from unread list
                removeBookmark(id: id)
            }
        } catch {
            // Update still queued if offline - operation succeeded locally
            if isCurrentlyUnread {
                removeBookmark(id: id)
            }
        }
    }

    func toggleStar(id: Int) async {
        guard case .loaded(let bookmarks) = viewState,
              let bookmark = bookmarks.first(where: { $0.id == id }) else { return }

        var newTags = bookmark.tagNames
        if newTags.contains("!star") {
            newTags.removeAll { $0 == "!star" }
        } else {
            newTags.append("!star")
        }

        do {
            try await cacheManager.updateBookmarkTags(bookmarkId: id, tags: newTags)
            updateBookmarkTags(id: id, tags: newTags)
        } catch {
            // Update still queued if offline - update UI optimistically
            updateBookmarkTags(id: id, tags: newTags)
        }
    }

    func fetchAvailableTags() async -> [String] {
        (try? await cacheManager.fetchAllTags()) ?? []
    }

    func refreshBookmark(id: Int) async {
        guard case .loaded(let bookmarks) = viewState,
              let bookmark = bookmarks.first(where: { $0.id == id }) else { return }

        do {
            let (title, description) = try await cacheManager.refreshBookmarkMetadata(bookmarkId: id, url: bookmark.url)
            updateBookmarkMetadata(id: id, title: title, description: description)
        } catch {
            // Update still queued if offline - no local update for refresh
        }
    }

    func updateBookmark(id: Int, title: String, description: String, notes: String, unread: Bool, shared: Bool) async {
        do {
            try await cacheManager.updateBookmark(bookmarkId: id, title: title, description: description, notes: notes, unread: unread, shared: shared)
            updateBookmarkFull(id: id, title: title, description: description, notes: notes, unread: unread, shared: shared)
        } catch {
            // Update still queued if offline - update UI optimistically
            updateBookmarkFull(id: id, title: title, description: description, notes: notes, unread: unread, shared: shared)
        }
    }

    func deleteBookmark(id: Int) async {
        do {
            try await cacheManager.deleteBookmark(bookmarkId: id)
            removeBookmark(id: id)
        } catch {
            // Delete still queued if offline - remove from UI optimistically
            removeBookmark(id: id)
        }
    }

    private func updateBookmarkMetadata(id: Int, title: String?, description: String?) {
        if case .loaded(var bookmarks) = viewState {
            if let index = bookmarks.firstIndex(where: { $0.id == id }) {
                let oldBookmark = bookmarks[index]
                let updatedBookmark = Bookmark(
                    id: oldBookmark.id,
                    url: oldBookmark.url,
                    title: title ?? oldBookmark.title,
                    description: description ?? oldBookmark.description,
                    notes: oldBookmark.notes,
                    isArchived: oldBookmark.isArchived,
                    unread: oldBookmark.unread,
                    shared: oldBookmark.shared,
                    tagNames: oldBookmark.tagNames,
                    dateAdded: oldBookmark.dateAdded,
                    dateModified: oldBookmark.dateModified,
                    websiteTitle: oldBookmark.websiteTitle,
                    websiteDescription: oldBookmark.websiteDescription,
                    faviconUrl: oldBookmark.faviconUrl
                )
                bookmarks[index] = updatedBookmark
                viewState = .loaded(bookmarks)
            }
        }
    }

    private func updateBookmarkFull(id: Int, title: String, description: String, notes: String, unread: Bool, shared: Bool) {
        if case .loaded(var bookmarks) = viewState {
            if let index = bookmarks.firstIndex(where: { $0.id == id }) {
                let oldBookmark = bookmarks[index]
                let updatedBookmark = Bookmark(
                    id: oldBookmark.id,
                    url: oldBookmark.url,
                    title: title,
                    description: description,
                    notes: notes,
                    isArchived: oldBookmark.isArchived,
                    unread: unread,
                    shared: shared,
                    tagNames: oldBookmark.tagNames,
                    dateAdded: oldBookmark.dateAdded,
                    dateModified: oldBookmark.dateModified,
                    websiteTitle: oldBookmark.websiteTitle,
                    websiteDescription: oldBookmark.websiteDescription,
                    faviconUrl: oldBookmark.faviconUrl
                )
                bookmarks[index] = updatedBookmark
                viewState = .loaded(bookmarks)
            }
        }
    }
}
