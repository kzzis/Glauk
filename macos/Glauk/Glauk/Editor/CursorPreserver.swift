// CursorPreserver.swift
import AppKit

/// 外から書き換えられたときに、カーソルを同じ文に留めておくための計算。
///
/// ★ ここが雑だと、エージェントが書くたびに視点が先頭へ飛ぶ。
///   「AIが書いても書き手の集中を切らさない」という仕様の核心にあたる。
enum CursorPreserver {
    /// 変更箇所がカーソルより前なら、増減した行数だけずらす。後ろなら動かさない。
    static func adjust(location: Int, in text: NSString,
                       changedFromLine: Int, lineDelta: Int) -> Int {
        let changeStart = lineStart(of: changedFromLine, in: text)
        guard location > changeStart else { return min(location, text.length) }
        return max(0, min(location + lineDelta, text.length))
    }

    /// ★ 先頭から数えるので O(行数)。リロード時に1回だけ呼ぶこと。
    ///   毎フレーム呼ぶと1万行のファイルで目に見えて重くなる。
    static func lineStart(of lineIndex: Int, in text: NSString) -> Int {
        var index = 0
        var line = 0
        while line < lineIndex && index < text.length {
            index = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0)))
            line += 1
        }
        return index
    }

    /// 行番号の範囲を文字範囲に変換する。
    /// 一時属性に渡すのは文字範囲なので、`changedLineRange` の結果はここを通す。
    static func characterRange(forLines lines: Range<Int>, in text: NSString) -> NSRange {
        let start = lineStart(of: lines.lowerBound, in: text)
        guard lines.upperBound > lines.lowerBound else {
            return NSRange(location: start, length: 0)
        }
        let endLineStart = lineStart(of: lines.upperBound - 1, in: text)
        let endLine = text.lineRange(for: NSRange(location: endLineStart, length: 0))
        return NSRange(location: start, length: max(0, NSMaxRange(endLine) - start))
    }
}
