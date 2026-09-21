import AppKit

func dynamicColor(dark: UInt32, light: UInt32) -> NSColor {
    func make(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
    return NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? make(dark) : make(light)
    }
}

struct EditorTypography {
    /// ハイライトで上書きするため、MarkdownTextView の textView.font と揃える。
    var body = GlaukFont.body(size: 16)

    /// 本文サイズを変えても見出しの大小関係を保つ。
    func heading(_ level: Int) -> NSFont {
        let scale: [CGFloat] = [1.90, 1.55, 1.30, 1.15, 1.06, 1.00]
        let size = (body.pointSize * scale[min(max(level, 1), 6) - 1]).rounded()
        return GlaukFont.heading(level: level, size: size)
    }
    /// 等幅フォントの変換が semibold に留まる場合に、bold の太さを補う。
    var bold: (NSFont) -> NSFont = { base in
        let converted = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        let traits = converted.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? CGFloat) ?? 0
        if weight >= NSFont.Weight.bold.rawValue { return converted }
        return NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .bold)
    }
    var accent = ThemeToken.NS.accent
    var muted = ThemeToken.NS.quote
    var ink = ThemeToken.NS.ink
    var levelLabel = ThemeToken.NS.levelLabel
    var levelLabelFont = GlaukFont.mono(size: 9)
    var hrLine = ThemeToken.NS.hr
    var code = GlaukFont.mono(size: 14)
    /// グリフを隠すだけでは行高が残るため、極小フォントで潰す。
    var folded = NSFont.systemFont(ofSize: 0.01)
    /// 隠した ``` の行に使う。行は残るので、これがブロック上下の余白の高さになる。
    var codePadding = NSFont.systemFont(ofSize: 7)

    /// 日本語のフォールバックで斜体が失われないよう、フォントではなく傾きを指定する。
    var italicObliqueness: CGFloat = 0.2

    var codeKeyword = dynamicColor(dark: 0xFF7B72, light: 0xCF222E)
    var codeType = dynamicColor(dark: 0x4EC9B0, light: 0x0F766E) // 大文字始まりの識別子
    var codeFunction = dynamicColor(dark: 0x79C0FF, light: 0x0969DA)
    var codeString = dynamicColor(dark: 0xE3B341, light: 0x8B5000)
    var codeNumber = dynamicColor(dark: 0xFFA657, light: 0xB35900)
    var codeComment = NSColor.secondaryLabelColor
    var codeLangLabel = ThemeToken.NS.quote
    var codeAdded = dynamicColor(dark: 0x7EE787, light: 0x116329)
    var codeRemoved = dynamicColor(dark: 0xFFA198, light: 0x82071E)
    var codeMeta = dynamicColor(dark: 0x8B949E, light: 0x57606A)
    var codeAddedBg = dynamicColor(dark: 0x0F3A20, light: 0xDAFBE1)
    var codeRemovedBg = dynamicColor(dark: 0x4A1418, light: 0xFFEBE9)

    var quoteBar = ThemeToken.NS.accent
    var quoteBarWidth: CGFloat = 2

    /// 本文・引用・リストの行高を揃える。
    static let lineHeight: CGFloat = 1.7

    /// MarkdownTextView の defaultParagraphStyle と必ず揃えること
    var bodyParagraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = EditorTypography.lineHeight
        p.paragraphSpacing = 8
        return p
    }()

    /// TextKit 1 では paragraphSpacingBefore が効かないため、行高で上の余白を作る。
    /// 見出しを後続本文に寄せるため、下には余白を足さない。
    var headingParagraph: (Int) -> NSParagraphStyle = { level in
        let lineHeight: [CGFloat] = [2.00, 1.95, 1.90, 1.80, 1.75, 1.75]
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = lineHeight[min(max(level, 1), 6) - 1]
        p.paragraphSpacing = 0
        return p
    }
    var quoteParagraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = EditorTypography.lineHeight
        p.firstLineHeadIndent = 16
        p.headIndent = 16
        return p
    }()
    /// `level` は入れ子の深さ。折り返しはマーカーの右に揃える。
    var listParagraph: (Int) -> NSParagraphStyle = { level in
        let step: CGFloat = 20
        let base = step * CGFloat(level)
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = EditorTypography.lineHeight
        p.firstLineHeadIndent = base
        p.headIndent = base + step
        return p
    }
    var codeParagraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.35
        p.firstLineHeadIndent = 20
        p.headIndent = 20
        p.tailIndent = -20
        return p
    }()

    var codeCornerRadius: CGFloat = 6
    var inlineCodeCornerRadius: CGFloat = 3
    var tableRule = ThemeToken.NS.hr
    var codeBg = ThemeToken.NS.codeBg
    var codeBorder = ThemeToken.NS.codeBorder

    var highlightBg = dynamicColor(dark: 0x5C4B00, light: 0xFFF3A3)
    var tagText = dynamicColor(dark: 0x9BD1FF, light: 0x0A5BA8)
    var tagBg = dynamicColor(dark: 0x1E3A5F, light: 0xDCEBFB)
    var tagCornerRadius: CGFloat = 4
    var commentText = NSColor.tertiaryLabelColor
    var math = GlaukFont.mono(size: 14)
    var mathText = dynamicColor(dark: 0xC3A6FF, light: 0x6B21A8)
    var superscript = NSFont.systemFont(ofSize: 10)
    var checkboxSize: CGFloat = 13
    var checkboxOn = NSColor.controlAccentColor
    var checkboxOff = NSColor.tertiaryLabelColor
    var bulletColor = NSColor.secondaryLabelColor
    var bulletRadius: CGFloat = 2

    var calloutTint: (String) -> NSColor = { type in
        switch type.lowercased() {
        case "warning", "caution", "attention": return .systemOrange
        case "danger", "error", "bug", "failure", "fail", "missing": return .systemRed
        case "success", "check", "done", "tip", "hint", "important": return .systemGreen
        case "question", "help", "faq": return .systemPurple
        case "example": return .systemPink
        case "quote", "cite": return .systemGray
        default: return .systemBlue      // note / info / todo / abstract …
        }
    }
}
