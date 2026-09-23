import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var noteIndex: NoteIndex
    @EnvironmentObject var notesFolder: NotesFolder
    @StateObject private var document = DocumentStore()
    @StateObject private var navigator: NoteNavigator
    @State private var showSwitcher = false
    @StateObject private var watcher = FileWatcher()
    /// ウィンドウ表示を遅らせないよう、SwiftTerm はペインを開くまで生成しない。
    @State private var agent: AgentPaneController?
    @State private var showAgent = false
    /// @AppStorage は Int32 を扱えないので Int で持つ
    @AppStorage("glauk.defaultAgent") private var defaultAgent = Int(AgentKind.claude.rawValue)
    @AppStorage(ThemePreference.storageKey) private var theme = ThemePreference.auto.rawValue
    @AppStorage(GlaukTheme.storageKey) private var palette = GlaukTheme.paper.rawValue
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
    @AppStorage("glauk.showTree") private var showTree = true

    init(noteIndex: NoteIndex, notesFolder: NotesFolder) {
        let store = DocumentStore()
        _document = StateObject(wrappedValue: store)
        _navigator = StateObject(wrappedValue: NoteNavigator(store: store,
                                                             index: noteIndex,
                                                             folder: notesFolder))
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if showTree {
                    sidebar
                        .frame(width: min(320, max(252, geometry.size.width * 0.23)))
                    Rectangle()
                        .fill(ThemeToken.shellDivider)
                        .frame(width: 1)
                }

                VStack(spacing: 0) {
                    toolbar
                    Rectangle()
                        .fill(ThemeToken.shellDivider)
                        .frame(height: 1)
                    HStack(spacing: 0) {
                        editor
                        if showAgent, let agent {
                            Rectangle()
                                .fill(ThemeToken.shellDivider)
                                .frame(width: 1)
                            AgentPaneBody(controller: agent,
                                          selectedAgent: $defaultAgent,
                                          onSwitch: { kind in
                                              agent.start(agent: kind,
                                                          cwd: workingDirectory,
                                                          activeFile: activeFileForAgent)
                                          })
                                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
                        }
                    }
                    footer
                }
                .background(ThemeToken.paper)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .preferredColorScheme(ThemePreference(rawValue: theme)?.colorScheme)
        // タイトルバーの外観を揃えるため、NSWindow にも反映する。
        .onChange(of: theme) { _, newValue in
            ThemePreference.apply(ThemePreference(rawValue: newValue) ?? .auto,
                                  to: NSApp.keyWindow)
        }
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
        .onAppear {
            watcher.onExternalChange = { _ in
                // にじみとカーソル保全は MarkdownTextView 側で起きる。
                //   ここは読み直すだけ。document.lastExternalEdit が合図になる。
                guard let result = document.reloadFromDisk() else { return }
                #if DEBUG
                print("[watch] 読み直した / 変わった行 \(result.changedLines)")
                #endif
            }
            // .onChange は最初の値では発火しない。起動時に既に開いていた
            //   ファイルを見張り始めるために、ここでも1度呼ぶ。
            watcher.watch(path: document.path)
        }
        .onChange(of: document.path) { _, newPath in
            watcher.watch(path: newPath)
            agent?.followActiveFile(activeFileForAgent)
        }
        .task { await noteIndex.refresh(root: notesFolder.root) }
        .onChange(of: notesFolder.root) { _, newRoot in
            Task { await noteIndex.refresh(root: newRoot) }
        }
        // Obsidian 側でノートを増やして戻ってきたときに反映する
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await noteIndex.refresh(root: notesFolder.root) }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Glauk")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(ThemeToken.ink)
                Spacer()
                iconButton("sidebar.left", help: "サイドバーを隠す (⌘\\)") {
                    showTree = false
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 60)

            vaultButton
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            Button { showSwitcher = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                    Text("ノートを検索")
                    Spacer(minLength: 0)
                    Text("⌘O")
                        .font(.system(size: 11, weight: .medium))
                }
                .font(.system(size: 13))
                .foregroundStyle(ThemeToken.sidebarSecondary)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(ThemeToken.sidebarField, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .help("ノートを検索 (⌘O)")
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Button {
                if notesFolder.root != nil {
                    handle(.newNote(inFolder: ""))
                } else {
                    document.createWithPanel()
                }
            } label: {
                Label("新規ノート", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(ThemeToken.accent, in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 16)
            .padding(.bottom, 20)

            NoteTreeView(currentPath: currentRelativePath) { action in
                handle(action)
            }

            Rectangle().fill(ThemeToken.shellDivider).frame(height: 1)
            SettingsLink {
                Label("設定", systemImage: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(ThemeToken.sidebarSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 46)
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
            .help("設定 (⌘,)")
        }
        .background(ThemeToken.sidebar)
    }

    private var editor: some View {
        Group {
            if document.path == nil {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(ThemeToken.sidebarSecondary)
                    Text("ノートを開いて、書き始めましょう")
                        .font(.system(size: 17, weight: .medium))
                    Button("ノートを検索") { showSwitcher = true }
                        .buttonStyle(.link)
                }
                .foregroundStyle(ThemeToken.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MarkdownTextView(text: $document.text,
                                 noteIndex: noteIndex,
                                 loadRevision: document.revision,
                                 indexRevision: noteIndex.revision,
                                 externalEdit: document.lastExternalEdit,
                                 themeID: palette,
                                 onOpenNote: { name in
                                     Task { await navigator.follow(link: name) }
                                 })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if !showTree {
                iconButton("sidebar.left", help: "サイドバーを表示 (⌘\\)") {
                    showTree = true
                }
                Rectangle().fill(ThemeToken.shellDivider).frame(width: 1, height: 18)
            }
            iconButton("arrow.left", help: "戻る (⌘[)", enabled: navigator.canGoBack) {
                Task { await navigator.goBack() }
            }
            iconButton("arrow.right", help: "進む (⌘])", enabled: navigator.canGoForward) {
                Task { await navigator.goForward() }
            }
            Rectangle().fill(ThemeToken.shellDivider).frame(width: 1, height: 20)
            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundStyle(ThemeToken.sidebarSecondary)
            Text(breadcrumb)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ThemeToken.sidebarSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(document.path ?? "")
            Spacer(minLength: 8)
            if let error = document.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Button(action: toggleAgent) {
                Label(showAgent ? "AIを閉じる" : "AIを開く", systemImage: "sidebar.right")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(ThemeToken.sidebarField, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThemeToken.ink)
            .help("AIペインを出し入れ (⌘J)")
            Menu {
                Button("新規ファイル…") { document.createWithPanel() }
                Button("ファイルを開く…") { document.openWithPanel() }
                Button("ノートを検索") { showSwitcher = true }
                SettingsLink { Text("設定") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 28, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(ThemeToken.sidebarSecondary)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("⌘O でノートを検索")
            Text("·")
            Text("⌘J でAIを開く")
            Spacer()
            Text("Markdown")
        }
        .font(.system(size: 11))
        .foregroundStyle(ThemeToken.sidebarSecondary)
        .padding(.horizontal, 20)
        .frame(height: 28)
        .overlay(alignment: .top) {
            Rectangle().fill(ThemeToken.shellDivider).frame(height: 1)
        }
    }

    private var breadcrumb: String {
        guard let path = document.path else { return "ノートを選択" }
        if let relative = currentRelativePath {
            return (relative as NSString).deletingPathExtension
                .replacingOccurrences(of: "/", with: "  /  ")
        }
        return (path as NSString).lastPathComponent
    }

    private func iconButton(_ symbol: String,
                            help: String,
                            enabled: Bool = true,
                            active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? ThemeToken.ink : ThemeToken.sidebarSecondary)
                .frame(width: 28, height: 28)
                .background(active ? ThemeToken.sidebarField : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(help)
    }

    @ViewBuilder
    private var vaultButton: some View {
        if noteIndex.hasFolder, let root = notesFolder.root {
            Button {
                notesFolder.chooseWithPanel()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "folder")
                    Text((root as NSString).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ThemeToken.ink)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(ThemeToken.sidebarField, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .help(root)
        } else {
            Button("ノートフォルダを選ぶ…") { notesFolder.chooseWithPanel() }
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .buttonStyle(.plain)
                .background(ThemeToken.sidebarField, in: RoundedRectangle(cornerRadius: 9))
        }
    }

    // MARK: - AIペイン

    private func toggleAgent() {
        if showAgent {
            agent?.stop()          // 仕様: 閉じたら必ず終了。常駐させない
            showAgent = false
            return
        }
        let controller = agent ?? AgentPaneController()
        agent = controller
        showAgent = true
        controller.start(agent: AgentKind(rawValue: Int32(defaultAgent)) ?? .claude,
                         cwd: workingDirectory,
                         activeFile: activeFileForAgent)
        DispatchQueue.main.async { controller.focusTerminal() }
    }

    /// ノートを移動しても同じ会話で参照できるよう、設定済みなら vault を cwd にする。
    private var workingDirectory: String {
        if let root = notesFolder.root, !root.isEmpty { return root }
        guard let path = document.path else { return NSHomeDirectory() }
        return (path as NSString).deletingLastPathComponent
    }

    /// 開いているファイルの、cwd から見た相対パス。未保存なら nil。
    private var activeFileForAgent: String? {
        guard let path = document.path, !path.isEmpty else { return nil }
        let root = workingDirectory
        guard path.hasPrefix(root + "/") else {
            // vault の外を開いている。絶対パスなら確実に届く。
            return path
        }
        return String(path.dropFirst(root.count + 1))
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
            // 動かす前に書き出す。自動保存は800msデバウンスなので、打った直後に
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

    /// 自動保存が古いパスへ書き戻さないよう、文書の保存先を更新する。
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
