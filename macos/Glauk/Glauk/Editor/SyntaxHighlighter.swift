// SyntaxHighlighter.swift
import AppKit

struct EditorTypography {
    var body = NSFont.systemFont(ofSize: 15)
    var heading: (Int) -> NSFont = { level in
        let sizes: [CGFloat] = [28, 22, 18]
        return NSFont.systemFont(ofSize: sizes[min(level, 3) - 1], weight: .bold)
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

            case .boldMarker, .wikilinkHidden:
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
