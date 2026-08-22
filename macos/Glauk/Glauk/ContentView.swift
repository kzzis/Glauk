// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var noteIndex: NoteIndex
    @EnvironmentObject var notesFolder: NotesFolder
    @StateObject private var document = DocumentStore()
    /// ノート間の移動は全部ここを通す。ContentView は入口を並べるだけにする。
    @StateObject private var navigator: NoteNavigator
    @State private var showSwitcher = false
    /// ツリーの開閉は覚えておく。畳めば仕様書どおりの単一画面に戻る。
    @AppStorage("glauk.showTree") private var showTree = true

    init(noteIndex: NoteIndex, notesFolder: NotesFolder) {
        let store = DocumentStore()
        _document = StateObject(wrappedValue: store)
        _navigator = StateObject(wrappedValue: NoteNavigator(store: store,
                                                             index: noteIndex,
                                                             folder: notesFolder))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                if showTree {
                    NoteTreeView(currentPath: currentRelativePath) { relative in
                        guard let root = notesFolder.root else { return }
                        Task { await navigator.open(at: root + "/" + relative) }
                    }
                    .frame(width: 240)
                    Divider()
                }

                MarkdownTextView(text: $document.text,
                                 noteIndex: noteIndex,
                                 loadRevision: document.revision,
                                 indexRevision: noteIndex.revision,
                                 onOpenNote: { name in
                                     Task { await navigator.follow(link: name) }
                                 })
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .overlay {
            if showSwitcher {
                NoteSwitcherView(
                    onOpen: { path in
                        showSwitcher = false
                        Task { await navigator.open(at: path) }
                    },
                    onCancel: { showSwitcher = false }
                )
            }
        }
        // ★ どこに作るかを必ず見せる。任意のフォルダを扱う以上、
        //   「気づいたら変な場所にファイルができていた」を防ぐ。
        .alert(item: $navigator.pendingCreate) { pending in
            Alert(
                title: Text("「\(pending.name)」を作成しますか?"),
                message: Text("作成先: \(pending.relativePath)"),
                primaryButton: .default(Text("作成して開く")) {
                    Task { await navigator.createAndOpen(name: pending.name) }
                },
                secondaryButton: .cancel(Text("やめる"))
            )
        }
        // ⌘[ / ⌘] とマウスの戻るボタンは EditorTextView が拾って投げてくる
        .onReceive(NotificationCenter.default.publisher(for: .glaukGoBack)) { _ in
            Task { await navigator.goBack() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .glaukGoForward)) { _ in
            Task { await navigator.goForward() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .glaukFindNote)) { _ in
            showSwitcher = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .glaukOpenFile)) { _ in
            document.openWithPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .glaukNewFile)) { _ in
            document.createWithPanel()
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

    private var toolbar: some View {
        HStack {
            Button {
                showTree.toggle()
            } label: {
                Image(systemName: showTree ? "sidebar.left" : "sidebar.leading")
            }
            // ★ ⌘\ はメニュー側(GlaukApp)が持つ。ここにも付けると同じキーの
            //   引き受け手が2つになる。
            .help("ノートツリーを出し入れ (⌘\\)")

            // ★ ⌘[ / ⌘] も EditorTextView 側で拾う。ここに .keyboardShortcut を
            //   付けると、本文にフォーカスがあるとき二重に反応する。
            Button { Task { await navigator.goBack() } } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!navigator.canGoBack)
            .help("戻る (⌘[)")
            Button { Task { await navigator.goForward() } } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!navigator.canGoForward)
            .help("進む (⌘])")

            // ★ フォルダ未設定でも押せるようにしておく。disabled にすると
            //   ⌘O が無反応になり、「vault を指定する場所が無い」ように見える。
            //   未設定のときはスイッチャー側が「フォルダを選ぶ…」を出す。
            Button("ノートを探す…") { showSwitcher = true }
            Button("開く…") { document.openWithPanel() }
            Button("新規…") { document.createWithPanel() }

            // 仕様書の「UIクロームは無彩色」に従い、現在地はノート名だけ出す
            if let name = navigator.currentName {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(document.path ?? "")
            }
            Spacer()
            vaultButton
            if let error = document.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(8)
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
}
