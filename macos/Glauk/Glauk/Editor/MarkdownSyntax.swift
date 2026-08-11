// MarkdownSyntax.swift
import AppKit
import GlaukCore

enum SpanKind: UInt8 {
    case heading1 = 1, heading2 = 2, heading3 = 3
    case boldMarker = 4
    case wikilinkHidden = 5, wikilinkName = 6, wikilinkTarget = 7
    case codeFence = 8, codeBlock = 9
    case inlineCodeMarker = 10, inlineCode = 11
    case frontmatter = 12
}

struct Span {
    let range: NSRange
    let kind: SpanKind
}

extension NSAttributedString.Key {
    static let glaukHidden = NSAttributedString.Key("glauk.hidden")
    static let glaukLinkTarget = NSAttributedString.Key("glauk.linkTarget")
}

enum MarkdownParser {
    static func spans(in text: String) -> [Span] {
        let bytes = Array(text.utf8)
        if bytes.isEmpty { return [] }

        var count = 0
        guard let raw = bytes.withUnsafeBufferPointer({ buf in
            glauk_parse_spans(buf.baseAddress, buf.count, &count)
        }) else { return [] }
        defer { glauk_free_spans(raw, count) }   // ★ 取得の直後に解放を予約

        var result: [Span] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let s = raw[i]
            guard let kind = SpanKind(rawValue: s.kind) else { continue }
            result.append(Span(range: NSRange(location: Int(s.start), length: Int(s.len)),
                               kind: kind))
        }
        return result
    }
}
