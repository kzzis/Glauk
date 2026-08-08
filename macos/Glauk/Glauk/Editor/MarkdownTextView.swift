// MarkdownTextView.swift
import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var typewriterScroll: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // 最初に1回だけ呼ばれる。ここでAppKit側を組み立てる
    func makeNSView(context: Context) -> NSScrollView {
        let layoutManager = MarkdownLayoutManager()
        let storage = NSTextStorage()
        storage.delegate = context.coordinator
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator

        // --- 書き心地に効く設定 ---
        textView.isRichText = false                          // 貼り付けで書式を持ち込ませない
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false  // " が " に化けるのを防ぐ
        textView.isAutomaticDashSubstitutionEnabled = false   // -- が — に化けるのを防ぐ
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // --- スクロール内で正しく伸びるための定型 ---
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textView.textContainerInset = NSSize(width: 32, height: 32)

        textView.font = NSFont(name: "IBMPlexMono", size: 15)
            ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.55
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.textStorage = storage   // ★ NSTextStorageの所有者がここしか無いので強参照で保持する
        context.coordinator.highlighter.apply(to: storage, cursorLine: nil)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    // SwiftUI側の状態が変わるたびに呼ばれる
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard textView.string != text else { return }   // ★ 無限ループ防止

        let selected = textView.selectedRange()
        textView.string = text
        let safeLocation = min(selected.location, (text as NSString).length)
        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        if let storage = textView.textStorage {
            context.coordinator.highlighter.apply(to: storage, cursorLine: nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        private let parent: MarkdownTextView
        let highlighter = SyntaxHighlighter()
        weak var textView: NSTextView?
        var textStorage: NSTextStorage?   // NSTextView/NSTextContainerはlayoutManagerを弱参照するため、これが無いと解放されて編集不能になる
        private var lastCursorLine: NSRange?

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            #if DEBUG
            let t0 = CFAbsoluteTimeGetCurrent()
            #endif

            parent.text = textView.string

            #if DEBUG
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            if ms > 8 { print("[latency] textDidChange \(String(format: "%.2f", ms))ms") }
            #endif
        }

        // NSTextStorage が編集を確定させた直後に呼ばれる。ここで段落単位のLive Previewを更新する
        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            guard let textView, !textView.hasMarkedText() else { return }   // 変換中は触らない

            let ns = textStorage.string as NSString
            // ★ ここで渡ってくる selectedRange は、直前の削除等でまだ古い(編集前の)値のことがある
            let selection = textView.selectedRange().clamped(to: ns.length)
            let cursorLine = ns.lineRange(for: selection)
            highlighter.applyIncremental(to: textStorage, editedRange: editedRange, cursorLine: cursorLine)
            lastCursorLine = cursorLine
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let storage = textView.textStorage else { return }

            let ns = storage.string as NSString
            let selection = textView.selectedRange().clamped(to: ns.length)
            let current = ns.lineRange(for: selection)

            if let previous = lastCursorLine, previous != current {
                highlighter.applySpans(to: storage, in: previous, cursorLine: current)
            }
            highlighter.applySpans(to: storage, in: current, cursorLine: current)
            lastCursorLine = current

            if parent.typewriterScroll { scrollCurrentLineToCenter(textView) }
        }

        private func scrollCurrentLineToCenter(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: textView.selectedRange(), actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            lineRect.origin.y += textView.textContainerInset.height

            let visibleHeight = scrollView.contentView.bounds.height
            let targetY = lineRect.midY - visibleHeight / 2
            let maxY = max(0, textView.bounds.height - visibleHeight)
            let clampedY = min(max(0, targetY), maxY)

            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: clampedY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
