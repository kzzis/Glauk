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
        return isDark
            ? NSColor(srgbRed: 0x2A / 255, green: 0x4A / 255, blue: 0x7F / 255, alpha: 1)
            : NSColor(srgbRed: 0xD6 / 255, green: 0x48 / 255, blue: 0x2F / 255, alpha: 1)
    }
}
