// SyntaxHighlighter.swift
import AppKit

struct EditorTypography {
    /// MarkdownTextView が textView.font に入れているものと必ず揃えること。
    /// ここがズレると applySpans が全文の .font を上書きしてしまい、等幅で書いているつもりが
    /// プロポーショナルで表示される(太字の差も分かりにくくなる)。
    var body = NSFont(name: "IBMPlexMono", size: 15)
        ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    var heading: (Int) -> NSFont = { level in
        let sizes: [CGFloat] = [28, 22, 18]
        return NSFont.systemFont(ofSize: sizes[min(level, 3) - 1], weight: .bold)
    }
    /// システム等幅フォントに対しては、NSFontManager の変換もディスクリプタの .bold も
    /// **Semibold(weight 0.30)** しか返さず「太くなっていない」ように見える。
    /// 変換結果のウェイトを確かめ、bold に届かなければ等幅の bold ウェイト(0.40)を使う。
    var bold: (NSFont) -> NSFont = { base in
        let converted = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        let traits = converted.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? CGFloat) ?? 0
        if weight >= NSFont.Weight.bold.rawValue { return converted }
        return NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .bold)
    }
    var accent = NSColor.systemRed      // Step 9 でテーマトークンに差し替え
    var muted = NSColor.secondaryLabelColor
    var ink = NSColor.textColor
    /// コードは本文より少し小さい等幅。本文が既に等幅なのでフォント自体は同系だが、
    /// Step 9 で本文がサンセリフになったときにここだけ等幅で残るように分けておく。
    var code = NSFont(name: "IBMPlexMono", size: 14)
        ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    /// glauk-design-doc.md の CodeBg(Light #EFEDE8 / Dark #26262A)
    var codeBg = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0x26 / 255, green: 0x26 / 255, blue: 0x2A / 255, alpha: 1)
            : NSColor(srgbRed: 0xEF / 255, green: 0xED / 255, blue: 0xE8 / 255, alpha: 1)
    }
}

final class SyntaxHighlighter {
    private let typography: EditorTypography
    /// 未作成ノートの区別表示に使う。Coordinator から NoteIndex を差し込む
    var noteExists: (String) -> Bool = { _ in true }

    init(typography: EditorTypography = .init()) { self.typography = typography }

    /// 文書全体を再計算する(初期表示など)
    func apply(to storage: NSTextStorage, cursorLine: NSRange?) {
        applySpans(to: storage, in: NSRange(location: 0, length: storage.length), cursorLine: cursorLine)
    }

    /// `scope` の範囲だけを再計算する
    func applySpans(to storage: NSTextStorage, in scope: NSRange, cursorLine: NSRange?) {
        guard NSMaxRange(scope) <= storage.length else { return }
        let ns = storage.string as NSString
        let scopedText = ns.substring(with: scope)
        let spans = MarkdownParser.spans(in: scopedText).map { span in
            Span(range: NSRange(location: span.range.location + scope.location, length: span.range.length),
                 kind: span.kind)
        }

        storage.beginEditing()
        storage.removeAttribute(.glaukHidden, range: scope)
        // 前回の結果を消しておかないと、記法を消したあとも背景や下線が残る
        storage.removeAttribute(.backgroundColor, range: scope)
        storage.removeAttribute(.underlineStyle, range: scope)
        storage.addAttribute(.font, value: typography.body, range: scope)
        storage.addAttribute(.foregroundColor, value: typography.ink, range: scope)

        // bold_marker は開き・閉じの2個1組で来る(Zig側が閉じが見つかったときだけ両方を返すため)
        var pendingBoldOpen: Span?
        // wikilink_target は wikilink_name より必ず先に来る(開始位置ソート済みのため)。
        // 直前に見た target 名を覚えておけば、続く name の存在判定に使える。
        var currentTargetName: String?

        for span in spans {
            guard NSMaxRange(span.range) <= storage.length else { continue }
            let onCursorLine = cursorLine.map { NSIntersectionRange($0, span.range).length > 0 }
                ?? false

            switch span.kind {
            case .heading1, .heading2, .heading3:
                let level = Int(span.kind.rawValue)
                let lineRange = (storage.string as NSString).lineRange(for: span.range)
                storage.addAttribute(.font, value: typography.heading(level), range: lineRange)
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .boldMarker:
                if let open = pendingBoldOpen {
                    let contentStart = NSMaxRange(open.range)
                    let contentRange = NSRange(location: contentStart, length: span.range.location - contentStart)
                    if contentRange.length > 0, NSMaxRange(contentRange) <= storage.length {
                        storage.addAttribute(.font, value: typography.bold(typography.body), range: contentRange)
                    }
                    pendingBoldOpen = nil
                } else {
                    pendingBoldOpen = span
                }
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .wikilinkHidden:
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .wikilinkTarget:
                let name = (storage.string as NSString).substring(with: span.range)
                currentTargetName = name
                storage.addAttribute(.glaukLinkTarget, value: name, range: span.range)

            case .codeFence:
                // ``` の行は丸ごと隠す。カーソルを置いたときだけ見える。
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .codeBlock, .inlineCode:
                storage.addAttribute(.font, value: typography.code, range: span.range)
                storage.addAttribute(.backgroundColor, value: typography.codeBg, range: span.range)

            case .inlineCodeMarker:
                // 隠していても背景は繋げたいので、先に背景を塗ってから隠す
                storage.addAttribute(.backgroundColor, value: typography.codeBg, range: span.range)
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .wikilinkName:
                let exists = currentTargetName.map(noteExists) ?? false
                if exists {
                    storage.addAttribute(.foregroundColor, value: typography.accent, range: span.range)
                } else {
                    storage.addAttribute(.foregroundColor, value: typography.muted, range: span.range)
                    storage.addAttribute(.underlineStyle,
                                         value: NSUnderlineStyle.patternDot.rawValue
                                              | NSUnderlineStyle.single.rawValue,
                                         range: span.range)
                }
            }
        }
        storage.endEditing()
    }

    /// 変更のあった範囲を含む段落だけを再計算する
    func applyIncremental(to storage: NSTextStorage, editedRange: NSRange, cursorLine: NSRange?) {
        let ns = storage.string as NSString
        let safeEditedRange = editedRange.clamped(to: ns.length)
        // 編集範囲を含む段落へ広げる(前後1行を含めると `**` の跨ぎに強くなる)
        var scope = ns.paragraphRange(for: safeEditedRange)
        if scope.location > 0 {
            scope = ns.paragraphRange(for: NSRange(location: scope.location - 1, length: 1))
                .union(scope)
        }
        // ★ コードブロックの途中で切ると、開きの ``` が見えないまま解析することになり、
        //   コードの中身が通常のMarkdownとして解釈されてしまう。ブロック全体まで広げる。
        scope = expandToFenceBoundaries(in: ns, scope: scope)
        applySpans(to: storage, in: scope, cursorLine: cursorLine)
    }

    /// ``` で囲まれたブロックに掛かっているなら、そのブロック全体を含むよう広げる
    private func expandToFenceBoundaries(in ns: NSString, scope: NSRange) -> NSRange {
        var fenceLines: [NSRange] = []
        var searchStart = 0
        while searchStart < ns.length {
            let found = ns.range(of: "```",
                                 range: NSRange(location: searchStart, length: ns.length - searchStart))
            guard found.location != NSNotFound else { break }
            let line = ns.lineRange(for: NSRange(location: found.location, length: 0))
            // 行頭(先頭の空白を除く)から始まるものだけをフェンスとみなす
            let indent = ns.substring(with: NSRange(location: line.location,
                                                    length: found.location - line.location))
            if indent.trimmingCharacters(in: .whitespaces).isEmpty { fenceLines.append(line) }
            searchStart = NSMaxRange(found)
        }

        var result = scope
        var i = 0
        while i < fenceLines.count {
            let open = fenceLines[i]
            // 閉じが無いフェンスは文末までをブロックとみなす(パーサ側の挙動と揃える)
            let closeEnd = i + 1 < fenceLines.count ? NSMaxRange(fenceLines[i + 1]) : ns.length
            let block = NSRange(location: open.location, length: closeEnd - open.location)
            let touches = NSIntersectionRange(block, scope).length > 0
                || (scope.location >= block.location && scope.location <= NSMaxRange(block))
            if touches { result = result.union(block) }
            i += 2
        }
        return result.clamped(to: ns.length)
    }
}

extension NSRange {
    func union(_ other: NSRange) -> NSRange {
        let start = Swift.min(location, other.location)
        let end = Swift.max(NSMaxRange(self), NSMaxRange(other))
        return NSRange(location: start, length: end - start)
    }

    /// `length` の範囲内に収まるよう location/length を切り詰める
    func clamped(to length: Int) -> NSRange {
        let start = Swift.min(location, length)
        let end = Swift.min(NSMaxRange(self), length)
        return NSRange(location: start, length: Swift.max(0, end - start))
    }
}
