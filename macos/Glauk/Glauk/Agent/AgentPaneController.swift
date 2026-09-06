// AgentPaneController.swift
import AppKit
import Combine
import SwiftTerm

/// AIペインの中身。画面(SwiftTerm)と PTY(Zig)を繋ぐだけに留める。
///
/// ★ SwiftTerm の LocalProcessTerminalView は使わない。プロセスの世話は Zig の責務。
///   Swift 側を薄く保つと、コアを別言語に移す道も残る。
@MainActor
final class AgentPaneController: NSObject, ObservableObject {
    let terminalView: TerminalView
    private let pty = PtySession()

    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var runningAgent: AgentKind?

    /// 起動直後に入力欄へ差し込む文字列(まだ送っていない分)。
    /// ★ cwd だけでは「このファイル」が通じない。フォルダには .md が何枚もあり、
    ///   エージェントはどれを指しているのか分からない。開いているファイルの
    ///   名前を、人が打つのと同じ経路で最初に入れておく。改行は送らない。
    private var pendingSeed: String?
    /// CLI が黙ってから差し込むための遅延。出力が来るたびに引き直す。
    private var seedTask: Task<Void, Never>?
    /// ずっと描き続ける CLI で永久に差し込まれないのを防ぐ打ち切り時刻。
    private var seedDeadline: Date?
    /// いま入力欄に入っている、こちらが打った分。消すときの文字数もここから数える。
    private var insertedSeed: String?
    /// ★ 差し込んだあとに人が1文字でも打ったら、以降は入力欄に触らない。
    ///   書きかけを黙って消される方が、古いファイル名が残るよりずっと困る。
    ///   SwiftTerm のデリゲートは隔離の外から来るので nonisolated で持つ。
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

    /// - Parameter activeFile: 開いているファイルの、cwd から見た相対パス。
    ///   未保存なら nil。入力欄の先頭にそのまま差し込む。
    /// ★ 以前は `@名前` にしていたが、`@` は claude / codex 双方でファイル検索の
    ///   ポップアップを開く。開いたままだと CLI 側が入力を横取りし、日本語の
    ///   変換候補が出せなくなる。素のパスでも「どのファイルの話か」は通じる。
    func start(agent: AgentKind, cwd: String, activeFile: String?) {
        errorMessage = nil
        // ★ 前の会話を消してから始める。切り替えは作り直しなので、
        //   残っていると2つの会話が同じ画面に並んでいるように見える。
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
        // ★ 起動直後の大きさは spawn 側の 24x80 のまま。SwiftTerm がレイアウトの
        //   たびに sizeChanged を投げてくるので、そこで実寸に直る。
        //   ここで公開されていない内部APIを覗きに行かない。
    }

    /// エディタと同じ紙とインクにする。
    /// ★ ANSI の16色までは作り込まない。エージェントの出力が読めればよく、
    ///   凝りすぎると仕様書の「カスタマイズ自由度より完成度優先」から外れる。
    /// ★ nativeBackgroundColor は CGColor に変換されて layer に入る = その時点の
    ///   外観で固定される。動的な色を渡すだけでは追随しないので、テーマが
    ///   変わったら呼び直す必要がある。
    func applyTheme() {
        let appearance = terminalView.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            terminalView.nativeBackgroundColor = ThemeToken.NS.paper
            terminalView.nativeForegroundColor = ThemeToken.NS.ink
        }
    }

    /// 画面を消す。SwiftTerm に「まっさらに戻す」APIは無いので、
    /// 端末に向けて消去のエスケープを流す(どの版でも通る)。
    private func clearScreen() {
        terminalView.clearScrollback()
        terminalView.feed(text: "\u{1b}[H\u{1b}[2J")
    }

    /// ★ ペインを出しただけでは本文の NSTextView がフォーカスを持ったまま。
    ///   打った文字がエディタに入ってしまい「対話できない」ように見える。
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

    /// 出力が来るたびに呼ばれ、静かになったところで1度だけ差し込む。
    /// ★ 起動直後に送っても、CLI がまだ入力欄を用意しておらず捨てられる。
    ///   「最後の出力から少し経った = 描き終わった」を合図に使う。
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

    /// 開いているノートが変わった。入力欄のファイル名を差し替える。
    ///
    /// ★ 差し替えられるのは「まだ人が何も打っていない」ときだけ。自分が打った
    ///   ぶんの文字数しか消さないので、書きかけを巻き込むことはない。
    ///   打ち始めていたら何もしない — ヘッダの表示だけが新しいファイルを指す。
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
            // ★ CLI が PATH に無いと、子が execvp に失敗して _exit(127) し、
            //   1バイトも出さずに EOF になる。これを起動失敗の合図として使う。
            errorMessage = "CLI が見つかりません。ターミナルで `which claude` が通るか確認してください"
        }
    }
}

// MARK: - TerminalViewDelegate
// ★ 既定実装が無いので全部書く必要がある。ほとんどは空でよい。
extension AgentPaneController: TerminalViewDelegate {
    /// ユーザーのキー入力 → PTY へ
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

    /// ターミナル内のリンクは外のブラウザで開く
    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), url.scheme != nil else { return }
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
    }
}
