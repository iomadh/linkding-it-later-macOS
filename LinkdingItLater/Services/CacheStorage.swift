//
//  CacheStorage.swift
//  LinkdingosApp
//

import Foundation

final class CacheStorage {
    static let shared = CacheStorage()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Serial queue to ensure thread-safe file access
    private let queue = DispatchQueue(label: "com.dellah.linkdingos.cacheStorage", qos: .userInitiated)

    private var containerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.dellah.linkdingos")
    }

    private var bookmarksFileURL: URL? {
        containerURL?.appendingPathComponent("bookmarks.json")
    }

    private var tagsFileURL: URL? {
        containerURL?.appendingPathComponent("tags.json")
    }

    private var pendingUpdatesFileURL: URL? {
        containerURL?.appendingPathComponent("pending_updates.json")
    }

    private var metadataFileURL: URL? {
        containerURL?.appendingPathComponent("cache_metadata.json")
    }

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Bookmarks

    func saveBookmarks(_ bookmarks: [Bookmark]) {
        queue.sync {
            guard let url = bookmarksFileURL else { return }
            do {
                let data = try encoder.encode(bookmarks)
                try data.write(to: url, options: .atomic)

                // Update metadata
                var metadata = _loadMetadata() ?? CacheMetadata()
                metadata.lastSyncDate = Date()
                metadata.bookmarkCount = bookmarks.count
                _saveMetadata(metadata)
            } catch {
                print("Failed to save bookmarks cache: \(error)")
            }
        }
    }

    func loadBookmarks() -> [Bookmark]? {
        queue.sync {
            _loadBookmarks()
        }
    }

    private func _loadBookmarks() -> [Bookmark]? {
        guard let url = bookmarksFileURL,
              fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([Bookmark].self, from: data)
        } catch {
            print("Failed to load bookmarks cache: \(error)")
            return nil
        }
    }

    func updateCachedBookmark(_ bookmark: Bookmark) {
        queue.sync {
            guard var bookmarks = _loadBookmarks() else { return }
            if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                bookmarks[index] = bookmark
                _saveBookmarks(bookmarks)
            }
        }
    }

    private func _saveBookmarks(_ bookmarks: [Bookmark]) {
        guard let url = bookmarksFileURL else { return }
        do {
            let data = try encoder.encode(bookmarks)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save bookmarks cache: \(error)")
        }
    }

    func removeCachedBookmark(id: Int) {
        queue.sync {
            guard var bookmarks = _loadBookmarks() else { return }
            bookmarks.removeAll { $0.id == id }
            _saveBookmarks(bookmarks)
        }
    }

    // MARK: - Tags

    func saveTags(_ tags: [String]) {
        queue.sync {
            guard let url = tagsFileURL else { return }
            do {
                let data = try encoder.encode(tags)
                try data.write(to: url, options: .atomic)
            } catch {
                print("Failed to save tags cache: \(error)")
            }
        }
    }

    func loadTags() -> [String]? {
        queue.sync {
            guard let url = tagsFileURL,
                  fileManager.fileExists(atPath: url.path) else { return nil }
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode([String].self, from: data)
            } catch {
                print("Failed to load tags cache: \(error)")
                return nil
            }
        }
    }

    // MARK: - Pending Updates

    func savePendingUpdates(_ updates: [PendingUpdate]) {
        queue.sync {
            _savePendingUpdates(updates)
        }
    }

    private func _savePendingUpdates(_ updates: [PendingUpdate]) {
        guard let url = pendingUpdatesFileURL else { return }
        do {
            let data = try encoder.encode(updates)
            try data.write(to: url, options: .atomic)

            // Update metadata
            var metadata = _loadMetadata() ?? CacheMetadata()
            metadata.pendingUpdateCount = updates.count
            _saveMetadata(metadata)
        } catch {
            print("Failed to save pending updates: \(error)")
        }
    }

    func loadPendingUpdates() -> [PendingUpdate] {
        queue.sync {
            _loadPendingUpdates()
        }
    }

    private func _loadPendingUpdates() -> [PendingUpdate] {
        guard let url = pendingUpdatesFileURL,
              fileManager.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([PendingUpdate].self, from: data)
        } catch {
            print("Failed to load pending updates: \(error)")
            return []
        }
    }

    func addPendingUpdate(_ update: PendingUpdate) {
        queue.sync {
            var updates = _loadPendingUpdates()

            // Coalesce updates: remove older updates for the same bookmark/field
            updates.removeAll { existing in
                existing.bookmarkId == update.bookmarkId &&
                existing.updateType == update.updateType
            }

            updates.append(update)
            _savePendingUpdates(updates)
        }
    }

    func removePendingUpdate(id: UUID) {
        queue.sync {
            var updates = _loadPendingUpdates()
            updates.removeAll { $0.id == id }
            _savePendingUpdates(updates)
        }
    }

    // MARK: - Metadata

    func saveMetadata(_ metadata: CacheMetadata) {
        queue.sync {
            _saveMetadata(metadata)
        }
    }

    private func _saveMetadata(_ metadata: CacheMetadata) {
        guard let url = metadataFileURL else { return }
        do {
            let data = try encoder.encode(metadata)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save cache metadata: \(error)")
        }
    }

    func loadMetadata() -> CacheMetadata? {
        queue.sync {
            _loadMetadata()
        }
    }

    private func _loadMetadata() -> CacheMetadata? {
        guard let url = metadataFileURL,
              fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(CacheMetadata.self, from: data)
        } catch {
            print("Failed to load cache metadata: \(error)")
            return nil
        }
    }

    // MARK: - Cache Management

    func clearAllCache() {
        queue.sync {
            let urls = [bookmarksFileURL, tagsFileURL, pendingUpdatesFileURL, metadataFileURL]
            for url in urls {
                if let url = url, fileManager.fileExists(atPath: url.path) {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }
}
