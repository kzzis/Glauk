// SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var notesFolder: NotesFolder
    @EnvironmentObject var noteIndex: NoteIndex

    var body: some View {
        Form {
            Section("ノートフォルダ") {
                if let root = notesFolder.root {
                    Text(root)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.head)
                    if notesFolder.looksLikeObsidianVault {
                        Label("Obsidian の vault を検出しました", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if noteIndex.isScanning {
                        Label("走査中…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(noteIndex.names.count) 件のノート")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("変更…") { notesFolder.chooseWithPanel() }
                        Button("解除") { notesFolder.clear() }
                    }
                } else {
                    Text("未設定(単一ファイル編集のみ)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("フォルダを選ぶ…") { notesFolder.chooseWithPanel() }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
    }
}
