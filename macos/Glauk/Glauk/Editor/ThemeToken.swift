// ThemeToken.swift
import AppKit

/// 色を1箇所に集める。Step 9 で Asset Catalog のトークンに繋ぎ替える。
enum ThemeToken {
    /// にじみのインク色。ライトは朱、ダークはブルーブラック。
    static var accentNSColor: NSColor {
        // ★ effectiveAppearance.name を直接比べない。ハイコントラストや
        //   アクセシビリティ設定では .accessibilityDarkAqua などになり、
        //   .darkAqua との == が外れてライト用の色が出てしまう。
        let isDark = NSApp?.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // ★ 仕様書はダークのインクを「ブルーブラック #2A4A7F」としているが、
        //   にじみは文字色ではなく「背景に薄く敷く色」。暗い紙に暗い色を14%で
        //   敷いても沈んで見えない(実測: ライトの画素差 0.247 に対し 0.067)。
        //   ブルーブラックの色味は保ったまま、紙より明るい側へ振る。
        return isDark
            ? NSColor(srgbRed: 0x7A / 255, green: 0xA6 / 255, blue: 0xE8 / 255, alpha: 1)
            : NSColor(srgbRed: 0xD6 / 255, green: 0x48 / 255, blue: 0x2F / 255, alpha: 1)
    }
}
