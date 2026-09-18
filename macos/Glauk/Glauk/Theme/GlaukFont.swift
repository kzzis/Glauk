// GlaukFont.swift
import AppKit

/// フォントの指定を一箇所に集める。
///
/// ★ 名前で引いて、見つからなければ次の候補へ落ちる。`NSFont(name:size:)` が
///   nil を返すのは「そのフォントが入っていない」という失敗であって、
///   異常ではない。強制アンラップしないこと。
/// ★ 指定するのは PostScript名。ファイル名でも表示名でもない。
///   ここを間違えると黙ってフォールバックが効き、「指定したのに反映されない」
///   という分かりにくい状態になる。
/// ★ フォントの同梱はしていない。入っていれば使い、無ければ落ちる。
enum GlaukFont {
    /// 候補を順に試し、最初に見つかったものを使う
    static func first(_ names: [String], size: CGFloat,
                      weight: NSFont.Weight = .regular) -> NSFont {
        for name in names {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// 見出し
    static func heading(level: Int, size: CGFloat) -> NSFont {
        first(["SourceSerif4-Semibold", "NotoSerifJP-Bold"], size: size, weight: .bold)
    }

    /// 本文。★ 等幅にしない。読み物としての見た目は、ここを
    ///   プロポーショナルにするかどうかで大きく変わる。
    ///   和文はシステムフォントからヒラギノへ自動で落ちる。
    static func body(size: CGFloat = 16) -> NSFont {
        for name in ["Inter-Regular", "NotoSansJP-Regular"] {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.systemFont(ofSize: size)
    }

    /// コードと AIペイン
    static func mono(size: CGFloat = 13) -> NSFont {
        first(["IBMPlexMono", "IBMPlexMono-Regular"], size: size)
    }
}
