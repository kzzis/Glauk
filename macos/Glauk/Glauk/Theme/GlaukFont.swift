import AppKit

/// フォントは同梱せず、PostScript 名で検索して未導入ならフォールバックする。
enum GlaukFont {
    static func first(_ names: [String], size: CGFloat,
                      weight: NSFont.Weight = .regular) -> NSFont {
        for name in names {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func heading(level: Int, size: CGFloat) -> NSFont {
        first(["SourceSerif4-Semibold", "NotoSerifJP-Bold"], size: size, weight: .bold)
    }

    static func body(size: CGFloat = 16) -> NSFont {
        first(["Inter-Regular", "NotoSansJP-Regular"], size: size)
    }

    /// ターミナルの桁を保つため、フォールバックも等幅にする。
    static func mono(size: CGFloat = 13) -> NSFont {
        for name in ["IBMPlexMono", "IBMPlexMono-Regular"] {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
