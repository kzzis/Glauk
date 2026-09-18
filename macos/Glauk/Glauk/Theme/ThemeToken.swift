// ThemeToken.swift
import SwiftUI
import AppKit

/// 仕様書「物語: 紙とインク」の色を一箇所に集める。
///
/// ★ 実体は Assets.xcassets の Color Set。NSColor(named:) が返すのは
///   固定のRGBではなく「今の外観で解決される動的な色」なので、一度入れておけば
///   ライト⇔ダークの切り替えに自分で追随する。塗り直すコードは要らない。
/// ★ ただし**テーマ(配色)の切り替えは別**。参照する Color Set の名前ごと
///   変わるので、こちらは取り直しが要る。だから `let` ではなく計算プロパティ。
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

        /// ★ `NSColor(named:)!` にしない。アセットが見つからないのは失敗であって
        ///   クラッシュではない。バンドルの外(検証用のハーネスなど)から
        ///   同じコードを動かせなくなる代償が大きすぎる。
        private static func named(_ token: String, fallback: NSColor) -> NSColor {
            NSColor(named: GlaukTheme.current.name(token)) ?? fallback
        }
    }
}
