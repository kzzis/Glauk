// MarkdownLayoutManager.swift
import AppKit

final class MarkdownLayoutManager: NSLayoutManager {
    /// 引用の縦棒 / 区切り線の見た目。SyntaxHighlighter の EditorTypography と揃えること。
    var quoteBarColor = NSColor.systemRed
    var quoteBarWidth: CGFloat = 2
    var ruleColor = NSColor.separatorColor
    var codeBgColor = NSColor.textBackgroundColor
    var codeLangColor = NSColor.tertiaryLabelColor
    var codeCornerRadius: CGFloat = 6
    var inlineCodeCornerRadius: CGFloat = 3
    var tableRuleColor = NSColor.separatorColor
    var checkboxOnColor = NSColor.controlAccentColor
    var checkboxOffColor = NSColor.tertiaryLabelColor
    var checkboxSize: CGFloat = 13
    var bulletColor = NSColor.secondaryLabelColor
    var bulletRadius: CGFloat = 2
    var calloutTint: (String) -> NSColor = { _ in .systemBlue }
    var tagBgColor = NSColor.systemBlue.withAlphaComponent(0.18)
    var tagCornerRadius: CGFloat = 4

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

    /// 文字にぴったり沿った矩形を返す。
    /// ★ blockRects は行フラグメント(=行まるごと)を返すので、行内の一部を
    ///   囲みたいものに使ってはいけない。タグの下地が行全体に広がる。
    private func inlineRects(for key: NSAttributedString.Key,
                             in charRange: NSRange,
                             origin: NSPoint,
                             container: NSTextContainer) -> [NSRect] {
        guard let storage = textStorage else { return [] }
        var result: [NSRect] = []
        storage.enumerateAttribute(key, in: charRange) { value, range, _ in
            guard value != nil, range.length > 0 else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateEnclosingRects(forGlyphRange: glyphs,
                                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                    in: container) { rect, _ in
                result.append(rect.offsetBy(dx: origin.x, dy: origin.y))
            }
        }
        return result
    }

    /// 目印を付けた文字の「見た目の中心」を返す。
    /// ★ 行フラグメントの中心では駄目。lineHeightMultiple で行が伸びているぶん
    ///   文字より上にずれ、中黒やチェックボックスが宙に浮く。
    ///   ベースラインを基準にして、そこから文字の高さの分だけ持ち上げる。
    private func markerCenter(for range: NSRange,
                              in container: NSTextContainer,
                              origin: NSPoint) -> NSPoint? {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let rect = boundingRect(forGlyphRange: glyphs, in: container)
        guard rect.width > 0 else { return nil }

        let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let offset = location(forGlyphAt: glyphs.location)      // フラグメント内のベースライン
        let baseline = fragment.minY + offset.y
        let font = (textStorage?.attribute(.font, at: range.location, effectiveRange: nil)
            as? NSFont) ?? NSFont.systemFont(ofSize: 15)
        return NSPoint(x: origin.x + rect.midX,
                       y: origin.y + baseline - font.xHeight / 2)
    }

    /// 文字では表せない装飾(引用の縦棒・区切り線)をここで描く。
    /// テキストを書き換えずに見た目を足せるので、記法の文字列は原文のまま保てる。
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainer(forGlyphAt: glyphsToShow.location,
                                                                      effectiveRange: nil) else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let fullWidth = container.size.width - container.lineFragmentPadding * 2

        // --- コードブロック: 横幅いっぱいの角丸で塗り、右上に言語名を出す ---
        for (range, rect) in blockRects(for: .glaukCodeBlock, in: charRange, origin: origin) {
            let box = NSRect(x: origin.x + container.lineFragmentPadding, y: rect.minY,
                             width: fullWidth, height: rect.height)
            codeBgColor.setFill()
            NSBezierPath(roundedRect: box, xRadius: codeCornerRadius, yRadius: codeCornerRadius).fill()

            // ```swift の "swift" をブロックの右上に小さく添える
            var label: String?
            storage.enumerateAttribute(.glaukCodeLang, in: range) { value, _, stop in
                if let name = value as? String { label = name; stop.pointee = true }
            }
            if let label {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: codeLangColor,
                ]
                let text = label as NSString
                let size = text.size(withAttributes: attrs)
                text.draw(at: NSPoint(x: box.maxX - size.width - 10, y: box.minY + 6),
                          withAttributes: attrs)
            }
        }

        // --- タグ: 文字に沿った角丸の下地 ---
        for rect in inlineRects(for: .glaukTag, in: charRange, origin: origin, container: container) {
            let box = rect.insetBy(dx: -3, dy: 2)
            tagBgColor.setFill()
            NSBezierPath(roundedRect: box, xRadius: tagCornerRadius, yRadius: tagCornerRadius).fill()
        }

        // --- インラインコード: 文字に沿った小さな角丸 ---
        for rect in inlineRects(for: .glaukInlineCode, in: charRange, origin: origin, container: container) {
            let box = rect.insetBy(dx: -1, dy: 2)
            codeBgColor.setFill()
            NSBezierPath(roundedRect: box,
                         xRadius: inlineCodeCornerRadius,
                         yRadius: inlineCodeCornerRadius).fill()
        }

        // --- テーブル: 外枠 + 行の区切り(縦罫線は下の glaukTablePipe で描く) ---
        for (range, rect) in blockRects(for: .glaukTable, in: charRange, origin: origin) {
            let box = NSRect(x: origin.x + container.lineFragmentPadding, y: rect.minY,
                             width: fullWidth, height: rect.height)
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            tableRuleColor.setStroke()
            path.lineWidth = 1
            path.stroke()

            // 行と行の間に横罫線。たたんだ区切り行は高さが無いので飛ばす。
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var fragments: [NSRect] = []
            enumerateLineFragments(forGlyphRange: glyphs) { r, _, _, _, _ in
                if r.height > 1 { fragments.append(r) }
            }
            tableRuleColor.setFill()
            for fragment in fragments.dropLast() {
                NSRect(x: box.minX, y: origin.y + fragment.maxY, width: fullWidth, height: 1).fill()
            }
        }

        // --- テーブルの縦罫線: 透明にした `|` の位置に引く ---
        storage.enumerateAttribute(.glaukTablePipe, in: charRange) { value, range, _ in
            guard value != nil else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = boundingRect(forGlyphRange: glyphs, in: container)
            guard rect.width > 0 else { return }
            let x = (origin.x + rect.midX).rounded()
            let bar = NSRect(x: x, y: origin.y + rect.minY, width: 1, height: rect.height)
            self.tableRuleColor.setFill()
            bar.fill()
        }

        // --- コールアウト: 帯を敷いて左に色の縦棒 ---
        for (range, rect) in blockRects(for: .glaukCallout, in: charRange, origin: origin) {
            var type = "note"
            storage.enumerateAttribute(.glaukCallout, in: range) { value, _, stop in
                if let t = value as? String { type = t; stop.pointee = true }
            }
            let tint = calloutTint(type)
            let box = NSRect(x: origin.x + container.lineFragmentPadding, y: rect.minY,
                             width: fullWidth, height: rect.height)
            tint.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            tint.setFill()
            NSRect(x: box.minX, y: box.minY, width: 3, height: box.height).fill()
        }

        // --- リストの中黒: 透明にした `-` の位置に描く ---
        storage.enumerateAttribute(.glaukBullet, in: charRange) { value, range, _ in
            guard value != nil else { return }
            guard let center = self.markerCenter(for: range, in: container, origin: origin) else { return }
            let r = self.bulletRadius
            let dot = NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            self.bulletColor.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }

        // --- チェックボックス: 透明にした `[ ]` の位置に描く ---
        storage.enumerateAttribute(.glaukCheckbox, in: charRange) { value, range, _ in
            guard let done = value as? Bool else { return }
            guard let center = self.markerCenter(for: range, in: container, origin: origin) else { return }
            let side = self.checkboxSize
            let box = NSRect(x: (center.x - side / 2).rounded(),
                             y: (center.y - side / 2).rounded(),
                             width: side, height: side)
            let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
            if done {
                self.checkboxOnColor.setFill()
                path.fill()
                // ★ テキストの座標系は y が下向き。上向きの座標で組むと鉤が逆さになる。
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: box.minX + side * 0.24, y: box.midY))
                tick.line(to: NSPoint(x: box.minX + side * 0.43, y: box.maxY - side * 0.26))
                tick.line(to: NSPoint(x: box.minX + side * 0.78, y: box.minY + side * 0.26))
                tick.lineWidth = 2
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.setStroke()
                tick.stroke()
            } else {
                self.checkboxOffColor.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }

        storage.enumerateAttribute(.glaukQuote, in: charRange) { value, range, _ in
            guard value != nil else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, glyphRange, _ in
                // ★ 隠した `> ` は幅が0なので、直前の空行のフラグメントに吸い込まれる。
                //   実測: 空行の "\n" と "> " が同じフラグメントに入り、空行に縦棒が1本余分に出る。
                //   引用の始まりより前から始まるフラグメントは描かない。
                let chars = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                guard chars.location >= range.location else { return }
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
