// NSRange+Range.swift
import Foundation

// ★ 構文ハイライトだけでなく、にじみやカーソル保全からも使う。
//   SyntaxHighlighter.swift の末尾に置いたままだと依存が見えないので分けた。
extension NSRange {
    func union(_ other: NSRange) -> NSRange {
        let start = Swift.min(location, other.location)
        let end = Swift.max(NSMaxRange(self), NSMaxRange(other))
        return NSRange(location: start, length: end - start)
    }

    /// `length` の範囲内に収まるよう location/length を切り詰める
    func clamped(to length: Int) -> NSRange {
        let start = Swift.min(location, length)
        let end = Swift.min(NSMaxRange(self), length)
        return NSRange(location: start, length: Swift.max(0, end - start))
    }
}
