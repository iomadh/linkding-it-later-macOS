//
//  FilterListView.swift
//  Linkding It Later
//

import SwiftUI

struct FilterListView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var editingFilter: BookmarkFilter?
    @State private var showingAddFilter = false

    private var sortedFilters: [BookmarkFilter] {
        settings.bookmarkFilters.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            ForEach(sortedFilters) { filter in
                HStack {
                    Image(systemName: filter.icon)
                        .foregroundColor(.accentColor)
                        .frame(width: 30)

                    VStack(alignment: .leading) {
                        Text(filter.displayName).font(.body)
                        if !filter.searchQuery.isEmpty {
                            Text(filter.searchQuery)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { editingFilter = filter }
            }
            .onDelete(perform: deleteFilters)
            .onMove(perform: moveFilters)
        }
        .navigationTitle("Filters")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingAddFilter = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add filter")
            }
        }
        .contextMenu(forSelectionType: BookmarkFilter.self) { selectedFilters in
            if let filter = selectedFilters.first {
                Button("Edit Filter...") {
                    editingFilter = filter
                }
                Button("Delete Filter", role: .destructive) {
                    deleteFilter(filter)
                }
            }
        } primaryAction: { selectedFilters in
            if let filter = selectedFilters.first {
                editingFilter = filter
            }
        }
        .sheet(item: $editingFilter) { filter in
            FilterEditView(filter: filter, onSave: updateFilter, onDelete: deleteFilter)
                .frame(minWidth: 400, minHeight: 350)
        }
        .sheet(isPresented: $showingAddFilter) {
            FilterEditView(filter: nil, onSave: addFilter, onDelete: nil)
                .frame(minWidth: 400, minHeight: 350)
        }
    }

    private func deleteFilters(at offsets: IndexSet) {
        var filters = sortedFilters
        filters.remove(atOffsets: offsets)
        reorderFilters(&filters)
        settings.bookmarkFilters = filters
    }

    private func moveFilters(from source: IndexSet, to destination: Int) {
        var filters = sortedFilters
        filters.move(fromOffsets: source, toOffset: destination)
        reorderFilters(&filters)
        settings.bookmarkFilters = filters
    }

    private func reorderFilters(_ filters: inout [BookmarkFilter]) {
        for index in filters.indices {
            filters[index].order = index
        }
    }

    private func addFilter(_ filter: BookmarkFilter) {
        var newFilter = filter
        newFilter.order = settings.bookmarkFilters.count
        settings.bookmarkFilters.append(newFilter)
    }

    private func updateFilter(_ filter: BookmarkFilter) {
        if let index = settings.bookmarkFilters.firstIndex(where: { $0.id == filter.id }) {
            settings.bookmarkFilters[index] = filter
        }
    }

    private func deleteFilter(_ filter: BookmarkFilter) {
        settings.bookmarkFilters.removeAll { $0.id == filter.id }
    }
}
