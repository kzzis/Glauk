// NoteTreeView.swift
import SwiftUI

/// 左のノートツリー。⌘\ で出し入れする。
/// 仕様書の Zen モードを壊さないよう、既定では出るが畳めば元の単一画面に戻る。
struct NoteTreeView: View {
    @EnvironmentObject var noteIndex: NoteIndex
    @EnvironmentObject var notesFolder: NotesFolder

    /// いま開いているノートの相対パス(強調表示に使う)
    var currentPath: String?
    /// 相対パスを渡す
    var onOpen: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !noteIndex.hasFolder {
                empty
            } else if noteIndex.tree.isEmpty {
                Text(noteIndex.isScanning ? "走査中…" : "ノートがありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(noteIndex.tree, children: \.children) { node in
                    row(node)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("ノートフォルダが未設定です")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("vault を選ぶ…") { notesFolder.chooseWithPanel() }
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func row(_ node: NoteNode) -> some View {
        if node.isFolder {
            Label(node.name, systemImage: "folder")
                .lineLimit(1)
        } else {
            Label(node.name, systemImage: "doc.text")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(node.id == currentPath ? Color.accentColor : Color.primary)
                .fontWeight(node.id == currentPath ? .semibold : .regular)
                // ★ Label だけだと文字の上しか反応しない。行全体を当たり判定にする。
                .contentShape(Rectangle())
                .onTapGesture { onOpen(node.id) }
        }
    }
}
