// ThemeToken.swift
import SwiftUI
import AppKit

/// 仕様書「物語: 紙とインク」の色を一箇所に集める。
///
/// ★ 実体は Assets.xcassets の Color Set。NSColor(named:) が返すのは
///   固定のRGBではなく「今の外観で解決される動的な色」なので、一度入れておけば
///   ライト⇔ダークの切り替えに自分で追随する。テーマ変更を検知して塗り直す
///   コードは要らない。逆に、どこかに固定色が残っているとそこだけ切り替わらない。
enum ThemeToken {
    // SwiftUI 用
    static let accent = Color("InkAccent")
    static let paper = Color("PaperBg")
    static let ink = Color("InkText")
    static let quote = Color("QuoteText")
    static let codeBg = Color("CodeBg")
    static let codeBorder = Color("CodeBorder")
    static let levelLabel = Color("LevelLabel")
    static let hr = Color("HrLine")

    // AppKit 用(NSTextView / NSLayoutManager はこちら)
    enum NS {
        static let accent = named("InkAccent", fallback: .systemRed)
        static let paper = named("PaperBg", fallback: .textBackgroundColor)
        static let ink = named("InkText", fallback: .textColor)
        static let quote = named("QuoteText", fallback: .secondaryLabelColor)
        static let codeBg = named("CodeBg", fallback: .textBackgroundColor)
        static let codeBorder = named("CodeBorder", fallback: .separatorColor)
        static let levelLabel = named("LevelLabel", fallback: .tertiaryLabelColor)
        static let hr = named("HrLine", fallback: .separatorColor)

        /// ★ `NSColor(named:)!` にしない。アセットが見つからないのは失敗であって
        ///   クラッシュではない。バンドルの外(テスト用のハーネスなど)から
        ///   同じコードを動かせなくなる代償が大きすぎる。
        private static func named(_ name: String, fallback: NSColor) -> NSColor {
            NSColor(named: name) ?? fallback
        }
    }
}
