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
    static var sidebar: Color { Color(nsColor: NS.sidebar) }
    static var sidebarField: Color { Color(nsColor: NS.sidebarField) }
    static var sidebarSecondary: Color { Color(nsColor: NS.sidebarSecondary) }
    static var shellDivider: Color { Color(nsColor: NS.shellDivider) }

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
        static var sidebar: NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1)
                    : NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1)
            }
        }
        static var sidebarField: NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(srgbRed: 0.19, green: 0.20, blue: 0.22, alpha: 1)
                    : .white
            }
        }
        static var sidebarSecondary: NSColor { .secondaryLabelColor }
        static var shellDivider: NSColor { .separatorColor }

        /// アセットのない検証環境でも利用できるようフォールバックする。
        private static func named(_ token: String, fallback: NSColor) -> NSColor {
            NSColor(named: GlaukTheme.current.name(token)) ?? fallback
        }
    }
}
