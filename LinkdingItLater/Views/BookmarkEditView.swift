//
//  BookmarkEditView.swift
//  Linkding It Later
//

import SwiftUI

struct BookmarkEditView: View {
    let bookmark: Bookmark
    let availableTags: [String]
    let onSave: (String, String, String, [String], Bool, Bool) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var notes: String
    @State private var tags: [String]
    @State private var unread: Bool
    @State private var shared: Bool
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false
    @State private var newTagText = ""
    @FocusState private var isTagFieldFocused: Bool

    private let quickSelectTags = [
        "!action", "!fiction", "!laptop", "!listen", "!long",
        "!reply", "!research", "!spoilers", "!watch", "!work"
    ]

    init(bookmark: Bookmark, availableTags: [String] = [], onSave: @escaping (String, String, String, [String], Bool, Bool) -> Void, onDelete: @escaping () -> Void) {
        self.bookmark = bookmark
        self.availableTags = availableTags
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: bookmark.title)
        _description = State(initialValue: bookmark.description)
        _notes = State(initialValue: bookmark.notes)
        _tags = State(initialValue: bookmark.tagNames)
        _unread = State(initialValue: bookmark.unread)
        _shared = State(initialValue: bookmark.shared)
    }

    private var filteredSuggestions: [String] {
        guard !newTagText.isEmpty else { return [] }
        let lowercasedInput = newTagText.lowercased()
        return availableTags
            .filter { $0.lowercased().hasPrefix(lowercasedInput) && !tags.contains($0) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }

                Section("Description") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                Section("Tags") {
                    if !tags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(tags, id: \.self) { tag in
                                TagPill(tag: tag) {
                                    withAnimation { tags.removeAll { $0 == tag } }
                                }
                            }
                        }
                    }

                    TextField("Add tag...", text: $newTagText)
                        .autocorrectionDisabled()
                        .focused($isTagFieldFocused)
                        .onSubmit {
                            addTag(newTagText)
                            isTagFieldFocused = true
                        }

                    if !filteredSuggestions.isEmpty {
                        ForEach(filteredSuggestions, id: \.self) { suggestion in
                            Button {
                                addTag(suggestion)
                            } label: {
                                HStack {
                                    Image(systemName: "tag").foregroundColor(.secondary)
                                    Text(suggestion).foregroundColor(.primary)
                                }
                            }
                        }
                    }

                    FlowLayout(spacing: 8) {
                        ForEach(quickSelectTags, id: \.self) { tag in
                            QuickSelectPill(tag: tag, isSelected: tags.contains(tag)) {
                                toggleQuickTag(tag)
                            }
                        }
                    }
                }

                Section {
                    Toggle("Mark as unread", isOn: $unread)
                    Toggle("Share", isOn: $shared)
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Bookmark", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Bookmark")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        onSave(title, description, notes, tags, unread, shared)
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Delete Bookmark?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func toggleQuickTag(_ tag: String) {
        withAnimation {
            if tags.contains(tag) { tags.removeAll { $0 == tag } }
            else { tags.append(tag) }
        }
    }

    private func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !tags.contains(trimmed) else {
            newTagText = ""
            return
        }
        withAnimation { tags.append(trimmed) }
        newTagText = ""
    }
}
