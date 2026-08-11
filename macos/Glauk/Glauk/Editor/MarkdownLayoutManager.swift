// MarkdownLayoutManager.swift
import AppKit

final class MarkdownLayoutManager: NSLayoutManager {
    /// 引用の縦棒 / 区切り線の見た目。SyntaxHighlighter の EditorTypography と揃えること。
    var quoteBarColor = NSColor.systemRed
    var quoteBarWidth: CGFloat = 2
    var ruleColor = NSColor.separatorColor

    /// 文字では表せない装飾(引用の縦棒・区切り線)をここで描く。
    /// テキストを書き換えずに見た目を足せるので、記法の文字列は原文のまま保てる。
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainer(forGlyphAt: glyphsToShow.location,
                                                                      effectiveRange: nil) else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

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
