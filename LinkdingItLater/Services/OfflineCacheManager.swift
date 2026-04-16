//
//  OfflineCacheManager.swift
//  LinkdingosApp
//

import Foundation
import Combine

@MainActor
final class OfflineCacheManager: ObservableObject {
    static let shared = OfflineCacheManager()

    @Published private(set) var isOffline: Bool = false
    @Published private(set) var pendingUpdateCount: Int = 0
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var isSyncing: Bool = false

    /// Notifies subscribers when bookmarks have been updated (e.g., from background refresh)
    let bookmarksDidUpdate = PassthroughSubject<[Bookmark], Never>()

    private let linkdingService: LinkdingServiceProtocol
    private let cacheStorage: CacheStorage
    private let networkMonitor: NetworkMonitor
    private var cancellables = Set<AnyCancellable>()

    private let maxRetries = 3

    /// Timer for periodic foreground refresh
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 15 * 60 // 15 minutes

    init(
        linkdingService: LinkdingServiceProtocol = LinkdingService.shared,
        cacheStorage: CacheStorage = .shared,
        networkMonitor: NetworkMonitor = .shared
    ) {
        self.linkdingService = linkdingService
        self.cacheStorage = cacheStorage
        self.networkMonitor = networkMonitor

        loadCachedState()
        setupNetworkObserver()
    }

    private func loadCachedState() {
        if let metadata = cacheStorage.loadMetadata() {
            lastSyncDate = metadata.lastSyncDate
            pendingUpdateCount = metadata.pendingUpdateCount
        }
    }

    private func setupNetworkObserver() {
        networkMonitor.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOffline = !isConnected
            }
            .store(in: &cancellables)

        networkMonitor.networkBecameAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Task { [weak self] in
                    await self?.syncPendingUpdates()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Timer-based Refresh

    /// Start the periodic refresh timer (call when app becomes active)
    func startPeriodicRefresh() {
        stopPeriodicRefresh()
        print("[PeriodicRefresh] Starting timer with \(refreshInterval/60) minute interval")

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performPeriodicRefresh()
            }
        }
    }

    /// Stop the periodic refresh timer (call when app goes to background)
    func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("[PeriodicRefresh] Timer stopped")
    }

    private func performPeriodicRefresh() async {
        guard networkMonitor.isConnected else {
            print("[PeriodicRefresh] Skipping - offline")
            return
        }

        print("[PeriodicRefresh] Starting periodic refresh...")

        // Sync pending updates first
        await syncPendingUpdates()

        // Then fetch new bookmarks
        do {
            let bookmarks = try await linkdingService.fetchBookmarks(unreadOnly: true)
            cacheStorage.saveBookmarks(bookmarks)
            lastSyncDate = Date()
            bookmarksDidUpdate.send(bookmarks)
            print("[PeriodicRefresh] Completed - fetched \(bookmarks.count) bookmarks")
        } catch {
            print("[PeriodicRefresh] Failed to fetch bookmarks: \(error)")
        }
    }

    // MARK: - Fetch Bookmarks

    func fetchBookmarks(unreadOnly: Bool = true, notifyOnUpdate: Bool = false) async throws -> [Bookmark] {
        if networkMonitor.isConnected {
            do {
                let bookmarks = try await linkdingService.fetchBookmarks(unreadOnly: unreadOnly)
                cacheStorage.saveBookmarks(bookmarks)
                lastSyncDate = Date()

                if notifyOnUpdate {
                    bookmarksDidUpdate.send(bookmarks)
                }

                return bookmarks
            } catch {
                // Network request failed, try cache
                if let cached = cacheStorage.loadBookmarks() {
                    return cached
                }
                throw error
            }
        } else {
            // Offline - use cache
            if let cached = cacheStorage.loadBookmarks() {
                return cached
            }
            throw OfflineCacheError.noCachedData
        }
    }

    // MARK: - Set Unread Status

    func setUnreadStatus(bookmarkId: Int, unread: Bool) async throws {
        // Update cache immediately (optimistic update)
        updateCachedBookmarkUnreadStatus(bookmarkId: bookmarkId, unread: unread)

        if networkMonitor.isConnected {
            do {
                try await linkdingService.setUnreadStatus(bookmarkId: bookmarkId, unread: unread)
            } catch {
                // Network failed, queue for later
                queueUpdate(bookmarkId: bookmarkId, type: .setUnread, payload: .setUnread(unread: unread))
                throw error
            }
        } else {
            // Offline, queue for later
            queueUpdate(bookmarkId: bookmarkId, type: .setUnread, payload: .setUnread(unread: unread))
        }
    }

    // MARK: - Update Tags

    func updateBookmarkTags(bookmarkId: Int, tags: [String]) async throws {
        // Update cache immediately (optimistic update)
        updateCachedBookmarkTags(bookmarkId: bookmarkId, tags: tags)

        if networkMonitor.isConnected {
            do {
                try await linkdingService.updateBookmarkTags(bookmarkId: bookmarkId, tags: tags)
            } catch {
                // Network failed, queue for later
                queueUpdate(bookmarkId: bookmarkId, type: .updateTags, payload: .updateTags(tags: tags))
                throw error
            }
        } else {
            // Offline, queue for later
            queueUpdate(bookmarkId: bookmarkId, type: .updateTags, payload: .updateTags(tags: tags))
        }
    }

    // MARK: - Update Notes

    func updateBookmarkNotes(bookmarkId: Int, notes: String) async throws {
        // Update cache immediately (optimistic update)
        updateCachedBookmarkNotes(bookmarkId: bookmarkId, notes: notes)

        if networkMonitor.isConnected {
            do {
                try await linkdingService.updateBookmarkNotes(bookmarkId: bookmarkId, notes: notes)
            } catch {
                // Network failed, queue for later
                queueUpdate(bookmarkId: bookmarkId, type: .updateNotes, payload: .updateNotes(notes: notes))
                throw error
            }
        } else {
            // Offline, queue for later
            queueUpdate(bookmarkId: bookmarkId, type: .updateNotes, payload: .updateNotes(notes: notes))
        }
    }

    // MARK: - Fetch Tags

    func fetchAllTags() async throws -> [String] {
        if networkMonitor.isConnected {
            do {
                let tags = try await linkdingService.fetchAllTags()
                cacheStorage.saveTags(tags)
                return tags
            } catch {
                // Network request failed, try cache
                if let cached = cacheStorage.loadTags() {
                    return cached
                }
                throw error
            }
        } else {
            // Offline - use cache
            if let cached = cacheStorage.loadTags() {
                return cached
            }
            throw OfflineCacheError.noCachedData
        }
    }

    // MARK: - Create Bookmark (for Share Extension)

    func createBookmark(url: String, tags: [String] = [], notes: String = "", unread: Bool = true) async throws {
        if networkMonitor.isConnected {
            do {
                try await linkdingService.createBookmark(url: url, tags: tags, notes: notes, unread: unread)
            } catch {
                // Network failed, queue for later
                queueUpdate(
                    bookmarkId: -1, // Placeholder ID for new bookmarks
                    type: .createBookmark,
                    payload: .createBookmark(url: url, tags: tags, notes: notes, unread: unread)
                )
                throw error
            }
        } else {
            // Offline, queue for later
            queueUpdate(
                bookmarkId: -1,
                type: .createBookmark,
                payload: .createBookmark(url: url, tags: tags, notes: notes, unread: unread)
            )
        }
    }

    // MARK: - Refresh Bookmark Metadata

    func refreshBookmarkMetadata(bookmarkId: Int, url: String) async throws -> (title: String?, description: String?) {
        if networkMonitor.isConnected {
            do {
                let result = try await linkdingService.refreshBookmarkMetadata(bookmarkId: bookmarkId, url: url)
                // Update cache with new metadata
                updateCachedBookmarkMetadata(bookmarkId: bookmarkId, title: result.title, description: result.description)
                return result
            } catch {
                // Network failed, queue for later
                queueUpdate(bookmarkId: bookmarkId, type: .refreshBookmark, payload: .refreshBookmark(url: url))
                throw error
            }
        } else {
            // Offline, queue for later
            queueUpdate(bookmarkId: bookmarkId, type: .refreshBookmark, payload: .refreshBookmark(url: url))
            throw OfflineCacheError.noCachedData
        }
    }

    // MARK: - Update Bookmark

    func updateBookmark(bookmarkId: Int, title: String?, description: String?, notes: String?, unread: Bool?, shared: Bool?) async throws {
        // Update cache immediately (optimistic update)
        updateCachedBookmark(bookmarkId: bookmarkId, title: title, description: description, notes: notes, unread: unread, shared: shared)

        if networkMonitor.isConnected {
            do {
                try await linkdingService.updateBookmark(bookmarkId: bookmarkId, title: title, description: description, notes: notes, unread: unread, shared: shared)
            } catch {
                // Network failed, queue for later
                queueUpdate(bookmarkId: bookmarkId, type: .updateBookmark, payload: .updateBookmark(title: title, description: description, notes: notes, unread: unread, shared: shared))
                throw error
            }
        } else {
            // Offline, queue for later
            queueUpdate(bookmarkId: bookmarkId, type: .updateBookmark, payload: .updateBookmark(title: title, description: description, notes: notes, unread: unread, shared: shared))
        }
    }

    // MARK: - Delete Bookmark

    func deleteBookmark(bookmarkId: Int) async throws {
        // Remove from cache immediately (optimistic update)
        removeCachedBookmark(bookmarkId: bookmarkId)

        if networkMonitor.isConnected {
            do {
                try await linkdingService.deleteBookmark(bookmarkId: bookmarkId)
            } catch {
                // Network failed, queue for later
                queueUpdate(bookmarkId: bookmarkId, type: .deleteBookmark, payload: .deleteBookmark)
                throw error
            }
        } else {
            // Offline, queue for later
            queueUpdate(bookmarkId: bookmarkId, type: .deleteBookmark, payload: .deleteBookmark)
        }
    }

    // MARK: - Sync Pending Updates

    func syncPendingUpdates() async {
        guard networkMonitor.isConnected else { return }
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        var pendingUpdates = cacheStorage.loadPendingUpdates()
        guard !pendingUpdates.isEmpty else { return }

        // Sort by timestamp to process in order
        pendingUpdates.sort { $0.timestamp < $1.timestamp }

        for update in pendingUpdates {
            do {
                try await processUpdate(update)
                cacheStorage.removePendingUpdate(id: update.id)
                pendingUpdateCount = cacheStorage.loadPendingUpdates().count
            } catch {
                // Increment retry count
                var updatedItem = update
                updatedItem.retryCount += 1

                if updatedItem.retryCount >= maxRetries {
                    // Remove after max retries
                    cacheStorage.removePendingUpdate(id: update.id)
                } else {
                    // Save with incremented retry count
                    var allUpdates = cacheStorage.loadPendingUpdates()
                    if let index = allUpdates.firstIndex(where: { $0.id == update.id }) {
                        allUpdates[index] = updatedItem
                        cacheStorage.savePendingUpdates(allUpdates)
                    }
                }
                pendingUpdateCount = cacheStorage.loadPendingUpdates().count
            }
        }
    }

    private func processUpdate(_ update: PendingUpdate) async throws {
        switch update.payload {
        case .setUnread(let unread):
            try await linkdingService.setUnreadStatus(bookmarkId: update.bookmarkId, unread: unread)
        case .updateTags(let tags):
            try await linkdingService.updateBookmarkTags(bookmarkId: update.bookmarkId, tags: tags)
        case .updateNotes(let notes):
            try await linkdingService.updateBookmarkNotes(bookmarkId: update.bookmarkId, notes: notes)
        case .createBookmark(let url, let tags, let notes, let unread):
            try await linkdingService.createBookmark(url: url, tags: tags, notes: notes, unread: unread)
        case .refreshBookmark(let url):
            _ = try await linkdingService.refreshBookmarkMetadata(bookmarkId: update.bookmarkId, url: url)
        case .updateBookmark(let title, let description, let notes, let unread, let shared):
            try await linkdingService.updateBookmark(bookmarkId: update.bookmarkId, title: title, description: description, notes: notes, unread: unread, shared: shared)
        case .deleteBookmark:
            try await linkdingService.deleteBookmark(bookmarkId: update.bookmarkId)
        }
    }

    // MARK: - Private Helpers

    private func queueUpdate(bookmarkId: Int, type: UpdateType, payload: UpdatePayload) {
        let update = PendingUpdate(
            bookmarkId: bookmarkId,
            updateType: type,
            payload: payload
        )
        cacheStorage.addPendingUpdate(update)
        pendingUpdateCount = cacheStorage.loadPendingUpdates().count
    }

    private func updateCachedBookmarkUnreadStatus(bookmarkId: Int, unread: Bool) {
        guard var bookmarks = cacheStorage.loadBookmarks(),
              let index = bookmarks.firstIndex(where: { $0.id == bookmarkId }) else { return }

        let old = bookmarks[index]
        let updated = Bookmark(
            id: old.id,
            url: old.url,
            title: old.title,
            description: old.description,
            notes: old.notes,
            isArchived: old.isArchived,
            unread: unread,
            shared: old.shared,
            tagNames: old.tagNames,
            dateAdded: old.dateAdded,
            dateModified: old.dateModified,
            websiteTitle: old.websiteTitle,
            websiteDescription: old.websiteDescription,
            faviconUrl: old.faviconUrl
        )
        bookmarks[index] = updated
        cacheStorage.saveBookmarks(bookmarks)
    }

    private func updateCachedBookmarkTags(bookmarkId: Int, tags: [String]) {
        guard var bookmarks = cacheStorage.loadBookmarks(),
              let index = bookmarks.firstIndex(where: { $0.id == bookmarkId }) else { return }

        let old = bookmarks[index]
        let updated = Bookmark(
            id: old.id,
            url: old.url,
            title: old.title,
            description: old.description,
            notes: old.notes,
            isArchived: old.isArchived,
            unread: old.unread,
            shared: old.shared,
            tagNames: tags,
            dateAdded: old.dateAdded,
            dateModified: old.dateModified,
            websiteTitle: old.websiteTitle,
            websiteDescription: old.websiteDescription,
            faviconUrl: old.faviconUrl
        )
        bookmarks[index] = updated
        cacheStorage.saveBookmarks(bookmarks)
    }

    private func updateCachedBookmarkNotes(bookmarkId: Int, notes: String) {
        guard var bookmarks = cacheStorage.loadBookmarks(),
              let index = bookmarks.firstIndex(where: { $0.id == bookmarkId }) else { return }

        let old = bookmarks[index]
        let updated = Bookmark(
            id: old.id,
            url: old.url,
            title: old.title,
            description: old.description,
            notes: notes,
            isArchived: old.isArchived,
            unread: old.unread,
            shared: old.shared,
            tagNames: old.tagNames,
            dateAdded: old.dateAdded,
            dateModified: old.dateModified,
            websiteTitle: old.websiteTitle,
            websiteDescription: old.websiteDescription,
            faviconUrl: old.faviconUrl
        )
        bookmarks[index] = updated
        cacheStorage.saveBookmarks(bookmarks)
    }

    private func updateCachedBookmarkMetadata(bookmarkId: Int, title: String?, description: String?) {
        guard var bookmarks = cacheStorage.loadBookmarks(),
              let index = bookmarks.firstIndex(where: { $0.id == bookmarkId }) else { return }

        let old = bookmarks[index]
        let updated = Bookmark(
            id: old.id,
            url: old.url,
            title: title ?? old.title,
            description: description ?? old.description,
            notes: old.notes,
            isArchived: old.isArchived,
            unread: old.unread,
            shared: old.shared,
            tagNames: old.tagNames,
            dateAdded: old.dateAdded,
            dateModified: old.dateModified,
            websiteTitle: old.websiteTitle,
            websiteDescription: old.websiteDescription,
            faviconUrl: old.faviconUrl
        )
        bookmarks[index] = updated
        cacheStorage.saveBookmarks(bookmarks)
    }

    private func updateCachedBookmark(bookmarkId: Int, title: String?, description: String?, notes: String?, unread: Bool?, shared: Bool?) {
        guard var bookmarks = cacheStorage.loadBookmarks(),
              let index = bookmarks.firstIndex(where: { $0.id == bookmarkId }) else { return }

        let old = bookmarks[index]
        let updated = Bookmark(
            id: old.id,
            url: old.url,
            title: title ?? old.title,
            description: description ?? old.description,
            notes: notes ?? old.notes,
            isArchived: old.isArchived,
            unread: unread ?? old.unread,
            shared: shared ?? old.shared,
            tagNames: old.tagNames,
            dateAdded: old.dateAdded,
            dateModified: old.dateModified,
            websiteTitle: old.websiteTitle,
            websiteDescription: old.websiteDescription,
            faviconUrl: old.faviconUrl
        )
        bookmarks[index] = updated
        cacheStorage.saveBookmarks(bookmarks)
    }

    private func removeCachedBookmark(bookmarkId: Int) {
        guard var bookmarks = cacheStorage.loadBookmarks() else { return }
        bookmarks.removeAll { $0.id == bookmarkId }
        cacheStorage.saveBookmarks(bookmarks)
    }
}

// MARK: - Error Types

enum OfflineCacheError: LocalizedError {
    case noCachedData
    case syncFailed

    var errorDescription: String? {
        switch self {
        case .noCachedData:
            return "No cached data available. Please connect to the internet to load bookmarks."
        case .syncFailed:
            return "Failed to sync pending changes."
        }
    }
}
