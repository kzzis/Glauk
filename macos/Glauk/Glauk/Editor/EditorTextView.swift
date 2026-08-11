// EditorTextView.swift
import AppKit

protocol EditorTextViewDelegate: AnyObject {
    func editorTextView(_ tv: NSTextView, didClickWikilink name: String)
}

final class EditorTextView: NSTextView {
    weak var linkDelegate: EditorTextViewDelegate?

    override func mouseDown(with event: NSEvent) {
        guard let storage = textStorage else {
            super.mouseDown(with: event); return
        }
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        guard index >= 0, index < storage.length,
              let name = storage.attribute(.glaukLinkTarget, at: index,
                                           effectiveRange: nil) as? String
        else {
            super.mouseDown(with: event); return      // ← リンク以外は通常動作
        }
        linkDelegate?.editorTextView(self, didClickWikilink: name)
    }

    /// リンクの上でカーソルを指差しに変える
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let storage = textStorage, let lm = layoutManager,
              let tc = textContainer else { return }

        storage.enumerateAttribute(.glaukLinkTarget,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, _ in
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
