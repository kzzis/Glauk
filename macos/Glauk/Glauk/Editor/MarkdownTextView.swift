// MarkdownTextView.swift
import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var noteIndex: NoteIndex
    /// ファイルを開くたびに増える値。これが変わったら、テキストビューが
    /// firstResponder中でも強制的に中身を差し替える(Step 4のファイル読み込み用)。
    var loadRevision = 0
    /// 索引が変わるたびに増える値。これが変わったら `[[リンク]]` の色だけ塗り直す
    /// (走査は非同期なので、初回表示のときは索引がまだ空のことがある)。
    var indexRevision = 0
    /// `[[リンク]]` がクリックされた。名前(`|`や`#`を落としたもの)が渡る。
    var onOpenNote: (String) -> Void = { _ in }
    var typewriterScroll: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // 最初に1回だけ呼ばれる。ここでAppKit側を組み立てる
    func makeNSView(context: Context) -> NSScrollView {
        let layoutManager = MarkdownLayoutManager()
        // 文字では表せない装飾(角丸・縦棒・罫線)を描くための色をハイライタと揃える
        let typography = EditorTypography()
        layoutManager.codeBgColor = typography.codeBg
        layoutManager.codeLangColor = typography.codeLangLabel
        layoutManager.codeCornerRadius = typography.codeCornerRadius
        layoutManager.inlineCodeCornerRadius = typography.inlineCodeCornerRadius
        layoutManager.quoteBarColor = typography.quoteBar
        layoutManager.quoteBarWidth = typography.quoteBarWidth
        layoutManager.tableRuleColor = typography.tableRule
        layoutManager.checkboxOnColor = typography.checkboxOn
        layoutManager.checkboxOffColor = typography.checkboxOff
        layoutManager.checkboxSize = typography.checkboxSize
        layoutManager.bulletColor = typography.bulletColor
        layoutManager.bulletRadius = typography.bulletRadius
        layoutManager.calloutTint = typography.calloutTint
        layoutManager.tagBgColor = typography.tagBg
        layoutManager.tagCornerRadius = typography.tagCornerRadius
        layoutManager.diffAddedBgColor = typography.codeAddedBg
        layoutManager.diffRemovedBgColor = typography.codeRemovedBg
        layoutManager.diffAddedBarColor = typography.codeAdded
        layoutManager.diffRemovedBarColor = typography.codeRemoved
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
        // ★ これが無いと maxSize は生成時のフレーム高さのまま = 表示領域の高さで頭打ちになり、
        //   本文がそれより長くてもテキストビューが伸びない(実測: 本文2545ptに対しフレーム660pt)。
        //   さらに scrollCurrentLineToCenter の maxY が 0 になるため、
        //   スクロールしても常に先頭へ戻され「全体が見れない」状態になる。
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)

        textView.font = NSFont(name: "IBMPlexMono", size: 15)
            ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.55
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.textStorage = storage   // ★ NSTextStorageの所有者がここしか無いので強参照で保持する
        context.coordinator.lastLoadRevision = loadRevision
        context.coordinator.lastIndexRevision = indexRevision
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
        // ★ 下の guard で早期 return する経路が多いので、必ず先に更新する。
        //   ここを後ろに置くと、リンクをクリックしても古い(何もしない)閉包が呼ばれる。
        context.coordinator.onOpenNote = onOpenNote
        // ★ 変換中(marked text)は絶対に触らない。
        //   下の `textView.string = text` はテキストビューを丸ごと置き換えるので、
        //   変換中に SwiftUI の再描画が挟まると未確定の文字列ごと消える。
        guard !textView.hasMarkedText() else { return }

        // ★ Step 5a: 走査が終わって索引が入れ替わったら、本文はそのままで塗り直す。
        //   これが無いと、起動直後に開いていた文書の `[[リンク]]` が
        //   「未作成」の見た目のまま(走査前の判定のまま)固まってしまう。
        if context.coordinator.lastIndexRevision != indexRevision {
            context.coordinator.lastIndexRevision = indexRevision
            if let storage = textView.textStorage {
                let ns = textView.string as NSString
                let selection = textView.selectedRange().clamped(to: ns.length)
                context.coordinator.highlighter.apply(to: storage,
                                                      cursorLine: ns.lineRange(for: selection))
            }
        }

        // ★ Step 4: ファイルを開いた直後は loadRevision が変わる。これは
        //   「テキストビューの中身を丸ごと差し替える」意図が明確な操作なので、
        //   firstResponder中でも(パネルを閉じてフォーカスが戻ってきていても)強制的に反映する。
        let isNewDocument = context.coordinator.lastLoadRevision != loadRevision
        guard isNewDocument || textView.string != text else { return }   // ★ 無限ループ防止

        if !isNewDocument {
            // ★ 編集中はテキストビューが正。
            //   SwiftUI から届く `text` は、テキストビューが既に持っている内容より
            //   古いことがある(特に日本語変換は1文字ごとに何度も状態を更新するので、
            //   確定がその更新列の間に挟まる)。古い値をここで代入すると、
            //   いま確定したばかりの文字が消える。
            let isEditing = textView.window?.firstResponder === textView
            guard !isEditing else { return }
        }
        context.coordinator.lastLoadRevision = loadRevision

        let selected = textView.selectedRange()
        textView.string = text
        let ns = text as NSString
        // 新しいファイルを開いたときは先頭にカーソルを置く。同一文書内の更新は選択位置を保つ。
        let safeLocation = isNewDocument ? 0 : min(selected.location, ns.length)
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
        private lazy var completion = WikilinkCompletion(index: parent.noteIndex)
        weak var textView: NSTextView?
        var textStorage: NSTextStorage?   // NSTextView/NSTextContainerはlayoutManagerを弱参照するため、これが無いと解放されて編集不能になる
        var lastLoadRevision: Int?
        var lastIndexRevision = 0
        var onOpenNote: (String) -> Void = { _ in }
        private var lastCursorLine: NSRange?
        private var pendingEditedRange: NSRange?
        private var highlightScheduled = false

        init(_ parent: MarkdownTextView) {
            self.parent = parent
            super.init()
            highlighter.noteExists = { [weak noteIndex = parent.noteIndex] name in
                // NSTextStorageDelegate/NSTextViewDelegate の呼び出しは常にメインスレッドなので安全
                MainActor.assumeIsolated { noteIndex?.looksResolvable(name) ?? true }
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

            // ★ 変換中(下線が出ている状態)に complete(nil) を呼ぶと、変換候補ウィンドウと
            //   補完ポップアップがぶつかって入力が壊れる。日本語環境ではほぼ必須のガード。
            guard !textView.hasMarkedText() else { return }
            let ns = textView.string as NSString
            let cursor = textView.selectedRange().location
            if completion.openBracketRange(in: ns, cursor: cursor) != nil {
                textView.complete(nil)
            }
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            let ns = textView.string as NSString
            guard completion.openBracketRange(in: ns, cursor: NSMaxRange(charRange)) != nil else {
                return []      // wikilink 文脈でなければ標準の英単語補完を出さない
            }
            let query = ns.substring(with: charRange)
            // NSTextViewDelegate の呼び出しは常にメインスレッド
            return MainActor.assumeIsolated { completion.completions(for: query) }
        }

        func textView(_ textView: NSTextView, rangeForUserCompletion range: NSRange) -> NSRange {
            let ns = textView.string as NSString
            return completion.openBracketRange(in: ns, cursor: NSMaxRange(range)) ?? range
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

        /// `[[リンク]]` をクリックした。開くかどうかの判断は ContentView に任せる
        /// (未作成なら作成の確認を出す、履歴に積む、といった判断はここの仕事ではない)。
        func editorTextView(_ tv: NSTextView, didClickWikilink name: String) {
            // mouseDown からの呼び出しなので常にメインスレッド
            MainActor.assumeIsolated { onOpenNote(name) }
        }

        /// `[text](url)` をクリックした。外のブラウザに渡す。
        func editorTextView(_ tv: NSTextView, didClickURL url: String) {
            guard let parsed = URL(string: url), parsed.scheme != nil else {
                NSSound.beep()      // 相対パスなど、いまは開けないもの
                return
            }
            NSWorkspace.shared.open(parsed)
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
