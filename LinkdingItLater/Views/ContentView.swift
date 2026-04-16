//
//  ContentView.swift
//  Linkding It Later
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @State private var selectedFilter: BookmarkFilter?
    @State private var selectedBookmark: Bookmark?
    @State private var showingAddBookmark = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                viewModel: viewModel,
                selectedFilter: $selectedFilter,
                onAddBookmark: { showingAddBookmark = true }
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } content: {
            if let filter = selectedFilter {
                BookmarkListView(
                    filter: filter,
                    viewModel: viewModel,
                    selectedBookmark: $selectedBookmark
                )
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 500)
            } else {
                ContentUnavailableView(
                    "Select a Filter",
                    systemImage: "sidebar.left",
                    description: Text("Choose a filter from the sidebar to view bookmarks.")
                )
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 500)
            }
        } detail: {
            if let bookmark = selectedBookmark {
                BookmarkDetailView(
                    bookmark: bookmark,
                    isActive: true,
                    onMarkAsRead: {
                        viewModel.removeBookmark(id: bookmark.id)
                        selectedBookmark = nil
                    },
                    onTagsUpdated: { tags in
                        viewModel.updateBookmarkTags(id: bookmark.id, tags: tags)
                    },
                    onNotesUpdated: { notes in
                        viewModel.updateBookmarkNotes(id: bookmark.id, notes: notes)
                    }
                )
            } else {
                ContentUnavailableView(
                    "No Bookmark Selected",
                    systemImage: "bookmark",
                    description: Text("Select a bookmark from the list to view it.")
                )
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .sheet(isPresented: $showingAddBookmark) {
            AddBookmarkView {
                Task {
                    await viewModel.refresh()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addBookmark)) { _ in
            showingAddBookmark = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshBookmarks)) { _ in
            Task {
                await viewModel.refresh()
            }
        }
        .onAppear {
            // Pre-select the first filter
            if selectedFilter == nil {
                selectedFilter = SettingsManager.shared.bookmarkFilters.sorted { $0.order < $1.order }.first
            }
            if viewModel.isConfigured && viewModel.bookmarks.isEmpty {
                Task {
                    await viewModel.loadBookmarks()
                }
            }
        }
    }
}
