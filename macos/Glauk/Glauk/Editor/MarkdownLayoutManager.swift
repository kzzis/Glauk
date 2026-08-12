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
    var diffAddedBgColor = NSColor.systemGreen.withAlphaComponent(0.14)
    var diffRemovedBgColor = NSColor.systemRed.withAlphaComponent(0.14)
    var diffAddedBarColor = NSColor.systemGreen
    var diffRemovedBarColor = NSColor.systemRed

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
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, fragGlyphs, _ in
                // ★ 行頭に来た隠し文字(``` や > や `)は幅が0なので、直前の行の
                //   フラグメントに吸い込まれる。そのぶんまで囲むと、ブロックが
                //   1行上まで伸びる。範囲の始まりより前から始まるフラグメントは数えない。
                let chars = self.characterRange(forGlyphRange: fragGlyphs, actualGlyphRange: nil)
                guard chars.location >= range.location else { return }
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

            // ★ 端の隠し文字を落としてから測る。
            //   隠したグリフは幅が0なので、行頭の `` ` `` は「直前の行」の
            //   フラグメントに入る(実測: 空行の "\n" と `` ` `` が同じ断片)。
            //   その状態だと enumerateEnclosingRects が「2行にまたがる選択」とみなし、
            //   前の空行が横幅いっぱいに塗られる。
            var trimmed = range
            while trimmed.length > 0,
                  storage.attribute(.glaukHidden, at: trimmed.location, effectiveRange: nil) != nil {
                trimmed.location += 1
                trimmed.length -= 1
            }
            while trimmed.length > 0,
                  storage.attribute(.glaukHidden, at: NSMaxRange(trimmed) - 1,
                                    effectiveRange: nil) != nil {
                trimmed.length -= 1
            }
            guard trimmed.length > 0 else { return }

            let glyphs = glyphRange(forCharacterRange: trimmed, actualCharacterRange: nil)
            enumerateEnclosingRects(forGlyphRange: glyphs,
                                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                    in: container) { rect, _ in
                guard rect.width > 0.5 else { return }
                result.append(self.hugText(rect, charIndex: trimmed.location)
                    .offsetBy(dx: origin.x, dy: origin.y))
            }
        }
        return result
    }

    /// 行フラグメントの高さではなく、文字そのものの高さに合わせた矩形にする。
    /// ★ lineHeightMultiple で増えた分は文字の「上」に付く。フラグメントの高さのまま
    ///   下地を敷くと、1行ぶん上にずれて「上の行に帯が出ている」ように見える。
    private func hugText(_ rect: NSRect, charIndex: Int) -> NSRect {
        let glyph = glyphIndexForCharacter(at: charIndex)
        guard glyph < numberOfGlyphs else { return rect }
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = fragment.minY + location(forGlyphAt: glyph).y
        let font = (textStorage?.attribute(.font, at: charIndex, effectiveRange: nil)
            as? NSFont) ?? NSFont.systemFont(ofSize: 15)
        return NSRect(x: rect.minX,
                      y: baseline - font.ascender,
                      width: rect.width,
                      height: font.ascender - font.descender)
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

        // --- diff の + / - 行: コードブロックの中に薄い下地を敷く ---
        // ★ コードブロックの角丸の「あと」に描く。先に描くと上から塗り潰される。
        for (range, rect) in blockRects(for: .glaukDiff, in: charRange, origin: origin) {
            guard let added = storage.attribute(.glaukDiff, at: range.location,
                                                effectiveRange: nil) as? Bool else { continue }
            let box = NSRect(x: origin.x + container.lineFragmentPadding, y: rect.minY,
                             width: fullWidth, height: rect.height)
            (added ? diffAddedBgColor : diffRemovedBgColor).setFill()
            box.fill()
            // 左端に濃い縦帯。色が薄くても + と - を見分けられるように。
            (added ? diffAddedBarColor : diffRemovedBarColor).setFill()
            NSRect(x: box.minX, y: box.minY, width: 2, height: box.height).fill()
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

        // --- テーブルの縦罫線 ---
        // ★ 桁揃えができた表は「列の目標位置」に引く。実際に置かれた `|` の位置で
        //   引くと、計測と組版の差が残って行ごとに数ptずれる(実測3.5pt)。
        var ruledTables: [NSRange] = []
        for (range, rect) in blockRects(for: .glaukTableColumns, in: charRange, origin: origin) {
            guard let xs = storage.attribute(.glaukTableColumns, at: range.location,
                                             effectiveRange: nil) as? [NSNumber] else { continue }
            ruledTables.append(range)
            tableRuleColor.setFill()
            for x in xs {
                NSRect(x: (origin.x + CGFloat(x.doubleValue)).rounded(),
                       y: rect.minY, width: 1, height: rect.height).fill()
            }
        }

        // 桁揃えを止めている表(カーソルが乗っている表)は `|` の位置に引く
        storage.enumerateAttribute(.glaukTablePipe, in: charRange) { value, range, _ in
            guard value != nil else { return }
            if ruledTables.contains(where: { NSIntersectionRange($0, range).length > 0 }) { return }
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
