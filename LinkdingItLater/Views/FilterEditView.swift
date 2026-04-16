//
//  FilterEditView.swift
//  Linkding It Later
//

import SwiftUI

struct FilterEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var searchQuery: String
    @State private var selectedIcon: String
    @State private var excludeExclamationTags: Bool
    @State private var showDotTagSubFilters: Bool
    @State private var showingIconPicker = false

    private let existingFilter: BookmarkFilter?
    private let onSave: (BookmarkFilter) -> Void
    private let onDelete: ((BookmarkFilter) -> Void)?

    private var isNewFilter: Bool { existingFilter == nil }

    init(filter: BookmarkFilter?, onSave: @escaping (BookmarkFilter) -> Void, onDelete: ((BookmarkFilter) -> Void)?) {
        self.existingFilter = filter
        self.onSave = onSave
        self.onDelete = onDelete
        _displayName = State(initialValue: filter?.displayName ?? "")
        _searchQuery = State(initialValue: filter?.searchQuery ?? "")
        _selectedIcon = State(initialValue: filter?.icon ?? "tag")
        _excludeExclamationTags = State(initialValue: filter?.excludeExclamationTags ?? false)
        _showDotTagSubFilters = State(initialValue: filter?.showDotTagSubFilters ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Filter Details") {
                    TextField("Display Name", text: $displayName)
                    TextField("Search Query", text: $searchQuery, prompt: Text("#tag word \"phrase\""))
                        .autocorrectionDisabled()
                    Toggle("Exclude ! tags", isOn: $excludeExclamationTags)
                    Toggle("Show . tag sub-filters", isOn: $showDotTagSubFilters)
                }

                Section("Icon") {
                    Button {
                        showingIconPicker = true
                    } label: {
                        HStack {
                            Image(systemName: selectedIcon)
                                .font(.title2)
                                .frame(width: 40)
                            Text(selectedIcon).foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                    }
                }

                if !isNewFilter, let filter = existingFilter {
                    Section {
                        Button("Delete Filter", role: .destructive) {
                            onDelete?(filter)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNewFilter ? "Add Filter" : "Edit Filter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let filter = BookmarkFilter(
                            id: existingFilter?.id ?? UUID(),
                            displayName: displayName.trimmingCharacters(in: .whitespaces),
                            searchQuery: searchQuery.trimmingCharacters(in: .whitespaces),
                            icon: selectedIcon,
                            order: existingFilter?.order ?? 0,
                            excludeExclamationTags: excludeExclamationTags,
                            showDotTagSubFilters: showDotTagSubFilters
                        )
                        onSave(filter)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                SFSymbolPickerView(selectedSymbol: $selectedIcon)
                    .frame(minWidth: 400, minHeight: 400)
            }
        }
    }

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
