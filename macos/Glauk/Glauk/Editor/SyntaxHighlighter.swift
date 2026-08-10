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
    var ink = NSColor.textColor
}

final class SyntaxHighlighter {
    private let typography: EditorTypography
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
        storage.addAttribute(.font, value: typography.body, range: scope)
        storage.addAttribute(.foregroundColor, value: typography.ink, range: scope)

        // bold_marker は開き・閉じの2個1組で来る(Zig側が閉じが見つかったときだけ両方を返すため)
        var pendingBoldOpen: Span?

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

            case .wikilinkName:
                storage.addAttribute(.foregroundColor, value: typography.accent, range: span.range)

            case .wikilinkTarget:
                let name = (storage.string as NSString).substring(with: span.range)
                storage.addAttribute(.glaukLinkTarget, value: name, range: span.range)
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
        applySpans(to: storage, in: scope, cursorLine: cursorLine)
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
