// SyntaxHighlighter.swift
import AppKit

/// ライト/ダークで色を切り替える。Step 9 で Asset Catalog のColor Setに移す。
func dynamicColor(dark: UInt32, light: UInt32) -> NSColor {
    func make(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
    return NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? make(dark) : make(light)
    }
}

struct EditorTypography {
    /// MarkdownTextView が textView.font に入れているものと必ず揃えること。
    /// ここがズレると applySpans が全文の .font を上書きしてしまい、等幅で書いているつもりが
    /// プロポーショナルで表示される(太字の差も分かりにくくなる)。
    var body = NSFont(name: "IBMPlexMono", size: 15)
        ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    var heading: (Int) -> NSFont = { level in
        let sizes: [CGFloat] = [28, 22, 18]
        return NSFont.systemFont(ofSize: sizes[min(level, 3) - 1], weight: .bold)
    }
    /// システム等幅フォントに対しては、NSFontManager の変換もディスクリプタの .bold も
    /// **Semibold(weight 0.30)** しか返さず「太くなっていない」ように見える。
    /// 変換結果のウェイトを確かめ、bold に届かなければ等幅の bold ウェイト(0.40)を使う。
    var bold: (NSFont) -> NSFont = { base in
        let converted = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        let traits = converted.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? CGFloat) ?? 0
        if weight >= NSFont.Weight.bold.rawValue { return converted }
        return NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .bold)
    }
    var accent = NSColor.systemRed      // Step 9 でテーマトークンに差し替え
    var muted = NSColor.secondaryLabelColor
    var ink = NSColor.textColor
    /// コードは本文より少し小さい等幅。本文が既に等幅なのでフォント自体は同系だが、
    /// Step 9 で本文がサンセリフになったときにここだけ等幅で残るように分けておく。
    var code = NSFont(name: "IBMPlexMono", size: 14)
        ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    /// 「たたむ」ためのフォント。グリフを消すだけでは行が1行分残るため(実測: 4行が1行分残った)、
    /// 極小フォントを併用して行の高さごと潰す。
    var folded = NSFont.systemFont(ofSize: 0.01)
    /// 隠した ``` の行に使う。行は残るので、これがブロック上下の余白の高さになる。
    var codePadding = NSFont.systemFont(ofSize: 7)

    /// 斜体は「フォントの差し替え」ではなく「傾き」で表す。
    /// ★ 日本語には斜体を持つフォントが無いため、斜体フォントを指定しても AppKit の
    ///   属性補正が日本語を描けるフォント(HiraKaku)へ差し替え、斜体が消える。
    ///   実測: "latin" → …Monospaced-RegularItalic のまま / "日本語" → HiraKaku-W4(italic=false)。
    ///   obliqueness ならフォントに関係なく効く。
    var italicObliqueness: CGFloat = 0.2

    // --- コードのシンタックスハイライト ---
    // ライト/ダークで色を切り替える。暗い側は GitHub Dark 系の配色に寄せている。
    var codeKeyword = dynamicColor(dark: 0xFF7B72, light: 0xCF222E) // var / let など
    var codeType = dynamicColor(dark: 0x4EC9B0, light: 0x0F766E) // 大文字始まりの識別子
    var codeFunction = dynamicColor(dark: 0x79C0FF, light: 0x0969DA) // 呼び出し
    var codeString = dynamicColor(dark: 0xE3B341, light: 0x8B5000)
    var codeNumber = dynamicColor(dark: 0xFFA657, light: 0xB35900)
    var codeComment = NSColor.secondaryLabelColor
    /// ブロック右上に出す言語名
    var codeLangLabel = NSColor.tertiaryLabelColor

    /// 引用の縦棒の色と太さ
    var quoteBar = NSColor.systemRed
    var quoteBarWidth: CGFloat = 2

    /// MarkdownTextView の defaultParagraphStyle と必ず揃えること
    var bodyParagraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.55
        return p
    }()
    /// 引用は字下げして、空いた左側に縦棒を描く
    var quoteParagraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.55
        p.firstLineHeadIndent = 16
        p.headIndent = 16
        return p
    }()
    /// リストは折り返した2行目以降がマーカーの右に揃うようにする
    var listParagraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.55
        p.headIndent = 20
        return p
    }()
    /// コードブロック / テーブルは角丸の内側に余白を作り、行間も詰める
    var codeParagraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.35
        p.firstLineHeadIndent = 20
        p.headIndent = 20
        p.tailIndent = -20
        return p
    }()

    /// コードブロックの角丸の丸み
    var codeCornerRadius: CGFloat = 6
    var inlineCodeCornerRadius: CGFloat = 3
    /// テーブルの罫線
    var tableRule = NSColor.separatorColor
    /// glauk-design-doc.md の CodeBg(Light #EFEDE8 / Dark #26262A)
    var codeBg = dynamicColor(dark: 0x26262A, light: 0xEFEDE8)
}

final class SyntaxHighlighter {
    private let typography: EditorTypography
    /// 未作成ノートの区別表示に使う。Coordinator から NoteIndex を差し込む
    var noteExists: (String) -> Bool = { _ in true }

    init(typography: EditorTypography = .init()) { self.typography = typography }

    /// 文書全体を再計算する(初期表示など)
    func apply(to storage: NSTextStorage, cursorLine: NSRange?) {
        applySpans(to: storage, in: NSRange(location: 0, length: storage.length), cursorLine: cursorLine)
    }

    /// `scope` の範囲だけを再計算する
    ///
    /// ★ 実際に塗る範囲は、コードフェンスとフロントマターの境界まで広げる。
    ///   途中で切ると開きの ``` や --- が見えないまま解析することになり、
    ///   中身が通常のMarkdownとして解釈されてしまう。カーソル行だけを塗り直す
    ///   呼び出し(カーソルの出入り)でも同じ拡張が要るので、ここで面倒を見る。
    func applySpans(to storage: NSTextStorage, in requestedScope: NSRange, cursorLine: NSRange?) {
        guard NSMaxRange(requestedScope) <= storage.length else { return }
        let ns = storage.string as NSString
        let scope = expandToBlockBoundaries(in: ns, scope: requestedScope)
        let scopedText = ns.substring(with: scope)
        let spans = MarkdownParser.spans(in: scopedText).map { span in
            Span(range: NSRange(location: span.range.location + scope.location, length: span.range.length),
                 kind: span.kind)
        }

        storage.beginEditing()
        storage.removeAttribute(.glaukHidden, range: scope)
        // 前回の結果を消しておかないと、記法を消したあとも背景や下線が残る
        storage.removeAttribute(.backgroundColor, range: scope)
        storage.removeAttribute(.underlineStyle, range: scope)
        storage.addAttribute(.font, value: typography.body, range: scope)
        storage.addAttribute(.foregroundColor, value: typography.ink, range: scope)

        storage.removeAttribute(.glaukQuote, range: scope)
        storage.removeAttribute(.glaukRule, range: scope)
        storage.removeAttribute(.glaukCodeBlock, range: scope)
        storage.removeAttribute(.glaukInlineCode, range: scope)
        storage.removeAttribute(.glaukTable, range: scope)
        storage.removeAttribute(.glaukTableHeader, range: scope)
        storage.removeAttribute(.glaukLinkURL, range: scope)
        storage.removeAttribute(.obliqueness, range: scope)
        storage.removeAttribute(.strikethroughStyle, range: scope)
        storage.removeAttribute(.kern, range: scope)   // テーブルの桁揃えをやり直すため
        storage.addAttribute(.paragraphStyle, value: typography.bodyParagraph, range: scope)

        // ★ Obsidian と同じ考え方: カーソルがテーブルの中にある間は原文のまま見せ、
        //   外に出たら罫線の表に切り替える。行単位で切り替えると、カーソル行だけ
        //   `|` が見えて桁がずれるため、テーブル全体で判定する。
        let cursorTable = cursorLine.flatMap { tableRange(in: ns, touching: $0) }
        func isSourceMode(_ range: NSRange) -> Bool {
            guard let t = cursorTable else { return false }
            return NSIntersectionRange(t, range).length > 0
        }

        // marker は開き・閉じの2個1組で来る(Zig側が閉じが見つかったときだけ両方を返すため)
        var pendingBoldOpen: Span?
        var pendingItalicOpen: Span?
        var pendingStrikeOpen: Span?
        // wikilink_target は wikilink_name より必ず先に来る(開始位置ソート済みのため)。
        // 直前に見た target 名を覚えておけば、続く name の存在判定に使える。
        var currentTargetName: String?

        for span in spans {
            guard NSMaxRange(span.range) <= storage.length else { continue }
            let onCursorLine = cursorLine.map { NSIntersectionRange($0, span.range).length > 0 }
                ?? false

            switch span.kind {
            case .heading1, .heading2, .heading3:
                let level = Int(span.kind.rawValue)
                let lineRange = (storage.string as NSString).lineRange(for: span.range)
                storage.addAttribute(.font, value: typography.heading(level), range: lineRange)
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .boldMarker:
                if let open = pendingBoldOpen {
                    let contentStart = NSMaxRange(open.range)
                    let contentRange = NSRange(location: contentStart, length: span.range.location - contentStart)
                    if contentRange.length > 0, NSMaxRange(contentRange) <= storage.length {
                        // ★ 本文固定ではなく「そこに今入っているフォント」を太らせる。
                        //   テーブルのセルはコード用の14ptなので、本文15ptで太らせると行内で大きさがずれる。
                        let base = (storage.attribute(.font, at: contentRange.location,
                                                      effectiveRange: nil) as? NSFont) ?? typography.body
                        storage.addAttribute(.font, value: typography.bold(base), range: contentRange)
                    }
                    pendingBoldOpen = nil
                } else {
                    pendingBoldOpen = span
                }
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .italicMarker:
                if let open = pendingItalicOpen {
                    let start = NSMaxRange(open.range)
                    let content = NSRange(location: start, length: span.range.location - start)
                    if content.length > 0, NSMaxRange(content) <= storage.length {
                        storage.addAttribute(.obliqueness,
                                             value: typography.italicObliqueness, range: content)
                    }
                    pendingItalicOpen = nil
                } else {
                    pendingItalicOpen = span
                }
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .strikeMarker:
                if let open = pendingStrikeOpen {
                    let start = NSMaxRange(open.range)
                    let content = NSRange(location: start, length: span.range.location - start)
                    if content.length > 0, NSMaxRange(content) <= storage.length {
                        storage.addAttribute(.strikethroughStyle,
                                             value: NSUnderlineStyle.single.rawValue, range: content)
                    }
                    pendingStrikeOpen = nil
                } else {
                    pendingStrikeOpen = span
                }
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .listMarker:
                storage.addAttribute(.foregroundColor, value: typography.accent, range: span.range)
                let lineRange = (storage.string as NSString).lineRange(for: span.range)
                storage.addAttribute(.paragraphStyle, value: typography.listParagraph, range: lineRange)

            case .quoteMarker:
                let lineRange = (storage.string as NSString).lineRange(for: span.range)
                storage.addAttribute(.paragraphStyle, value: typography.quoteParagraph, range: lineRange)
                // 縦棒は MarkdownLayoutManager が描く
                storage.addAttribute(.glaukQuote, value: true, range: lineRange)
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .quoteText:
                storage.addAttribute(.foregroundColor, value: typography.muted, range: span.range)

            case .hrule:
                // 罫線そのものは MarkdownLayoutManager が描く。--- の文字は隠す。
                storage.addAttribute(.glaukRule, value: true, range: span.range)
                storage.addAttribute(.foregroundColor, value: typography.muted, range: span.range)
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .linkHidden:
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .linkText:
                storage.addAttribute(.foregroundColor, value: typography.accent, range: span.range)

            case .linkURL:
                let url = (storage.string as NSString).substring(with: span.range)
                storage.addAttribute(.glaukLinkURL, value: url, range: span.range)

            case .codeKeyword:
                storage.addAttribute(.foregroundColor, value: typography.codeKeyword, range: span.range)
            case .codeString:
                storage.addAttribute(.foregroundColor, value: typography.codeString, range: span.range)
            case .codeNumber:
                storage.addAttribute(.foregroundColor, value: typography.codeNumber, range: span.range)
            case .codeComment:
                storage.addAttribute(.foregroundColor, value: typography.codeComment, range: span.range)
            case .codeType:
                storage.addAttribute(.foregroundColor, value: typography.codeType, range: span.range)
            case .codeFunction:
                storage.addAttribute(.foregroundColor, value: typography.codeFunction, range: span.range)

            case .codeLang:
                // 文字自体はフェンス行ごと隠れる。ブロックの右上に描くために覚えておく。
                let name = (storage.string as NSString).substring(with: span.range)
                storage.addAttribute(.glaukCodeLang, value: name, range: span.range)

            case .wikilinkHidden:
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .wikilinkTarget:
                let name = (storage.string as NSString).substring(with: span.range)
                currentTargetName = name
                storage.addAttribute(.glaukLinkTarget, value: name, range: span.range)

            case .frontmatter:
                // カーソルが入っていないときはたたむ。入れば素のまま編集できる。
                if !onCursorLine {
                    storage.addAttribute(.glaukHidden, value: true, range: span.range)
                    storage.addAttribute(.font, value: typography.folded, range: span.range)
                }

            case .codeFence:
                // ``` の行は丸ごと隠す。カーソルを置いたときだけ見える。
                // 行そのものは残るので、それが角丸ブロックの上下の余白になる。
                let lineRange = (storage.string as NSString).lineRange(for: span.range)
                storage.addAttribute(.glaukCodeBlock, value: true, range: lineRange)
                storage.addAttribute(.paragraphStyle, value: typography.codeParagraph, range: lineRange)
                if !onCursorLine {
                    storage.addAttribute(.glaukHidden, value: true, range: span.range)
                    // 行を残したままだと1行分の余白になって間延びするので、小さくして詰める
                    storage.addAttribute(.font, value: typography.codePadding, range: lineRange)
                }

            case .codeBlock:
                let lineRange = (storage.string as NSString).lineRange(for: span.range)
                storage.addAttribute(.font, value: typography.code, range: span.range)
                storage.addAttribute(.glaukCodeBlock, value: true, range: lineRange)
                storage.addAttribute(.paragraphStyle, value: typography.codeParagraph, range: lineRange)

            case .inlineCode:
                storage.addAttribute(.font, value: typography.code, range: span.range)
                storage.addAttribute(.glaukInlineCode, value: true, range: span.range)

            case .inlineCodeMarker:
                // 背景は繋げたいので、隠す範囲も含めて目印を付ける
                storage.addAttribute(.glaukInlineCode, value: true, range: span.range)
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .tableHeader, .tableRow:
                // ★ 改行まで含めた行範囲に目印を付ける。そうしないと行と行の間で属性が切れ、
                //   テーブル全体ではなく行ごとに枠が描かれてしまう。
                let lineRange = (storage.string as NSString).lineRange(for: span.range)
                storage.addAttribute(.glaukTable, value: true, range: lineRange)
                storage.addAttribute(.font, value: typography.code, range: span.range)
                storage.addAttribute(.paragraphStyle, value: typography.codeParagraph, range: lineRange)
                if span.kind == .tableHeader {
                    storage.addAttribute(.font, value: typography.bold(typography.code), range: span.range)
                    storage.addAttribute(.glaukTableHeader, value: true, range: span.range)
                }

            case .tableDelimiter:
                // |---|---| はたたむ。罫線は MarkdownLayoutManager が描く。
                let lineRange = (storage.string as NSString).lineRange(for: span.range)
                storage.addAttribute(.glaukTable, value: true, range: lineRange)
                if !isSourceMode(span.range) {
                    // ★ 極小フォントは改行まで含めて掛ける。行の中身だけだと、
                    //   末尾の改行が本文サイズのまま残って1行分の隙間になる。
                    storage.addAttribute(.glaukHidden, value: true, range: lineRange)
                    storage.addAttribute(.font, value: typography.folded, range: lineRange)
                }

            case .tablePipe:
                if isSourceMode(span.range) {
                    storage.addAttribute(.foregroundColor, value: typography.tableRule, range: span.range)
                } else {
                    // ★ 隠すのではなく透明にする。隠すと文字送りが0になって桁が詰まるので、
                    //   `|` の幅はそのまま列の余白として使い、その位置に縦罫線を描く。
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: span.range)
                    storage.addAttribute(.glaukTablePipe, value: true, range: span.range)
                }

            case .wikilinkName:
                let exists = currentTargetName.map(noteExists) ?? false
                if exists {
                    storage.addAttribute(.foregroundColor, value: typography.accent, range: span.range)
                } else {
                    storage.addAttribute(.foregroundColor, value: typography.muted, range: span.range)
                    storage.addAttribute(.underlineStyle,
                                         value: NSUnderlineStyle.patternDot.rawValue
                                              | NSUnderlineStyle.single.rawValue,
                                         range: span.range)
                }
            }
        }
        alignTables(in: storage, scope: scope, skipping: cursorTable)
        storage.endEditing()
    }

    // MARK: - テーブルの桁揃え

    /// 原文のセル幅はばらばらなので、そのまま出すと `|` の位置が揃わない。
    /// テキストは書き換えられないので、各セルの最後の文字に kern(字送り)を足して
    /// 列の幅を揃える。kern はその文字の「後ろ」に空きを作るので、次の `|` が右へ動く。
    private func alignTables(in storage: NSTextStorage, scope: NSRange, skipping cursorTable: NSRange?) {
        let ns = storage.string as NSString
        var tables: [NSRange] = []
        storage.enumerateAttribute(.glaukTable, in: scope) { value, range, _ in
            guard value != nil, range.length > 0 else { return }
            // 編集中のテーブルは原文のまま見せるので揃えない
            if let c = cursorTable, NSIntersectionRange(c, range).length > 0 { return }
            tables.append(range)
        }
        guard !tables.isEmpty else { return }

        // 折り返すと桁揃えの意味が無くなるので、収まらないときは揃えない
        let containerWidth = storage.layoutManagers.first?.textContainers.first?.size.width ?? 0
        let available = containerWidth - typography.codeParagraph.firstLineHeadIndent
            + typography.codeParagraph.tailIndent

        for table in tables {
            alignTable(in: storage, ns: ns, table: table, available: available)
        }
    }

    private func alignTable(in storage: NSTextStorage, ns: NSString,
                            table: NSRange, available: CGFloat) {
        // 行に分ける
        var lines: [NSRange] = []
        var p = table.location
        while p < NSMaxRange(table) {
            let line = ns.lineRange(for: NSRange(location: p, length: 0))
            lines.append(line)
            if line.length == 0 { break }
            p = NSMaxRange(line)
        }

        // 区切り行を除いた行について、`|` の位置と「行頭からそこまでの幅」を測る。
        // ★ セルを個別に測って足し合わせると、境目ごとの丸めが積もって数ptずれる。
        //   行頭からの累積で測り、各 `|` を目標位置へ直接合わせる。
        struct Row {
            var pipes: [Int]
            var prefix: [CGFloat]   // 行頭から pipes[k] の直前までの幅
        }
        var rows: [Row] = []
        for line in lines {
            if isTableDelimiterLine(ns.substring(with: line)) { continue }
            var pipes: [Int] = []
            for i in 0..<line.length where ns.character(at: line.location + i) == pipeChar {
                pipes.append(line.location + i)
            }
            guard pipes.count >= 2 else { continue }
            let prefix = pipes.map { p -> CGFloat in
                let r = NSRange(location: line.location, length: p - line.location)
                return r.length > 0 ? typesetWidth(storage.attributedSubstring(from: r)) : 0
            }
            rows.append(Row(pipes: pipes, prefix: prefix))
        }
        guard rows.count >= 2 else { return }   // 見出しだけの表は揃えなくてよい

        // 列の幅 = 「`|` から次の `|` まで」の最大値
        let segmentCount = (rows.map { $0.pipes.count }.max() ?? 1) - 1
        guard segmentCount > 0 else { return }
        var segment = [CGFloat](repeating: 0, count: segmentCount)
        for row in rows {
            for c in 0..<(row.pipes.count - 1) {
                segment[c] = Swift.max(segment[c], row.prefix[c + 1] - row.prefix[c])
            }
        }

        // 折り返すと桁揃えの意味が無くなるので、収まらないときは揃えない
        let total = segment.reduce(0, +)
        guard available <= 0 || total <= available else { return }

        for row in rows {
            var applied: CGFloat = 0     // これまでに足した字送りの合計
            var target = row.prefix[0]   // 1本目の `|` は動かさない
            for k in 1..<row.pipes.count {
                target += segment[k - 1]
                let extra = target - row.prefix[k] - applied
                guard extra > 0.5 else { continue }
                // 字送りは直前の1文字の「後ろ」に空きを作る
                let at = NSRange(location: row.pipes[k] - 1, length: 1)
                guard at.location >= 0, NSMaxRange(at) <= storage.length else { continue }
                storage.addAttribute(.kern, value: extra, range: at)
                applied += extra
            }
        }
    }

    /// 実際の組版と同じ幅を測る。
    /// NSAttributedString.size() はレイアウトマネージャの結果と数pt ずれるため、
    /// 桁揃えに使うと `|` の位置が揃いきらない(実測で最大5ptずれた)。
    private func typesetWidth(_ attributed: NSAttributedString) -> CGFloat {
        guard attributed.length > 0 else { return 0 }
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private let pipeChar = unichar(UInt8(ascii: "|"))

    /// `|---|:--:|` の行か
    private func isTableDelimiterLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        var hasDash = false, hasPipe = false
        for ch in t {
            switch ch {
            case "-": hasDash = true
            case "|": hasPipe = true
            case ":", " ", "\t": break
            default: return false
            }
        }
        return hasDash && hasPipe
    }

    /// 変更のあった範囲を含む段落だけを再計算する
    func applyIncremental(to storage: NSTextStorage, editedRange: NSRange, cursorLine: NSRange?) {
        let ns = storage.string as NSString
        let safeEditedRange = editedRange.clamped(to: ns.length)
        // 編集範囲を含む段落へ広げる(前後1行を含めると `**` の跨ぎに強くなる)
        var scope = ns.paragraphRange(for: safeEditedRange)
        if scope.location > 0 {
            scope = ns.paragraphRange(for: NSRange(location: scope.location - 1, length: 1))
                .union(scope)
        }
        // ブロック境界への拡張は applySpans が面倒を見る
        applySpans(to: storage, in: scope, cursorLine: cursorLine)
    }

    /// ``` のブロック / 先頭のフロントマターに掛かっているなら、その全体を含むよう広げる
    private func expandToBlockBoundaries(in ns: NSString, scope: NSRange) -> NSRange {
        var result = expandToFenceBoundaries(in: ns, scope: scope)
        if let fm = frontmatterRange(in: ns),
           NSIntersectionRange(fm, scope).length > 0 || scope.location <= NSMaxRange(fm) {
            result = result.union(fm)
        }
        // ★ テーブルは列幅を全行から決めるので、途中で切ると桁揃えが狂う
        if let table = tableRange(in: ns, touching: scope) {
            result = result.union(table)
        }
        return result.clamped(to: ns.length)
    }

    /// `scope` に掛かるテーブル(`|` を含む行の連なり)の全体を返す
    private func tableRange(in ns: NSString, touching scope: NSRange) -> NSRange? {
        guard ns.length > 0 else { return nil }
        let start = Swift.min(scope.location, ns.length)
        var first = ns.lineRange(for: NSRange(location: start, length: 0))
        guard ns.substring(with: first).contains("|") else { return nil }

        // 上へ
        while first.location > 0 {
            let prev = ns.lineRange(for: NSRange(location: first.location - 1, length: 0))
            guard ns.substring(with: prev).contains("|") else { break }
            first = prev.union(first)
        }
        // 下へ
        var last = ns.lineRange(for: NSRange(location: Swift.min(NSMaxRange(scope), ns.length - 1),
                                             length: 0))
        while NSMaxRange(last) < ns.length {
            let next = ns.lineRange(for: NSRange(location: NSMaxRange(last), length: 0))
            guard ns.substring(with: next).contains("|") else { break }
            last = last.union(next)
        }
        let block = first.union(last)
        // 2行目が区切り行でなければテーブルではない
        let head = ns.lineRange(for: NSRange(location: block.location, length: 0))
        guard NSMaxRange(head) < NSMaxRange(block) else { return nil }
        let second = ns.lineRange(for: NSRange(location: NSMaxRange(head), length: 0))
        guard isTableDelimiterLine(ns.substring(with: second)) else { return nil }
        return block
    }

    /// 文書先頭の `---` … `---`(閉じの改行まで)。Zig の frontmatterEnd と同じ判定。
    private func frontmatterRange(in ns: NSString) -> NSRange? {
        guard ns.length > 0 else { return nil }
        let firstLine = ns.lineRange(for: NSRange(location: 0, length: 0))
        guard isDashFence(ns.substring(with: firstLine)) else { return nil }

        var p = NSMaxRange(firstLine)
        while p < ns.length {
            let line = ns.lineRange(for: NSRange(location: p, length: 0))
            if isDashFence(ns.substring(with: line)) {
                return NSRange(location: 0, length: NSMaxRange(line))
            }
            p = NSMaxRange(line)
        }
        return nil   // 閉じが無いならフロントマターではない
    }

    private func isDashFence(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count >= 3 && t.allSatisfy { $0 == "-" }
    }

    /// ``` で囲まれたブロックに掛かっているなら、そのブロック全体を含むよう広げる
    private func expandToFenceBoundaries(in ns: NSString, scope: NSRange) -> NSRange {
        var fenceLines: [NSRange] = []
        var searchStart = 0
        while searchStart < ns.length {
            let found = ns.range(of: "```",
                                 range: NSRange(location: searchStart, length: ns.length - searchStart))
            guard found.location != NSNotFound else { break }
            let line = ns.lineRange(for: NSRange(location: found.location, length: 0))
            // 行頭(先頭の空白を除く)から始まるものだけをフェンスとみなす
            let indent = ns.substring(with: NSRange(location: line.location,
                                                    length: found.location - line.location))
            if indent.trimmingCharacters(in: .whitespaces).isEmpty { fenceLines.append(line) }
            searchStart = NSMaxRange(found)
        }

        var result = scope
        var i = 0
        while i < fenceLines.count {
            let open = fenceLines[i]
            // 閉じが無いフェンスは文末までをブロックとみなす(パーサ側の挙動と揃える)
            let closeEnd = i + 1 < fenceLines.count ? NSMaxRange(fenceLines[i + 1]) : ns.length
            let block = NSRange(location: open.location, length: closeEnd - open.location)
            let touches = NSIntersectionRange(block, scope).length > 0
                || (scope.location >= block.location && scope.location <= NSMaxRange(block))
            if touches { result = result.union(block) }
            i += 2
        }
        return result.clamped(to: ns.length)
    }
}

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
