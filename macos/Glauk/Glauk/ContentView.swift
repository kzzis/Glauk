// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var noteIndex: NoteIndex
    @EnvironmentObject var notesFolder: NotesFolder
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

            MarkdownTextView(text: $document.text,
                             noteIndex: noteIndex,
                             loadRevision: document.revision,
                             indexRevision: noteIndex.revision)
        }
        .frame(minWidth: 900, minHeight: 700)
        // 起動時
        .task { await noteIndex.refresh(root: notesFolder.root) }
        // 設定を変えたとき
        .onChange(of: notesFolder.root) { _, newRoot in
            Task { await noteIndex.refresh(root: newRoot) }
        }
        // Obsidian 側でノートを増やして戻ってきたときに反映する
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await noteIndex.refresh(root: notesFolder.root) }
        }
    }
}
