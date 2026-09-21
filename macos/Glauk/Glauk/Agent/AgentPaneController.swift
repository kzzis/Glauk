import AppKit
import Combine
import SwiftTerm

/// SwiftTerm の描画と Zig の PTY を接続する。プロセス管理は Zig が担う。
@MainActor
final class AgentPaneController: NSObject, ObservableObject {
    let terminalView: TerminalView
    private let pty = PtySession()

    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var runningAgent: AgentKind?

    /// 入力欄に差し込むパス。自動送信しないよう、改行は付けない。
    private var pendingSeed: String?
    /// CLI が黙ってから差し込むための遅延。出力が来るたびに引き直す。
    private var seedTask: Task<Void, Never>?
    /// ずっと描き続ける CLI で永久に差し込まれないのを防ぐ打ち切り時刻。
    private var seedDeadline: Date?
    /// いま入力欄に入っている、こちらが打った分。消すときの文字数もここから数える。
    private var insertedSeed: String?
    /// ユーザー入力後は書きかけを守るため差し替えない。
    /// SwiftTerm のデリゲートは隔離外から呼ばれるため nonisolated にする。
    private nonisolated(unsafe) var userTypedSinceSeed = false
    /// ヘッダに出す「いまエージェントに渡してあるファイル」。
    @Published private(set) var contextFile: String?

    override init() {
        terminalView = TerminalView(frame: NSRect(x: 0, y: 0, width: 420, height: 400),
                                    font: GlaukFont.mono(size: 12))
        super.init()
        terminalView.terminalDelegate = self
        applyTheme()
        pty.onOutput = { [weak self] chunk in
            guard let self else { return }
            self.terminalView.feed(byteArray: chunk)
            self.scheduleSeed()
        }
        pty.onExit = { [weak self] sawAnyOutput in
            self?.handleExit(sawAnyOutput: sawAnyOutput)
        }
    }

    /// - Parameter activeFile: cwd からの相対パス。未保存なら nil。
    /// `@` は CLI のファイル検索を開き IME を妨げるため、素のパスを差し込む。
    func start(agent: AgentKind, cwd: String, activeFile: String?) {
        errorMessage = nil
        clearScreen()
        cancelSeed()
        insertedSeed = nil
        userTypedSinceSeed = false
        pendingSeed = activeFile.map { "\($0) " }
        contextFile = activeFile
        guard pty.start(agent: agent, cwd: cwd) else {
            errorMessage = "エージェントを起動できませんでした"
            isRunning = false
            runningAgent = nil
            return
        }
        isRunning = true
        runningAgent = agent
        // 初期サイズは spawn の既定値。レイアウト後の sizeChanged で実寸を伝える。
    }

    /// 背景色は CGColor に変換されて外観が固定されるため、テーマ変更時に再適用する。
    func applyTheme() {
        let appearance = terminalView.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            terminalView.nativeBackgroundColor = ThemeToken.NS.paper
            terminalView.nativeForegroundColor = ThemeToken.NS.ink
        }
    }

    private func clearScreen() {
        terminalView.clearScrollback()
        terminalView.feed(text: "\u{1b}[H\u{1b}[2J")
    }

    /// ペイン表示後も本文に残るフォーカスを移す。
    func focusTerminal() {
        terminalView.window?.makeFirstResponder(terminalView)
    }

    func stop() {
        cancelSeed()
        insertedSeed = nil
        contextFile = nil
        pty.stop()
        isRunning = false
        runningAgent = nil
    }

    // MARK: - 開いているファイルを伝える

    /// CLI の入力欄が準備できるよう、出力が落ち着くまで待ってから差し込む。
    private func scheduleSeed() {
        guard pendingSeed != nil else { return }
        if seedDeadline == nil { seedDeadline = Date().addingTimeInterval(5) }
        seedTask?.cancel()
        let quiet = min(0.7, max(0.05, seedDeadline?.timeIntervalSinceNow ?? 0.7))
        seedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(quiet))
            guard !Task.isCancelled else { return }
            self?.flushSeed()
        }
    }

    private func flushSeed() {
        guard let seed = pendingSeed else { return }
        cancelSeed()
        userTypedSinceSeed = false
        pty.send(ArraySlice(Array(seed.utf8)))
        insertedSeed = seed
    }

    private func cancelSeed() {
        pendingSeed = nil
        seedTask?.cancel()
        seedTask = nil
        seedDeadline = nil
    }

    /// ユーザーが未入力の場合だけ、自分が差し込んだパスを置き換える。
    func followActiveFile(_ relativePath: String?) {
        let seed = relativePath.map { "\($0) " }

        // まだ差し込んでいない(CLI の起動中)なら、送る中身を入れ替えるだけでよい。
        if pendingSeed != nil {
            pendingSeed = seed
            contextFile = relativePath
            return
        }
        guard isRunning, !userTypedSinceSeed else { return }
        guard seed != insertedSeed else { return }

        eraseInsertedSeed()
        if let seed {
            pty.send(ArraySlice(Array(seed.utf8)))
            insertedSeed = seed
        }
        contextFile = relativePath
    }

    /// 自分が打った分だけ後退で消す。DEL を文字数ぶん送る。
    private func eraseInsertedSeed() {
        guard let old = insertedSeed, !old.isEmpty else { return }
        let deletes = [UInt8](repeating: 0x7f, count: old.count)
        pty.send(deletes[...])
        insertedSeed = nil
    }

    private func handleExit(sawAnyOutput: Bool) {
        isRunning = false
        runningAgent = nil
        if !sawAnyOutput {
            // CLI が PATH に無いと、子が execvp に失敗して _exit(127) し、
            //   1バイトも出さずに EOF になる。これを起動失敗の合図として使う。
            errorMessage = "CLI が見つかりません。ターミナルで `which claude` が通るか確認してください"
        }
    }
}

// MARK: - TerminalViewDelegate
extension AgentPaneController: TerminalViewDelegate {
    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        userTypedSinceSeed = true
        pty.send(data)
    }

    /// ペインの大きさが変わったら PTY にも伝える。これが無いと折り返しがずれる。
    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        pty.resize(rows: newRows, cols: newCols)
    }

    nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func scrolled(source: TerminalView, position: Double) {}
    nonisolated func bell(source: TerminalView) {}
    nonisolated func clipboardCopy(source: TerminalView, content: Data) {}
    nonisolated func clipboardRead(source: TerminalView) -> Data? { nil }
    nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), url.scheme != nil else { return }
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
    }
}
