//
//  SidebarView.swift
//  Linkding It Later
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var settings = SettingsManager.shared
    @Binding var selectedFilter: BookmarkFilter?
    let onAddBookmark: () -> Void

    @State private var refreshTrigger = false

    private var visibleFilters: [BookmarkFilter] {
        let sorted = settings.bookmarkFilters.sorted { $0.order < $1.order }
        if settings.hideEmptyFilters {
            return sorted.filter { $0.count(in: viewModel.bookmarks) > 0 }
        }
        return sorted
    }

    var body: some View {
        VStack(spacing: 0) {
            // Offline status bar
            if viewModel.isOffline || viewModel.pendingUpdateCount > 0 || viewModel.isSyncing {
                HStack(spacing: 6) {
                    if viewModel.isOffline {
                        Image(systemName: "wifi.slash")
                            .font(.caption)
                        Text("Offline")
                            .font(.caption.weight(.medium))
                    }
                    if viewModel.pendingUpdateCount > 0 {
                        Text("\(viewModel.pendingUpdateCount) pending")
                            .font(.caption)
                    }
                    if viewModel.isSyncing {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Syncing...")
                            .font(.caption)
                    }
                    Spacer()
                    if !viewModel.isOffline && viewModel.pendingUpdateCount > 0 && !viewModel.isSyncing {
                        Button {
                            Task { await viewModel.syncPendingUpdates() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(viewModel.isOffline ? Color.orange : Color.secondary)
            }

            List(visibleFilters, selection: $selectedFilter) { filter in
                HStack {
                    Label(filter.displayName, systemImage: filter.icon)
                    Spacer()
                    Text("\(filter.count(in: viewModel.bookmarks))")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .tag(filter)
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Feeds")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    settings.hideEmptyFilters.toggle()
                } label: {
                    Image(systemName: settings.hideEmptyFilters ? "eye.slash" : "eye")
                }
                .help(settings.hideEmptyFilters ? "Show empty filters" : "Hide empty filters")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh bookmarks")
                .keyboardShortcut("r", modifiers: .command)
            }

            ToolbarItem(placement: .automatic) {
                Button(action: onAddBookmark) {
                    Image(systemName: "plus")
                }
                .help("Add bookmark")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            refreshTrigger.toggle()
        }
    }
}
