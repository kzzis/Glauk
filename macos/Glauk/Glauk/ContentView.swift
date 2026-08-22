// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var noteIndex: NoteIndex
    @EnvironmentObject var notesFolder: NotesFolder
    @StateObject private var document = DocumentStore()
    /// ノート間の移動は全部ここを通す。ContentView は入口を並べるだけにする。
    @StateObject private var navigator: NoteNavigator
    @State private var showSwitcher = false
    /// ★ 開くまで作らない。常に生成すると SwiftTerm の初期化コストが
    ///   ⌥Space の出現時間(p95 < 300ms)に乗ってしまう。
    @State private var agent: AgentPaneController?
    @State private var showAgent = false
    /// ★ @AppStorage は Int32 を扱えないので Int で持つ
    @AppStorage("glauk.defaultAgent") private var defaultAgent = Int(AgentKind.claude.rawValue)
    /// 名前を尋ねるダイアログ(新規ノート / 新規フォルダ / 名前を変更)
    @State private var namePrompt: NamePrompt?
    @State private var nameInput = ""

    struct NamePrompt: Identifiable {
        enum Kind { case newNote, newFolder, rename }
        let id = UUID()
        let kind: Kind
        /// newNote / newFolder は作る先のフォルダ、rename は対象そのもの(いずれも絶対パス)
        let target: String

        var title: String {
            switch kind {
            case .newNote: return "新規ノート"
            case .newFolder: return "新規フォルダ"
            case .rename: return "名前を変更"
            }
        }
    }
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
                    NoteTreeView(currentPath: currentRelativePath) { action in
                        handle(action)
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

                if showAgent, let agent {
                    Divider()
                    agentPane(agent).frame(width: 420)
                }
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
        .alert(namePrompt?.title ?? "", isPresented: Binding(
            get: { namePrompt != nil },
            set: { if !$0 { namePrompt = nil } }
        ), presenting: namePrompt) { prompt in
            TextField("名前", text: $nameInput)
            Button("決定") { commit(prompt) }
            Button("やめる", role: .cancel) {}
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
        .onReceive(NotificationCenter.default.publisher(for: .glaukToggleAgent)) { _ in
            toggleAgent()
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
        HStack(spacing: 2) {
            iconButton(showTree ? "sidebar.left" : "sidebar.leading",
                       // ★ ⌘\ はメニュー側(GlaukApp)が持つ。ここにも付けると
                       //   同じキーの引き受け手が2つになる。
                       help: "ノートツリーを出し入れ (⌘\\)") { showTree.toggle() }

            Divider().frame(height: 14).padding(.horizontal, 4)

            // ★ ⌘[ / ⌘] も EditorTextView 側で拾う。ここに .keyboardShortcut を
            //   付けると、本文にフォーカスがあるとき二重に反応する。
            iconButton("chevron.left", help: "戻る (⌘[)", enabled: navigator.canGoBack) {
                Task { await navigator.goBack() }
            }
            iconButton("chevron.right", help: "進む (⌘])", enabled: navigator.canGoForward) {
                Task { await navigator.goForward() }
            }

            Divider().frame(height: 14).padding(.horizontal, 4)

            // ★ フォルダ未設定でも押せるようにしておく。disabled にすると
            //   無反応になり、「vault を指定する場所が無い」ように見える。
            //   未設定のときはスイッチャー側が「フォルダを選ぶ…」を出す。
            iconButton("magnifyingglass", help: "ノートを探す (⌘O)") { showSwitcher = true }
            iconButton("square.and.pencil", help: "新規ファイル…") { document.createWithPanel() }
            iconButton("folder", help: "ファイルを開く (⇧⌘O)") { document.openWithPanel() }

            // 仕様書の「UIクロームは無彩色」に従い、現在地はノート名だけ出す
            if let name = navigator.currentName {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 6)
                    .help(document.path ?? "")
            }
            Spacer(minLength: 8)
            if let error = document.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            vaultButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    /// ツールバーのアイコンボタン。
    /// ★ .borderless にすると押せる範囲が絵の輪郭だけになるので、
    ///   同じ大きさの枠を敷いて当たり判定を揃える。
    private func iconButton(_ symbol: String,
                            help: String,
                            enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(help)
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

    // MARK: - AIペイン

    @ViewBuilder
    private func agentPane(_ agent: AgentPaneController) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agent").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $defaultAgent) {
                    ForEach(AgentKind.allCases) { kind in
                        Text(kind.displayName).tag(Int(kind.rawValue))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
                .onChange(of: defaultAgent) { _, newValue in
                    // 切り替えは作り直し。同じ会話は引き継げない。
                    guard showAgent else { return }
                    agent.start(agent: AgentKind(rawValue: Int32(newValue)) ?? .claude,
                                cwd: workingDirectory)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            Divider()
            AgentPaneView(controller: agent)
            if let message = agent.errorMessage {
                Divider()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func toggleAgent() {
        if showAgent {
            agent?.stop()          // ★ 仕様: 閉じたら必ず終了。常駐させない
            showAgent = false
            return
        }
        let controller = agent ?? AgentPaneController()
        agent = controller
        showAgent = true
        controller.start(agent: AgentKind(rawValue: Int32(defaultAgent)) ?? .claude,
                         cwd: workingDirectory)
    }

    /// 開いているファイルのディレクトリ。未保存ならホーム。
    /// ★ / や /tmp にすると、エージェントが変な場所を触りかねない。
    private var workingDirectory: String {
        guard let path = document.path else { return NSHomeDirectory() }
        return (path as NSString).deletingLastPathComponent
    }

    // MARK: - ツリーからのファイル操作

    private func handle(_ action: NoteTreeAction) {
        guard let root = notesFolder.root else { return }
        func absolute(_ relative: String) -> String {
            relative.isEmpty ? root : root + "/" + relative
        }

        switch action {
        case .open(let relative):
            Task { await navigator.open(at: absolute(relative)) }

        case .newNote(let folder):
            nameInput = ""
            namePrompt = NamePrompt(kind: .newNote, target: absolute(folder))

        case .newFolder(let folder):
            nameInput = ""
            namePrompt = NamePrompt(kind: .newFolder, target: absolute(folder))

        case .rename(let relative):
            let path = absolute(relative)
            // 拡張子は見せない。ツリーの表示名と揃える。
            nameInput = NoteFileOps.isDirectory(path)
                ? (path as NSString).lastPathComponent
                : ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            namePrompt = NamePrompt(kind: .rename, target: path)

        case .move(let relative):
            moveWithPanel(absolute(relative))

        case .reveal(let relative):
            NoteFileOps.revealInFinder(absolute(relative))

        case .trash(let relative):
            let path = absolute(relative)
            run(affecting: path) { try NoteFileOps.trash(path); return nil }
        }
    }

    private func commit(_ prompt: NamePrompt) {
        let name = nameInput
        switch prompt.kind {
        case .newNote:
            run(affecting: nil, thenOpen: true) {
                try NoteFileOps.createNote(named: name, in: prompt.target)
            }
        case .newFolder:
            run(affecting: nil) {
                _ = try NoteFileOps.createFolder(named: name, in: prompt.target)
                return nil
            }
        case .rename:
            run(affecting: prompt.target) {
                try NoteFileOps.rename(prompt.target, to: name)
            }
        }
    }

    private func moveWithPanel(_ path: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent)
        panel.prompt = "ここへ移動"
        panel.message = "移動先のフォルダを選んでください"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run(affecting: path) { try NoteFileOps.move(path, toDirectory: url.path) }
    }

    /// ファイル操作を実行し、索引と「開いている文書」を追従させる。
    /// - Parameters:
    ///   - source: 操作の対象。開いている文書がこの中にあれば追従させる。作成なら nil。
    ///   - thenOpen: 出来上がったものを開くか(新規ノート用)。
    ///   - body: 対象の新しいパスを返す。消したときは nil。
    private func run(affecting source: String?,
                     thenOpen: Bool = false,
                     _ body: @escaping () throws -> String?) {
        Task {
            // ★ 動かす前に書き出す。自動保存は800msデバウンスなので、打った直後に
            //   名前を変えると、その数百ms分が元の場所に取り残される。
            if let source, isOpenDocument(under: source) {
                await document.saveNow()
            }
            do {
                let destination = try body()
                if let source { followOpenDocument(from: source, to: destination) }
                if thenOpen, let destination {
                    await navigator.open(at: destination)
                }
            } catch let failure as NoteFileOps.Failure {
                document.report(failure.message)
            } catch {
                document.report("操作できませんでした")
            }
            await noteIndex.refresh(root: notesFolder.root)
        }
    }

    private func isOpenDocument(under path: String) -> Bool {
        guard let open = document.path else { return false }
        return open == path || open.hasPrefix(path + "/")
    }

    /// 開いているファイルが動いた/消えたときに DocumentStore を合わせる。
    /// ★ path が古いままだと、次の自動保存が「元の場所」へ書き戻す。
    ///   ゴミ箱に入れたはずのノートが復活することになる。
    private func followOpenDocument(from source: String, to destination: String?) {
        guard let open = document.path, isOpenDocument(under: source) else { return }
        guard let destination else {
            document.close()
            return
        }
        // フォルダごと動かしたときは、中のファイルのパスも付け替える
        let moved = open == source ? destination : destination + String(open.dropFirst(source.count))
        document.rebind(to: moved)
    }

    /// いま開いているファイルの、vault からの相対パス。vault の外なら nil。
    private var currentRelativePath: String? {
        guard let root = notesFolder.root, let path = document.path else { return nil }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }
}
