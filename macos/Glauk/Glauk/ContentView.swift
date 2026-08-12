// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var noteIndex: NoteIndex
    @EnvironmentObject var notesFolder: NotesFolder
    @StateObject private var document = DocumentStore()
    @State private var showSwitcher = false
    /// ツリーの開閉は覚えておく。畳めば仕様書どおりの単一画面に戻る。
    @AppStorage("glauk.showTree") private var showTree = true
    /// タブは作らず、戻る操作だけを持つ(ブラウザと同じ発想)
    @State private var back: [String] = []
    @State private var forward: [String] = []
    @State private var pendingCreate: PendingNote?

    /// 未作成リンクを踏んだとき、どこに作るかを見せて確認する
    struct PendingNote: Identifiable {
        let name: String
        let path: String
        var id: String { path }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    showTree.toggle()
                } label: {
                    Image(systemName: showTree ? "sidebar.left" : "sidebar.leading")
                }
                // ★ ⌘\ はメニュー側(GlaukApp)が持つ。ここにも付けると同じキーの
                //   引き受け手が2つになる。
                .help("ノートツリーを出し入れ (⌘\\)")

                Button { goBack() } label: { Image(systemName: "chevron.left") }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(back.isEmpty)
                    .help("戻る (⌘[)")
                Button { goForward() } label: { Image(systemName: "chevron.right") }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(forward.isEmpty)
                    .help("進む (⌘])")

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
                                 indexRevision: noteIndex.revision,
                                 onOpenNote: { name in follow(link: name) })
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
        .alert(item: $pendingCreate) { pending in
            Alert(
                title: Text("「\(pending.name)」はまだありません"),
                message: Text("ここに作成します:\n\(pending.path)"),
                primaryButton: .default(Text("作成して開く")) { create(pending) },
                secondaryButton: .cancel(Text("やめる"))
            )
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

    private func switchTo(path: String, recordHistory: Bool = true) {
        showSwitcher = false
        Task {
            // ★ 自動保存は800msデバウンス。打った直後に移動すると未保存のことがある。
            //   「移動したら直前の編集が消えた」を起こさないよう、順序をここで固定する。
            await document.saveNow()
            if recordHistory, let current = document.path, current != path {
                back.append(current)
                forward.removeAll()          // 新しく辿ったら進む先は捨てる
            }
            document.open(path: path)
        }
    }

    /// `[[リンク]]` を踏んだ。あれば開く、無ければ作るか確認する。
    private func follow(link name: String) {
        guard let root = notesFolder.root else {
            // vault が無いと、どこに探せばいいか決まらない
            NSSound.beep()
            return
        }
        if let path = noteIndex.absolutePath(for: name, root: root) {
            switchTo(path: path)
            return
        }
        // Obsidian は即作成するが、Glauk は任意フォルダを扱うので確認を挟む
        pendingCreate = PendingNote(name: name, path: root + "/" + name + ".md")
    }

    private func create(_ pending: PendingNote) {
        guard GlaukFile.write(path: pending.path, contents: "# \(pending.name)\n\n") else {
            NSSound.beep()
            return
        }
        guard let root = notesFolder.root else { return }
        // 走査を待たずに索引へ足す。待つと、開いた直後のリンクがまだ「未作成」に見える。
        noteIndex.note(name: pending.name,
                       wasCreatedAt: String(pending.path.dropFirst(root.count + 1)))
        switchTo(path: pending.path)
    }

    private func goBack() {
        guard let previous = back.popLast() else { return }
        if let current = document.path { forward.append(current) }
        switchTo(path: previous, recordHistory: false)
    }

    private func goForward() {
        guard let next = forward.popLast() else { return }
        if let current = document.path { back.append(current) }
        switchTo(path: next, recordHistory: false)
    }
}
