// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var noteIndex: NoteIndex
    @EnvironmentObject var notesFolder: NotesFolder
    @StateObject private var document = DocumentStore()
    @State private var showSwitcher = false
    /// ツリーの開閉は覚えておく。畳めば仕様書どおりの単一画面に戻る。
    @AppStorage("glauk.showTree") private var showTree = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    showTree.toggle()
                } label: {
                    Image(systemName: showTree ? "sidebar.left" : "sidebar.leading")
                }
                .keyboardShortcut("\\", modifiers: .command)
                .help("ツリーを出し入れ (⌘\\)")

                // ★ フォルダ未設定でも押せるようにしておく。disabled にすると
                //   ⌘O が無反応になり、「vault を指定する場所が無い」ように見える。
                //   未設定のときはスイッチャー側が「フォルダを選ぶ…」を出す。
                Button("ノートを探す…") { showSwitcher = true }
                    .keyboardShortcut("o", modifiers: .command)
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
                vaultButton
                if let error = document.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(8)

            HStack(spacing: 0) {
                if showTree {
                    NoteTreeView(currentPath: currentRelativePath) { relative in
                        guard let root = notesFolder.root else { return }
                        switchTo(path: root + "/" + relative)
                    }
                    .frame(width: 240)
                    Divider()
                }

                MarkdownTextView(text: $document.text,
                                 noteIndex: noteIndex,
                                 loadRevision: document.revision,
                                 indexRevision: noteIndex.revision)
            }
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

    /// vault が設定済みなら件数を、未設定なら選ばせる。⌘, を知らなくても辿り着けるように。
    @ViewBuilder
    private var vaultButton: some View {
        if noteIndex.hasFolder, let root = notesFolder.root {
            Button {
                notesFolder.chooseWithPanel()
            } label: {
                Label(
                    noteIndex.isScanning
                        ? "走査中…"
                        : "\((root as NSString).lastPathComponent) · \(noteIndex.names.count)",
                    systemImage: notesFolder.looksLikeObsidianVault ? "shippingbox" : "folder"
                )
                .font(.caption)
            }
            .buttonStyle(.link)
            .help(root)
        } else {
            Button("vault を選ぶ…") { notesFolder.chooseWithPanel() }
                .font(.caption)
        }
    }

    /// いま開いているファイルの、vault からの相対パス。vault の外なら nil。
    private var currentRelativePath: String? {
        guard let root = notesFolder.root, let path = document.path else { return nil }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
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
