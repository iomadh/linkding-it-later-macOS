//
//  SFSymbolPickerView.swift
//  Linkding It Later
//

import SwiftUI

struct SFSymbolPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedSymbol: String
    @State private var searchText = ""

    private let symbols = [
        "star", "star.fill", "heart", "heart.fill", "bookmark", "bookmark.fill",
        "tag", "tag.fill", "flag", "flag.fill", "pin", "pin.fill",
        "doc", "doc.fill", "doc.text", "doc.richtext", "newspaper", "magazine",
        "book", "book.fill", "books.vertical", "text.book.closed",
        "envelope", "envelope.fill", "envelope.open", "envelope.open.fill",
        "message", "message.fill", "bubble.left", "bubble.right",
        "play", "play.fill", "video", "video.fill", "music.note", "headphones",
        "tv", "tv.fill", "gamecontroller", "gamecontroller.fill",
        "folder", "folder.fill", "tray", "tray.full", "archivebox", "archivebox.fill",
        "square.grid.2x2", "list.bullet", "checklist",
        "sportscourt", "figure.run", "bicycle", "car", "airplane",
        "globe", "network", "wifi", "antenna.radiowaves.left.and.right",
        "server.rack", "cpu", "desktopcomputer", "laptopcomputer",
        "leaf", "leaf.fill", "sun.max", "moon", "cloud", "bolt",
        "lightbulb", "lightbulb.fill", "wrench", "hammer", "paintbrush",
        "camera", "photo", "map", "location", "house", "building.2"
    ]

    private var filteredSymbols: [String] {
        if searchText.isEmpty { return symbols }
        return symbols.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 16) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button {
                            selectedSymbol = symbol
                            dismiss()
                        } label: {
                            Image(systemName: symbol)
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .background(symbol == selectedSymbol ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .searchable(text: $searchText, prompt: "Search symbols")
            .navigationTitle("Choose Icon")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
