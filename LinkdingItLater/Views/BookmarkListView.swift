//
//  BookmarkListView.swift
//  Linkding It Later
//

import SwiftUI

struct BookmarkListView: View {
    let filter: BookmarkFilter
    @ObservedObject var viewModel: MainViewModel
    @Binding var selectedBookmark: Bookmark?

    @State private var tagEditingBookmark: Bookmark?
    @State private var availableTags: [String] = []
    @State private var selectedDotTag: String? = nil
    @State private var editingBookmark: Bookmark?

    private var baseFilteredBookmarks: [Bookmark] {
        filter.apply(to: viewModel.bookmarks)
    }

    private var availableDotTags: [String] {
        let allTags = baseFilteredBookmarks.flatMap { $0.tagNames }
        let dotTags = Set(allTags.filter { $0.hasPrefix(".") })
        return dotTags.sorted()
    }

    private var filteredBookmarks: [Bookmark] {
        if let dotTag = selectedDotTag {
            return baseFilteredBookmarks.filter { $0.tagNames.contains(dotTag) }
        }
        return baseFilteredBookmarks
    }

    var body: some View {
        Group {
            switch viewModel.viewState {
            case .idle:
                emptyStateView
            case .loading:
                loadingView
            case .loaded:
                VStack(spacing: 0) {
                    OfflineStatusBanner(
                        isOffline: viewModel.isOffline,
                        pendingUpdateCount: viewModel.pendingUpdateCount,
                        lastSyncDate: viewModel.lastRefreshDate,
                        isSyncing: viewModel.isSyncing,
                        onSyncTapped: {
                            Task { await viewModel.syncPendingUpdates() }
                        }
                    )

                    if filter.showDotTagSubFilters && !availableDotTags.isEmpty {
                        dotTagPillRow
                            .padding(.vertical, 8)
                    }

                    if filteredBookmarks.isEmpty {
                        allReadView
                    } else {
                        bookmarkListView(filteredBookmarks)
                    }
                }
            case .error(let message):
                errorView(message)
            }
        }
        .navigationTitle(filter.displayName)
        .searchable(text: searchBinding, prompt: "Search bookmarks")
        .sheet(item: $tagEditingBookmark) { bookmark in
            TagEditingView(
                bookmarkId: bookmark.id,
                initialTags: bookmark.tagNames,
                availableTags: availableTags,
                onSave: { newTags in
                    Task {
                        try? await OfflineCacheManager.shared.updateBookmarkTags(bookmarkId: bookmark.id, tags: newTags)
                        viewModel.updateBookmarkTags(id: bookmark.id, tags: newTags)
                    }
                }
            )
            .frame(minWidth: 400, minHeight: 300)
        }
        .sheet(item: $editingBookmark) { bookmark in
            BookmarkEditView(
                bookmark: bookmark,
                availableTags: availableTags,
                onSave: { title, description, notes, tags, unread, shared in
                    Task {
                        await viewModel.updateBookmark(id: bookmark.id, title: title, description: description, notes: notes, unread: unread, shared: shared)
                        viewModel.updateBookmarkTags(id: bookmark.id, tags: tags)
                    }
                },
                onDelete: {
                    Task {
                        await viewModel.deleteBookmark(id: bookmark.id)
                    }
                }
            )
            .frame(minWidth: 480, minHeight: 600)
        }
        .onAppear {
            if viewModel.isConfigured && viewModel.bookmarks.isEmpty {
                Task { await viewModel.loadBookmarks() }
            }
        }
    }

    // Bridge the search to the filter's search via filter state
    // For macOS the toolbar search filters the current bookmark list
    @State private var searchText = ""
    private var searchBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { searchText = $0 }
        )
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Server Configured", systemImage: "server.rack")
        } description: {
            Text("Configure your Linkding server in Settings to get started.")
        } actions: {
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var loadingView: some View {
        ProgressView("Loading bookmarks...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var allReadView: some View {
        ContentUnavailableView {
            Label("All Caught Up!", systemImage: "checkmark.circle")
        } description: {
            Text("No bookmarks in \(filter.displayName).")
        } actions: {
            Button("Refresh") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func bookmarkListView(_ bookmarks: [Bookmark]) -> some View {
        List(bookmarks, selection: $selectedBookmark) { bookmark in
            BookmarkRowView(bookmark: bookmark)
                .tag(bookmark)
                .contextMenu {
                    bookmarkContextMenu(for: bookmark)
                }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func bookmarkContextMenu(for bookmark: Bookmark) -> some View {
        Button("Mark as Read") {
            Task { await viewModel.toggleReadStatus(id: bookmark.id) }
        }

        Button(bookmark.tagNames.contains("!star") ? "Unstar" : "Star") {
            Task { await viewModel.toggleStar(id: bookmark.id) }
        }

        Divider()

        Button("Edit Tags...") {
            Task {
                availableTags = await viewModel.fetchAvailableTags()
                tagEditingBookmark = bookmark
            }
        }

        Button("Edit Bookmark...") {
            Task {
                availableTags = await viewModel.fetchAvailableTags()
                editingBookmark = bookmark
            }
        }

        Button("Refresh from Website") {
            Task { await viewModel.refreshBookmark(id: bookmark.id) }
        }

        Divider()

        Button("Open in Browser") {
            if let url = URL(string: bookmark.url) {
                NSWorkspace.shared.open(url)
            }
        }

        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bookmark.url, forType: .string)
        }

        Divider()

        Button("Delete", role: .destructive) {
            Task {
                await viewModel.deleteBookmark(id: bookmark.id)
                if selectedBookmark?.id == bookmark.id {
                    selectedBookmark = nil
                }
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            HStack(spacing: 16) {
                Button("Retry") {
                    Task { await viewModel.loadBookmarks() }
                }
                .buttonStyle(.bordered)

                Button("Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var dotTagPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SubFilterPill(
                    title: "All",
                    isSelected: selectedDotTag == nil,
                    onTap: { selectedDotTag = nil }
                )

                ForEach(availableDotTags, id: \.self) { tag in
                    SubFilterPill(
                        title: String(tag.dropFirst()),
                        isSelected: selectedDotTag == tag,
                        onTap: { selectedDotTag = tag }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

struct SubFilterPill: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}
