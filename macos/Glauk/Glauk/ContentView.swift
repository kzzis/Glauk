// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var noteIndex: NoteIndex
    @EnvironmentObject var notesFolder: NotesFolder
    @StateObject private var document = DocumentStore()
    @State private var showSwitcher = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("ノートを探す…") { showSwitcher = true }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(!noteIndex.hasFolder)
                Button("開く…") { document.openWithPanel() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
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
        .overlay {
            if showSwitcher {
                NoteSwitcherView(
                    onOpen: { path in switchTo(path: path) },
                    onCancel: { showSwitcher = false }
                )
            }
        }
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

    private func switchTo(path: String) {
        showSwitcher = false
        Task {
            // ★ 自動保存は800msデバウンス。打った直後に移動すると未保存のことがある。
            //   「移動したら直前の編集が消えた」を起こさないよう、順序をここで固定する。
            await document.saveNow()
            document.open(path: path)
        }
    }
}
