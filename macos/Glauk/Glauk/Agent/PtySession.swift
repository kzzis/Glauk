// PtySession.swift
import Foundation
import GlaukCore

enum AgentKind: Int32, CaseIterable, Identifiable {
    case claude = 0
    case codex = 1

    var id: Int32 { rawValue }
    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

/// Zig の PTY を Swift から使うための包み。
///
/// ★ ここには SwiftTerm を持ち込まない。端末の描画とプロセスの世話を分けておくと、
///   画面が無くても起動・読み書き・後始末を確かめられる。
final class PtySession {
    /// 出力が来るたびに呼ばれる。メインスレッドで呼ぶ。
    /// ★ このプロジェクトは既定が MainActor 隔離。SwiftTerm のデリゲートは
    ///   その外から呼ばれるので、この型は隔離の外に置く必要がある。
    nonisolated(unsafe) var onOutput: ((ArraySlice<UInt8>) -> Void)?
    /// 子が終わったときに1度だけ呼ばれる。メインスレッドで呼ぶ。
    /// `sawAnyOutput` が false なら、1バイトも出さずに落ちた = CLI が見つからない。
    nonisolated(unsafe) var onExit: ((_ sawAnyOutput: Bool) -> Void)?

    /// ★ SwiftTerm のデリゲートは @MainActor の外から呼ばれる。
    ///   Zig 側の表は Mutex で守られていて、知らないIDには安全に失敗するので、
    ///   ここは並行性チェックの外に置く。
    private nonisolated(unsafe) var id: Int32 = -1
    /// ★ 画面の大きさは起動より前に届く(SwiftTerm はレイアウト時に sizeChanged を
    ///   投げ、そのとき PTY はまだ無い)。覚えておいて起動時に渡さないと、
    ///   CLI が 80桁で最初の1画面を描いてしまい、折り返しが崩れたまま残る。
    private nonisolated(unsafe) var lastRows: Int = 24
    private nonisolated(unsafe) var lastCols: Int = 80
    private let lock = NSLock()

    nonisolated var sessionId: Int32 {
        lock.lock(); defer { lock.unlock() }
        return id
    }

    nonisolated var isRunning: Bool { sessionId >= 0 }

    /// 起動できたら true。
    @discardableResult
    nonisolated func start(agent: AgentKind, cwd: String) -> Bool {
        stop()
        lock.lock()
        let rows = lastRows
        let cols = lastCols
        lock.unlock()
        let newId = cwd.withCString {
            glauk_pty_spawn(agent.rawValue, $0, UInt16(rows), UInt16(cols))
        }
        guard newId >= 0 else { return false }
        lock.lock(); id = newId; lock.unlock()

        // ★ 終わらないループなので Task ではなくスレッドを1本立てる。
        //   async は「待って再開する」モデルで、回り続ける read に合わない。
        let queue = DispatchQueue(label: "glauk.pty.read.\(newId)", qos: .userInitiated)
        queue.async { [weak self] in self?.readLoop(newId) }
        return true
    }

    private nonisolated func readLoop(_ sessionId: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var sawAnyOutput = false

        while true {
            let n = buffer.withUnsafeMutableBufferPointer {
                glauk_pty_read(sessionId, $0.baseAddress, $0.count)
            }
            guard n > 0 else { break }      // 0 = EOF(子が終了) / -1 = エラー
            sawAnyOutput = true
            let chunk = Array(buffer[0..<Int(n)])
            // ★ 受け手は画面を触るので必ずメインスレッドへ戻す。
            //   AppKit はスレッド安全ではなく、忘れると「動くけど時々落ちる」になる。
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // ★ 既に読んでしまった分がメインスレッドの順番待ちに残っている。
                //   エージェントを切り替えた後にそれが流れると、前の会話と
                //   新しい会話が同じ画面に混ざる。今のセッションの分だけ通す。
                guard self.sessionId == sessionId else { return }
                self.onOutput?(chunk[...])
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // 自分が畳んだ後、あるいは切り替えた後の EOF なら黙って終わる。
            // 通すと、新しく起動したセッションが「終了した」ことにされてしまう。
            guard self.sessionId == sessionId else { return }
            self.clearId()
            self.onExit?(sawAnyOutput)
        }
    }

    nonisolated func send(_ bytes: ArraySlice<UInt8>) {
        let id = sessionId
        guard id >= 0 else { return }
        let array = Array(bytes)
        _ = array.withUnsafeBufferPointer { glauk_pty_write(id, $0.baseAddress, $0.count) }
    }

    nonisolated func resize(rows: Int, cols: Int) {
        guard rows > 0, cols > 0 else { return }
        lock.lock()
        lastRows = rows
        lastCols = cols
        let id = self.id
        lock.unlock()
        guard id >= 0 else { return }   // まだ起動していなければ覚えるだけ
        _ = glauk_pty_resize(id, UInt16(rows), UInt16(cols))
    }

    /// 仕様の「閉じたら必ず終了、常駐させない」を守る唯一の出口。
    nonisolated func stop() {
        let old = sessionId
        guard old >= 0 else { return }
        clearId()
        glauk_pty_kill(old)
    }

    private nonisolated func clearId() {
        lock.lock(); id = -1; lock.unlock()
    }

    deinit {
        // ペインを閉じ忘れたままでもプロセスを残さない
        let old = sessionId
        if old >= 0 { glauk_pty_kill(old) }
    }
}
