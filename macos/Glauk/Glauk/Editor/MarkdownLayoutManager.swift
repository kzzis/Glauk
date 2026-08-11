// MarkdownLayoutManager.swift
import AppKit

final class MarkdownLayoutManager: NSLayoutManager {
    /// 引用の縦棒 / 区切り線の見た目。SyntaxHighlighter の EditorTypography と揃えること。
    var quoteBarColor = NSColor.systemRed
    var quoteBarWidth: CGFloat = 2
    var ruleColor = NSColor.separatorColor
    var codeBgColor = NSColor.textBackgroundColor
    var codeCornerRadius: CGFloat = 6
    var inlineCodeCornerRadius: CGFloat = 3
    var tableRuleColor = NSColor.separatorColor

    /// 属性が連続している範囲ごとに、その行たちを囲む矩形を返す
    private func blockRects(for key: NSAttributedString.Key,
                            in charRange: NSRange,
                            origin: NSPoint) -> [(NSRange, NSRect)] {
        guard let storage = textStorage else { return [] }
        var result: [(NSRange, NSRect)] = []
        storage.enumerateAttribute(key, in: charRange) { value, range, _ in
            guard value != nil, range.length > 0 else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var union: NSRect?
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                union = union.map { $0.union(rect) } ?? rect
            }
            if let u = union {
                result.append((range, u.offsetBy(dx: origin.x, dy: origin.y)))
            }
        }
        return result
    }

    /// 文字では表せない装飾(引用の縦棒・区切り線)をここで描く。
    /// テキストを書き換えずに見た目を足せるので、記法の文字列は原文のまま保てる。
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainer(forGlyphAt: glyphsToShow.location,
                                                                      effectiveRange: nil) else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let fullWidth = container.size.width - container.lineFragmentPadding * 2

        // --- コードブロック: 横幅いっぱいの角丸で塗る(Obsidianと同じ見た目) ---
        for (_, rect) in blockRects(for: .glaukCodeBlock, in: charRange, origin: origin) {
            let box = NSRect(x: origin.x + container.lineFragmentPadding, y: rect.minY,
                             width: fullWidth, height: rect.height)
            codeBgColor.setFill()
            NSBezierPath(roundedRect: box, xRadius: codeCornerRadius, yRadius: codeCornerRadius).fill()
        }

        // --- インラインコード: 文字に沿った小さな角丸 ---
        for (_, rect) in blockRects(for: .glaukInlineCode, in: charRange, origin: origin) {
            let box = rect.insetBy(dx: -1, dy: 1)
            codeBgColor.setFill()
            NSBezierPath(roundedRect: box,
                         xRadius: inlineCodeCornerRadius,
                         yRadius: inlineCodeCornerRadius).fill()
        }

        // --- テーブル: 枠と、見出しの下の線 ---
        for (_, rect) in blockRects(for: .glaukTable, in: charRange, origin: origin) {
            let box = NSRect(x: origin.x + container.lineFragmentPadding, y: rect.minY,
                             width: fullWidth, height: rect.height)
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            tableRuleColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        for (_, rect) in blockRects(for: .glaukTableHeader, in: charRange, origin: origin) {
            let line = NSRect(x: origin.x + container.lineFragmentPadding, y: rect.maxY - 1,
                              width: fullWidth, height: 1)
            tableRuleColor.setFill()
            line.fill()
        }

        storage.enumerateAttribute(.glaukQuote, in: charRange) { value, range, _ in
            guard value != nil else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                let bar = NSRect(x: origin.x + rect.minX + 4,
                                 y: origin.y + rect.minY + 2,
                                 width: self.quoteBarWidth,
                                 height: rect.height - 4)
                self.quoteBarColor.setFill()
                bar.fill()
            }
        }

        storage.enumerateAttribute(.glaukRule, in: charRange) { value, range, _ in
            guard value != nil else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                let line = NSRect(x: origin.x + rect.minX,
                                  y: origin.y + rect.midY,
                                  width: container.size.width - 8,
                                  height: 1)
                self.ruleColor.setFill()
                line.fill()
            }
        }
    }

    override func setGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) {
        guard let storage = textStorage else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes,
                            font: aFont, forGlyphRange: glyphRange)
            return
        }

        var patched = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var changed = false
        for i in 0..<glyphRange.length {
            let ci = charIndexes[i]
            guard ci < storage.length else { continue }
            if storage.attribute(.glaukHidden, at: ci, effectiveRange: nil) != nil {
                patched[i].insert(.null)     // ← このグリフを描画しない
                changed = true
            }
        }

        // 1つも隠さないなら、コピーを渡さず元をそのまま流す(無駄を省く)
        guard changed else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes,
                            font: aFont, forGlyphRange: glyphRange)
            return
        }

        patched.withUnsafeBufferPointer { buf in
            super.setGlyphs(glyphs, properties: buf.baseAddress!, characterIndexes: charIndexes,
                            font: aFont, forGlyphRange: glyphRange)
        }
    }
}
