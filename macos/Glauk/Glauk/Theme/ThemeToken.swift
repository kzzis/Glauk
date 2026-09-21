import SwiftUI
import AppKit

/// Color Set は外観に追従するが、配色テーマ変更時には参照名が変わるため取り直す。
enum ThemeToken {
    // SwiftUI 用
    static var accent: Color { Color(nsColor: NS.accent) }
    static var paper: Color { Color(nsColor: NS.paper) }
    static var ink: Color { Color(nsColor: NS.ink) }
    static var quote: Color { Color(nsColor: NS.quote) }
    static var codeBg: Color { Color(nsColor: NS.codeBg) }
    static var codeBorder: Color { Color(nsColor: NS.codeBorder) }
    static var levelLabel: Color { Color(nsColor: NS.levelLabel) }
    static var hr: Color { Color(nsColor: NS.hr) }

    // AppKit 用(NSTextView / NSLayoutManager はこちら)
    enum NS {
        static var accent: NSColor { named("InkAccent", fallback: .systemRed) }
        static var paper: NSColor { named("PaperBg", fallback: .textBackgroundColor) }
        static var ink: NSColor { named("InkText", fallback: .textColor) }
        static var quote: NSColor { named("QuoteText", fallback: .secondaryLabelColor) }
        static var codeBg: NSColor { named("CodeBg", fallback: .textBackgroundColor) }
        static var codeBorder: NSColor { named("CodeBorder", fallback: .separatorColor) }
        static var levelLabel: NSColor { named("LevelLabel", fallback: .tertiaryLabelColor) }
        static var hr: NSColor { named("HrLine", fallback: .separatorColor) }

        /// アセットのない検証環境でも利用できるようフォールバックする。
        private static func named(_ token: String, fallback: NSColor) -> NSColor {
            NSColor(named: GlaukTheme.current.name(token)) ?? fallback
        }
    }
}
