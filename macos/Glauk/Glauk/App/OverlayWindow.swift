// OverlayWindow.swift
import AppKit
import SwiftUI

/// 使い回すウィンドウ。閉じずに隠すので、次に出すときは組み立て直さなくて済む。
final class OverlayWindow: NSWindow {
    /// ★ タイトルバーを隠すと AppKit が「これはパネルだろう」と判断して
    ///   キーボード入力を受け付けなくなる。明示的に許可する。
    ///   これを忘れると「窓は出るが文字が打てない」という分かりにくい症状になる。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Esc で隠す
    override func cancelOperation(_ sender: Any?) {
        (delegate as? OverlayWindowController)?.hide()
    }
}

#if DEBUG
/// 呼び出しからカーソルが出るまでを測るための時計。
/// 仕様書の受け入れ基準(p95 < 300ms)を実際に確かめる。
enum SummonClock {
    nonisolated(unsafe) static var startedAt: CFAbsoluteTime = 0
    nonisolated(unsafe) static var waiting = false

    static func begin() {
        startedAt = CFAbsoluteTimeGetCurrent()
        waiting = true
    }

    static func firstDraw() {
        guard waiting else { return }
        waiting = false
        let ms = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        print("[summon] \(String(format: "%.1f", ms))ms")
    }
}
#endif

@MainActor
final class OverlayWindowController: NSObject, NSWindowDelegate {
    private(set) var window: OverlayWindow!
    private let fadeDuration: TimeInterval = 0.12
    /// 出す直前に呼ばれる。索引の更新など。
    var onSummon: (() -> Void)?

    func build<Content: View>(rootView: Content) {
        let w = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)

        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        // ★ 既定では close() でインスタンスごと解放される。show/hide 方式では
        //   次に makeKeyAndOrderFront した瞬間に解放済みを触って落ちる。
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: rootView)
        w.center()
        w.setFrameAutosaveName("GlaukMainWindow")   // 位置とサイズを覚える
        w.orderOut(nil)
        window = w
    }

    var isShown: Bool { window?.isVisible ?? false }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard let window else { return }
        #if DEBUG
        SummonClock.begin()
        #endif
        onSummon?()
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }, completionHandler: {
            // ★ アニメーションが走らない状況(非アクティブ時など)でも必ず見える状態にする。
            //   実測: これが無いと alpha が 0 のまま残り、窓は開いているのに何も見えない。
            window.alphaValue = 1
        })
        // ★ show() の直後はまだビュー階層が組み上がっていない。
        //   1周期待ってから本文にフォーカスを当てる。
        DispatchQueue.main.async { [weak self] in self?.focusEditor() }
    }

    func hide() {
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeDuration
            window.animator().alphaValue = 0
        }, completionHandler: {
            // ★ NSApp.hide(nil) は使わない。アプリごと隠れるので、次に
            //   makeKeyAndOrderFront しても出てこなくなる(実測: 2回目が表示されない)。
            //   orderOut だけで、フォーカスは自然に前のアプリへ戻る。
            window.orderOut(nil)
        })
    }

    /// 赤ボタンでも終了させず、隠すだけにする
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    /// 本文のテキストビューを探して first responder にする。
    /// SwiftUI 経由で参照を引き回すより、階層を1度歩くほうが壊れにくい。
    private func focusEditor() {
        guard let window, let root = window.contentView else { return }
        guard let editor = Self.firstTextView(in: root) else { return }
        window.makeFirstResponder(editor)
    }

    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = firstTextView(in: sub) { return found }
        }
        return nil
    }
}
