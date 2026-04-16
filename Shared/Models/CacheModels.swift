//
//  CacheModels.swift
//  LinkdingosApp
//

import Foundation

// MARK: - Update Type

enum UpdateType: String, Codable {
    case setUnread
    case updateTags
    case updateNotes
    case createBookmark
    case refreshBookmark
    case updateBookmark
    case deleteBookmark
}

// MARK: - Update Payload

enum UpdatePayload: Codable {
    case setUnread(unread: Bool)
    case updateTags(tags: [String])
    case updateNotes(notes: String)
    case createBookmark(url: String, tags: [String], notes: String, unread: Bool)
    case refreshBookmark(url: String)
    case updateBookmark(title: String?, description: String?, notes: String?, unread: Bool?, shared: Bool?)
    case deleteBookmark

    private enum CodingKeys: String, CodingKey {
        case type
        case unread
        case tags
        case notes
        case url
        case title
        case description
        case shared
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .setUnread(let unread):
            try container.encode("setUnread", forKey: .type)
            try container.encode(unread, forKey: .unread)
        case .updateTags(let tags):
            try container.encode("updateTags", forKey: .type)
            try container.encode(tags, forKey: .tags)
        case .updateNotes(let notes):
            try container.encode("updateNotes", forKey: .type)
            try container.encode(notes, forKey: .notes)
        case .createBookmark(let url, let tags, let notes, let unread):
            try container.encode("createBookmark", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(tags, forKey: .tags)
            try container.encode(notes, forKey: .notes)
            try container.encode(unread, forKey: .unread)
        case .refreshBookmark(let url):
            try container.encode("refreshBookmark", forKey: .type)
            try container.encode(url, forKey: .url)
        case .updateBookmark(let title, let description, let notes, let unread, let shared):
            try container.encode("updateBookmark", forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(notes, forKey: .notes)
            try container.encodeIfPresent(unread, forKey: .unread)
            try container.encodeIfPresent(shared, forKey: .shared)
        case .deleteBookmark:
            try container.encode("deleteBookmark", forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "setUnread":
            let unread = try container.decode(Bool.self, forKey: .unread)
            self = .setUnread(unread: unread)
        case "updateTags":
            let tags = try container.decode([String].self, forKey: .tags)
            self = .updateTags(tags: tags)
        case "updateNotes":
            let notes = try container.decode(String.self, forKey: .notes)
            self = .updateNotes(notes: notes)
        case "createBookmark":
            let url = try container.decode(String.self, forKey: .url)
            let tags = try container.decode([String].self, forKey: .tags)
            let notes = try container.decode(String.self, forKey: .notes)
            let unread = try container.decode(Bool.self, forKey: .unread)
            self = .createBookmark(url: url, tags: tags, notes: notes, unread: unread)
        case "refreshBookmark":
            let url = try container.decode(String.self, forKey: .url)
            self = .refreshBookmark(url: url)
        case "updateBookmark":
            let title = try container.decodeIfPresent(String.self, forKey: .title)
            let description = try container.decodeIfPresent(String.self, forKey: .description)
            let notes = try container.decodeIfPresent(String.self, forKey: .notes)
            let unread = try container.decodeIfPresent(Bool.self, forKey: .unread)
            let shared = try container.decodeIfPresent(Bool.self, forKey: .shared)
            self = .updateBookmark(title: title, description: description, notes: notes, unread: unread, shared: shared)
        case "deleteBookmark":
            self = .deleteBookmark
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown update type: \(type)"
            )
        }
    }
}

// MARK: - Pending Update

struct PendingUpdate: Codable, Identifiable {
    let id: UUID
    let bookmarkId: Int
    let updateType: UpdateType
    let timestamp: Date
    let payload: UpdatePayload
    var retryCount: Int

    init(
        id: UUID = UUID(),
        bookmarkId: Int,
        updateType: UpdateType,
        timestamp: Date = Date(),
        payload: UpdatePayload,
        retryCount: Int = 0
    ) {
        self.id = id
        self.bookmarkId = bookmarkId
        self.updateType = updateType
        self.timestamp = timestamp
        self.payload = payload
        self.retryCount = retryCount
    }
}

// MARK: - Cache Metadata

struct CacheMetadata: Codable {
    var lastSyncDate: Date?
    var bookmarkCount: Int
    var pendingUpdateCount: Int

    init(
        lastSyncDate: Date? = nil,
        bookmarkCount: Int = 0,
        pendingUpdateCount: Int = 0
    ) {
        self.lastSyncDate = lastSyncDate
        self.bookmarkCount = bookmarkCount
        self.pendingUpdateCount = pendingUpdateCount
    }
}
