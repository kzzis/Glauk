// EditorTextView.swift
import AppKit

protocol EditorTextViewDelegate: AnyObject {
    func editorTextView(_ tv: NSTextView, didClickWikilink name: String)
    func editorTextView(_ tv: NSTextView, didClickURL url: String)
}

final class EditorTextView: NSTextView {
    weak var linkDelegate: EditorTextViewDelegate?

    /// 本文の行長の上限。
    /// ★ 窓を広げると行がどこまでも伸びるのは、読み物としては読みにくい。
    ///   1行が長いほど、次の行の頭に目を戻すのが難しくなる。紙が広がっても
    ///   本文は真ん中の一段に留める。
    var maxContentWidth: CGFloat = 720
    /// 本文が狭いときの最低限の余白
    var minSideInset: CGFloat = 32

    /// 見出しの左に出す "H1" ラベル。
    /// ★ レイアウトマネージャの drawBackground から描くと出てこない。あちらの
    ///   描画はテキストコンテナの内側に切り取られ、余白には届かないため
    ///   (実測: 座標は x=75 と正しいのに、一切描かれなかった)。
    ///   余白はテキストビューのものなので、描くのもこちらの仕事。
    var showsLevelLabels = true
    var levelLabelColor = NSColor.tertiaryLabelColor
    var levelLabelFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSideInset()
    }

    private func updateSideInset() {
        let side = max(minSideInset, (bounds.width - maxContentWidth) / 2)
        // ★ inset を変えるとレイアウトが走り、setFrameSize が呼ばれうる。
        //   変化が無いときは触らないことで往復を止める。
        guard abs(textContainerInset.width - side) > 0.5 else { return }
        textContainerInset = NSSize(width: side, height: textContainerInset.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawLevelLabels(in: dirtyRect)
        #if DEBUG
        // 呼び出しからカーソルが出るまでを測る。受け入れ基準 p95 < 300ms 用。
        SummonClock.firstDraw()
        #endif
    }

    private func drawLevelLabels(in dirtyRect: NSRect) {
        guard showsLevelLabels,
              let storage = textStorage, let lm = layoutManager,
              let container = textContainer else { return }
        let inset = textContainerInset
        let attrs: [NSAttributedString.Key: Any] = [
            .font: levelLabelFont,
            .foregroundColor: levelLabelColor,
        ]
        storage.enumerateAttribute(.glaukHeadingLevel,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let level = value as? Int else { return }
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = lm.boundingRect(forGlyphRange: glyphs, in: container)
            guard !rect.isEmpty else { return }
            let label = "H\(level)" as NSString
            let size = label.size(withAttributes: attrs)
            // 見出しは字が大きい。上端ではなく1行目のベースライン寄りに置く。
            let y = inset.height + rect.minY
                + (rect.height * 0.5) - size.height / 2
            let point = NSPoint(x: inset.width + container.lineFragmentPadding - size.width - 10,
                                y: y)
            guard dirtyRect.intersects(NSRect(origin: point, size: size).insetBy(dx: -2, dy: -2)) else { return }
            label.draw(at: point, withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let storage = textStorage else {
            super.mouseDown(with: event); return
        }
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        guard index >= 0, index < storage.length else {
            super.mouseDown(with: event); return
        }

        if let name = storage.attribute(.glaukLinkTarget, at: index,
                                        effectiveRange: nil) as? String {
            linkDelegate?.editorTextView(self, didClickWikilink: name)
            return
        }
        // `[text](url)` は外のブラウザへ。ノートを開く経路とは分ける。
        if let url = storage.attribute(.glaukLinkURL, at: index,
                                       effectiveRange: nil) as? String {
            linkDelegate?.editorTextView(self, didClickURL: url)
            return
        }
        super.mouseDown(with: event)      // ← リンク以外は通常動作
    }

    /// ★ ⌘[ / ⌘] はここで拾う。ツールバーのボタンに .keyboardShortcut を
    ///   付けているだけだと、このテキストビューが firstResponder のときは
    ///   AppKit 側が先にキーを食べてしまい、届かないことがある。
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "[":
                NotificationCenter.default.post(name: .glaukGoBack, object: nil)
                return
            case "]":
                NotificationCenter.default.post(name: .glaukGoForward, object: nil)
                return
            case "j":
                NotificationCenter.default.post(name: .glaukToggleAgent, object: nil)
                return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    /// 多ボタンマウスの戻る/進む
    override func otherMouseDown(with event: NSEvent) {
        switch event.buttonNumber {
        case 3:
            NotificationCenter.default.post(name: .glaukGoBack, object: nil)
        case 4:
            NotificationCenter.default.post(name: .glaukGoForward, object: nil)
        default:
            super.otherMouseDown(with: event)
        }
    }

    /// リンクの上でカーソルを指差しに変える
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let storage = textStorage, let lm = layoutManager,
              let tc = textContainer else { return }

        let whole = NSRange(location: 0, length: storage.length)
        for key in [NSAttributedString.Key.glaukLinkTarget, .glaukLinkURL] {
            storage.enumerateAttribute(key, in: whole) { value, range, _ in
                guard value != nil else { return }
                let glyphRange = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                lm.enumerateEnclosingRects(
                    forGlyphRange: glyphRange,
                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                    in: tc
                ) { rect, _ in
                    var r = rect
                    r.origin.x += self.textContainerInset.width
                    r.origin.y += self.textContainerInset.height
                    self.addCursorRect(r, cursor: .pointingHand)
                }
            }
        }
    }
}
