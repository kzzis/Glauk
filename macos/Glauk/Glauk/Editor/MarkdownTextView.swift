// MarkdownTextView.swift
import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var noteIndex: NoteIndex
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

        let textView = EditorTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.linkDelegate = context.coordinator

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
        // ★ 変換中(marked text)は絶対に触らない。
        //   下の `textView.string = text` はテキストビューを丸ごと置き換えるので、
        //   変換中に SwiftUI の再描画が挟まると未確定の文字列ごと消える。
        guard !textView.hasMarkedText() else { return }
        guard textView.string != text else { return }   // ★ 無限ループ防止

        // ★ 編集中はテキストビューが正。
        //   SwiftUI から届く `text` は、テキストビューが既に持っている内容より
        //   古いことがある(特に日本語変換は1文字ごとに何度も状態を更新するので、
        //   確定がその更新列の間に挟まる)。古い値をここで代入すると、
        //   いま確定したばかりの文字が消える。
        //   外から流し込む必要が出てくるのは Step 4 のファイル読み込み以降で、
        //   そのときは binding 経由ではなく明示的な読み込み経路を作ること。
        let isEditing = textView.window?.firstResponder === textView
        guard !isEditing else { return }

        let selected = textView.selectedRange()
        textView.string = text
        let ns = text as NSString
        let safeLocation = min(selected.location, ns.length)
        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        if let storage = textView.textStorage {
            // cursorLine を nil にするとカーソル行のマーカーまで隠れてしまう
            let cursorLine = ns.lineRange(for: NSRange(location: safeLocation, length: 0))
            context.coordinator.highlighter.apply(to: storage, cursorLine: cursorLine)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate, EditorTextViewDelegate {
        private let parent: MarkdownTextView
        let highlighter = SyntaxHighlighter()
        weak var textView: NSTextView?
        var textStorage: NSTextStorage?   // NSTextView/NSTextContainerはlayoutManagerを弱参照するため、これが無いと解放されて編集不能になる
        private var lastCursorLine: NSRange?
        private var pendingEditedRange: NSRange?
        private var highlightScheduled = false

        init(_ parent: MarkdownTextView) {
            self.parent = parent
            super.init()
            highlighter.noteExists = { [weak noteIndex = parent.noteIndex] name in
                // NSTextStorageDelegate/NSTextViewDelegate の呼び出しは常にメインスレッドなので安全
                MainActor.assumeIsolated { noteIndex?.exists(name) ?? false }
            }
        }

        /// `**` を打ち終えた時点で閉じの `**` を補い、カーソルを内側に置く
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard replacementString == "*", affectedCharRange.length == 0 else { return true }

            let ns = textView.string as NSString
            let loc = affectedCharRange.location
            guard loc <= ns.length else { return true }

            func openMarkerCount(before end: Int) -> Int {
                let lineRange = ns.lineRange(for: NSRange(location: end, length: 0))
                let prefix = ns.substring(with: NSRange(location: lineRange.location,
                                                        length: end - lineRange.location))
                return markerPairCount(in: prefix)
            }

            // 補った閉じ `**` の上から打てるようにする。そうしないと自分で閉じを打ったときに
            // `**太字****` のように余ってしまう。
            if loc < ns.length, ns.character(at: loc) == asterisk,
               openMarkerCount(before: loc) % 2 == 1 {
                textView.setSelectedRange(NSRange(location: loc + 1, length: 0))
                return false
            }

            // 直前が `*` のときだけ = いま打った `*` で `**` が揃うとき
            guard loc > 0, ns.character(at: loc - 1) == asterisk else { return true }
            // `***` になる打ち方には介入しない
            if loc >= 2, ns.character(at: loc - 2) == asterisk { return true }
            // 行内に閉じられていない `**` が既にあるなら、この `**` は閉じ側なので補わない
            guard openMarkerCount(before: loc - 1) % 2 == 0 else { return true }

            textView.insertText("***", replacementRange: affectedCharRange)
            textView.setSelectedRange(NSRange(location: loc + 1, length: 0))
            return false
        }

        private let asterisk = unichar(UInt8(ascii: "*"))

        /// 重なりを数えないように `**` の個数を数える
        private func markerPairCount(in text: String) -> Int {
            let chars = Array(text.utf16)
            var count = 0
            var i = 0
            while i + 1 < chars.count {
                if chars[i] == asterisk && chars[i + 1] == asterisk {
                    count += 1
                    i += 2
                } else {
                    i += 1
                }
            }
            return count
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

        // NSTextStorage が編集を確定させた直後に呼ばれる。
        // ★ ここで属性を書き換えてはいけない。AppKit の編集サイクルの内側なので、
        //   SwiftUI に載せた状態だと変換確定(日本語入力の1回目のEnter)の直後に
        //   その行のレイアウトが失われ、行が丸ごと描画されなくなる。
        //   編集範囲だけ覚えておいて、サイクルを抜けてから塗る。
        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            pendingEditedRange = pendingEditedRange.map { $0.union(editedRange) } ?? editedRange
            scheduleHighlight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            scheduleHighlight()
            if parent.typewriterScroll { scrollCurrentLineToCenter(textView) }
        }

        /// 編集サイクルを抜けた次のターンで、まとめて1回だけ塗る
        private func scheduleHighlight() {
            guard !highlightScheduled else { return }
            highlightScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.highlightScheduled = false
                self.runPendingHighlight()
            }
        }

        private func runPendingHighlight() {
            guard let textView, let storage = textView.textStorage else { return }
            guard !textView.hasMarkedText() else { return }   // 変換中は触らない

            let ns = storage.string as NSString
            let selection = textView.selectedRange().clamped(to: ns.length)
            let cursorLine = ns.lineRange(for: selection)

            if let edited = pendingEditedRange {
                pendingEditedRange = nil
                highlighter.applyIncremental(to: storage,
                                             editedRange: edited.clamped(to: ns.length),
                                             cursorLine: cursorLine)
            }
            // カーソルが移った先と、離れた行の両方を塗り直す(ソース表示の切り替え)
            if let previous = lastCursorLine, previous != cursorLine {
                highlighter.applySpans(to: storage, in: previous, cursorLine: cursorLine)
            }
            highlighter.applySpans(to: storage, in: cursorLine, cursorLine: cursorLine)
            lastCursorLine = cursorLine
        }

        /// リンクをクリックしたときに呼ばれる。実際にノートを開く処理は Step 5b で差し替える
        func editorTextView(_ tv: NSTextView, didClickWikilink name: String) {
            // mouseDown からの呼び出しなので常にメインスレッド
            MainActor.assumeIsolated {
                if parent.noteIndex.exists(name) {
                    print("[link] open: \(name) → \(parent.noteIndex.path(for: name) ?? "?")")
                } else {
                    print("[link] not found: \(name)")
                    NSSound.beep()
                }
            }
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
