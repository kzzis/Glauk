// ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var noteIndex = NoteIndex()
    @StateObject private var document = DocumentStore()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("開く…") { document.openWithPanel() }
                Button("新規…") { document.createWithPanel() }
                if let path = document.path {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                if let error = document.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(8)

            MarkdownTextView(text: $document.text, noteIndex: noteIndex, loadRevision: document.revision)
        }
        .frame(minWidth: 900, minHeight: 700)
        .onAppear { noteIndex.loadMock() }
    }
}
