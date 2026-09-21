import AppKit

/// 外部変更後のカーソル位置と文字範囲を計算する。
enum CursorPreserver {
    /// 変更箇所がカーソルより前なら、増減した行数だけずらす。後ろなら動かさない。
    static func adjust(location: Int, in text: NSString,
                       changedFromLine: Int, lineDelta: Int) -> Int {
        let changeStart = lineStart(of: changedFromLine, in: text)
        guard location > changeStart else { return min(location, text.length) }
        return max(0, min(location + lineDelta, text.length))
    }

    /// 先頭から走査するため O(行数)。リロード時にだけ使う。
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
