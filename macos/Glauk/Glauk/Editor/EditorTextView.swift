// EditorTextView.swift
import AppKit

protocol EditorTextViewDelegate: AnyObject {
    func editorTextView(_ tv: NSTextView, didClickWikilink name: String)
    func editorTextView(_ tv: NSTextView, didClickURL url: String)
}

final class EditorTextView: NSTextView {
    weak var linkDelegate: EditorTextViewDelegate?

    #if DEBUG
    /// 呼び出しからカーソルが出るまでを測る。仕様書の受け入れ基準 p95 < 300ms 用。
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        SummonClock.firstDraw()
    }
    #endif

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
