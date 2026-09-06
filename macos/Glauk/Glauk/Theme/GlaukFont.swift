// GlaukFont.swift
import AppKit

/// フォントの指定を一箇所に集める。
///
/// ★ 名前で引いて、見つからなければ次の候補へ落ちる。`NSFont(name:size:)` が
///   nil を返すのは「そのフォントが入っていない」という失敗であって、
///   異常ではない。同梱フォントを外した環境でも落ちないようにする。
/// ★ 指定するのは PostScript名。ファイル名でも表示名でもない。
///   ここを間違えると黙ってフォールバックが効き、「同梱したのに反映されない」
///   という分かりにくい状態になる。
enum GlaukFont {
    /// 候補を順に試し、最初に見つかったものを使う
    static func first(_ names: [String], size: CGFloat,
                      weight: NSFont.Weight = .regular) -> NSFont {
        for name in names {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// 見出し。明朝で「紙とインク」の物語を担う場所。
    static func heading(level: Int, size: CGFloat) -> NSFont {
        first(["GenEiNijimiMincho-Regular", "SourceSerif4-Semibold", "NotoSerifJP-Bold"],
              size: size, weight: .bold)
    }

    /// 本文
    static func body(size: CGFloat = 15) -> NSFont {
        first(["Inter-Regular", "NotoSansJP-Regular", "IBMPlexMono"], size: size)
    }

    /// コードと AIペイン
    static func mono(size: CGFloat = 13) -> NSFont {
        first(["IBMPlexMono", "IBMPlexMono-Regular"], size: size)
    }

    #if DEBUG
    /// 同梱フォントが登録されたかを起動時に一度だけ確かめる用。
    /// 落ちたフォールバックを黙って使っていると気づけない。
    static func report() {
        let checks = [
            ("見出し", ["GenEiNijimiMincho-Regular", "SourceSerif4-Semibold", "NotoSerifJP-Bold"]),
            ("本文", ["Inter-Regular", "NotoSansJP-Regular", "IBMPlexMono"]),
            ("等幅", ["IBMPlexMono", "IBMPlexMono-Regular"]),
        ]
        for (label, names) in checks {
            let found = names.first { NSFont(name: $0, size: 12) != nil }
            print("[font] \(label): \(found ?? "システムフォントにフォールバック")")
        }
    }
    #endif
}
