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
    case listMarker = 13
    case quoteMarker = 14, quoteText = 15
    case italicMarker = 16
    case strikeMarker = 17
    case linkHidden = 18, linkText = 19, linkURL = 20
    case hrule = 21
    case codeKeyword = 22, codeString = 23, codeNumber = 24, codeComment = 25
    case tableHeader = 26, tableRow = 27, tableDelimiter = 28, tablePipe = 29
    case codeType = 30, codeFunction = 31, codeLang = 32
    case heading4 = 33, heading5 = 34, heading6 = 35
    case taskMarker = 36, taskOpen = 37, taskDone = 38
    case highlightMarker = 39, highlight = 40
    case tag = 41
    case commentMarker = 42, comment = 43
    case footnote = 44
    case mathMarker = 45, math = 46
    case callout = 47
    case embedMarker = 48
    case escape = 49
    case blockID = 50
    case autoLink = 51
    case calloutBody = 52
    case codeAdded = 53, codeRemoved = 54, codeMeta = 55
}

struct Span {
    let range: NSRange
    let kind: SpanKind
}

extension NSAttributedString.Key {
    static let glaukHidden = NSAttributedString.Key("glauk.hidden")
    static let glaukLinkTarget = NSAttributedString.Key("glauk.linkTarget")
    /// 通常のリンク `[text](url)` の URL
    static let glaukLinkURL = NSAttributedString.Key("glauk.linkURL")
    /// 引用の縦棒を描く範囲の目印(MarkdownLayoutManagerが背景描画で使う)
    static let glaukQuote = NSAttributedString.Key("glauk.quote")
    /// 区切り線を描く範囲の目印
    static let glaukRule = NSAttributedString.Key("glauk.rule")
    /// コードブロックの角丸背景を描く範囲
    static let glaukCodeBlock = NSAttributedString.Key("glauk.codeBlock")
    /// インラインコードの角丸背景を描く範囲
    static let glaukInlineCode = NSAttributedString.Key("glauk.inlineCode")
    /// テーブル全体の枠を描く範囲
    static let glaukTable = NSAttributedString.Key("glauk.table")
    /// テーブルの見出し行(下に区切り線を描く)
    static let glaukTableHeader = NSAttributedString.Key("glauk.tableHeader")
    /// コードブロックの言語名(ブロックの右上に描く)
    static let glaukCodeLang = NSAttributedString.Key("glauk.codeLang")
    /// テーブルの縦罫線を描く位置(`|` の文字に付ける)
    static let glaukTablePipe = NSAttributedString.Key("glauk.tablePipe")
    /// チェックボックスを描く位置。値は完了なら true(`[x]` の3文字に付ける)
    static let glaukCheckbox = NSAttributedString.Key("glauk.checkbox")
    /// 中黒を描く位置(リストの `-` に付ける)
    static let glaukBullet = NSAttributedString.Key("glauk.bullet")
    /// コールアウトの帯を描く範囲。値は種類の文字列("note" など)
    static let glaukCallout = NSAttributedString.Key("glauk.callout")
    /// #タグ の角丸の下地を描く範囲
    static let glaukTag = NSAttributedString.Key("glauk.tag")
    /// diff の + / - の行。値は追加なら true(行の左に色帯を描く)
    static let glaukDiff = NSAttributedString.Key("glauk.diff")
    /// テーブルの縦罫線を引くx座標(テキストコンテナ基準)。値は [NSNumber]
    static let glaukTableColumns = NSAttributedString.Key("glauk.tableColumns")
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
