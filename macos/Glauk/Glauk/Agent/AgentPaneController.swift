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

    override init() {
        terminalView = TerminalView(frame: NSRect(x: 0, y: 0, width: 420, height: 400), font: nil)
        super.init()
        terminalView.terminalDelegate = self
        pty.onOutput = { [weak self] chunk in
            self?.terminalView.feed(byteArray: chunk)
        }
        pty.onExit = { [weak self] sawAnyOutput in
            self?.handleExit(sawAnyOutput: sawAnyOutput)
        }
    }

    func start(agent: AgentKind, cwd: String) {
        errorMessage = nil
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

    func stop() {
        pty.stop()
        isRunning = false
        runningAgent = nil
    }

    private func handleExit(sawAnyOutput: Bool) {
        isRunning = false
        runningAgent = nil
        if !sawAnyOutput {
            // ★ CLI が PATH に無いと、子が execvp に失敗して _exit(127) し、
            //   1バイトも出さずに EOF になる。これを起動失敗の合図として使う。
            errorMessage = "CLI が見つかりません。`claude` / `codex` が PATH にあるか確認してください"
        }
    }
}

// MARK: - TerminalViewDelegate
// ★ 既定実装が無いので全部書く必要がある。ほとんどは空でよい。
extension AgentPaneController: TerminalViewDelegate {
    /// ユーザーのキー入力 → PTY へ
    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
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
