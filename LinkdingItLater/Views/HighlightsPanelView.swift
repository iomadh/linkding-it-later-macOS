//
//  HighlightsPanelView.swift
//  Linkding It Later
//

import SwiftUI

struct HighlightsPanelView: View {
    let bookmarkId: Int
    @Binding var highlights: [Highlight]
    let onChanged: () -> Void
    @State private var editingHighlight: Highlight?
    @State private var editNoteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Highlights")
                    .font(.headline)
                Spacer()
                if !highlights.isEmpty {
                    Text("\(highlights.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if highlights.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "highlighter")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Highlights")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Select text in reader mode to create highlights.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(highlights) { highlight in
                        HighlightRowView(highlight: highlight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editNoteText = highlight.note ?? ""
                                editingHighlight = highlight
                            }
                    }
                    .onDelete(perform: deleteHighlights)
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $editingHighlight) { highlight in
            EditHighlightNoteView(
                highlight: highlight,
                noteText: $editNoteText,
                onSave: { note in
                    HighlightStorage.shared.updateNote(id: highlight.id, bookmarkId: bookmarkId, note: note)
                    highlights = HighlightStorage.shared.load(bookmarkId: bookmarkId)
                    editingHighlight = nil
                    onChanged()
                },
                onDelete: {
                    HighlightStorage.shared.delete(id: highlight.id, bookmarkId: bookmarkId)
                    highlights = HighlightStorage.shared.load(bookmarkId: bookmarkId)
                    editingHighlight = nil
                    onChanged()
                }
            )
            .frame(minWidth: 400, minHeight: 300)
        }
    }

    private func deleteHighlights(at offsets: IndexSet) {
        for idx in offsets {
            HighlightStorage.shared.delete(id: highlights[idx].id, bookmarkId: bookmarkId)
        }
        highlights = HighlightStorage.shared.load(bookmarkId: bookmarkId)
        onChanged()
    }
}

private struct HighlightRowView: View {
    let highlight: Highlight

    private var displayText: AttributedString {
        if let md = highlight.markdownText,
           let attributed = try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(highlight.selectedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.25))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.yellow.opacity(0.6), lineWidth: 1)
                )

            if let note = highlight.note, !note.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 2)
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)
            }

            Text(highlight.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)
        }
        .padding(.vertical, 4)
    }
}

struct EditHighlightNoteView: View {
    let highlight: Highlight
    @Binding var noteText: String
    let onSave: (String) -> Void
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Edit Highlight")
                    .font(.headline)
                Spacer()
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            Text(highlight.selectedText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.25))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.yellow.opacity(0.6), lineWidth: 1))

            TextEditor(text: $noteText)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { onSave(noteText) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .confirmationDialog("Delete this highlight?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .padding()
    }
}
