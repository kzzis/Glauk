// WikilinkCompletion.swift
import AppKit

final class WikilinkCompletion {
    private let index: NoteIndex
    init(index: NoteIndex) { self.index = index }

    /// カーソル直前の未閉じ `[[` を探し、その後ろ(クエリ部分)の範囲を返す
    func openBracketRange(in text: NSString, cursor: Int) -> NSRange? {
        guard cursor >= 2 else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
        let head = NSRange(location: lineRange.location, length: cursor - lineRange.location)
        let line = text.substring(with: head)

        guard let openIdx = line.range(of: "[[", options: .backwards) else { return nil }
        let afterOpen = line[openIdx.upperBound...]
        if afterOpen.contains("]]") { return nil }      // 既に閉じている

        let queryLength = afterOpen.utf16.count
        // ★ NSRange は UTF-16 基準なので、utf16ビューで距離を測る
        let offset = line.utf16.distance(from: line.utf16.startIndex, to: openIdx.upperBound)
        return NSRange(location: head.location + offset, length: queryLength)
    }

    @MainActor
    func completions(for query: String) -> [String] {
        index.candidates(matching: query).map { $0 + "]]" }
    }
}
