import AppKit

final class SyntaxHighlighter {
    /// 空の見出し行に余白を作らないよう、マーカー以外の内容を確認する。
    static func lineHasContent(besides marker: NSRange, in ns: NSString) -> Bool {
        let line = ns.lineRange(for: marker)
        let after = NSRange(location: NSMaxRange(marker),
                            length: max(0, NSMaxRange(line) - NSMaxRange(marker)))
        guard after.length > 0 else { return false }
        return !ns.substring(with: after)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var typography: EditorTypography
    /// 未作成ノートの区別表示に使う。Coordinator から NoteIndex を差し込む
    var noteExists: (String) -> Bool = { _ in true }

    init(typography: EditorTypography = .init()) { self.typography = typography }

    /// 文書全体を再計算する(初期表示など)
    func apply(to storage: NSTextStorage, cursorLine: NSRange?) {
        applySpans(to: storage, in: NSRange(location: 0, length: storage.length), cursorLine: cursorLine)
    }

    /// `scope` の範囲だけを再計算する
    ///
    /// 実際に塗る範囲は、コードフェンスとフロントマターの境界まで広げる。
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
        storage.removeAttribute(.glaukLinkTarget, range: scope)
        storage.removeAttribute(.obliqueness, range: scope)
        storage.removeAttribute(.strikethroughStyle, range: scope)
        storage.removeAttribute(.kern, range: scope)   // テーブルの桁揃えをやり直すため
        storage.removeAttribute(.glaukCheckbox, range: scope)
        storage.removeAttribute(.glaukBullet, range: scope)
        storage.removeAttribute(.glaukCallout, range: scope)
        storage.removeAttribute(.glaukTag, range: scope)
        storage.removeAttribute(.glaukDiff, range: scope)
        storage.removeAttribute(.glaukTableColumns, range: scope)
        storage.addAttribute(.paragraphStyle, value: typography.bodyParagraph, range: scope)

        // Obsidian と同じ考え方: カーソルがテーブルの中にある間は原文のまま見せ、
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
        var pendingLinkTextRange: NSRange?
        // wikilink_target は wikilink_name より必ず先に来る(開始位置ソート済みのため)。
        // 直前に見た target 名を覚えておけば、続く name の存在判定に使える。
        var currentTargetName: String?
        // コールアウトの続きの行は種類を持っていないので、直前の見出し行のものを引き継ぐ
        var lastCalloutType = "note"

        for span in spans {
            guard NSMaxRange(span.range) <= storage.length else { continue }
            let onCursorLine = cursorLine.map { NSIntersectionRange($0, span.range).length > 0 }
                ?? false

            switch span.kind {
            case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
                // heading4 以降は rawValue が飛んでいるので、連番に直す
                let level = span.kind.rawValue <= 3
                    ? Int(span.kind.rawValue)
                    : Int(span.kind.rawValue) - 29
                let lineRange = (storage.string as NSString).lineRange(for: span.range)
                // 中身ができるまでは見出しとして組まない。`### ` と打った直後に
                //   見出しの字送りを当てると、まだ何も無い行に本文2行ぶんの空白が
                //   現れて、そこだけ様子がおかしく見える。マーカーは隠すので、
                //   打っている本人にはただの空行に見える。
                if Self.lineHasContent(besides: span.range, in: ns) {
                    storage.addAttribute(.font, value: typography.heading(level), range: lineRange)
                    storage.addAttribute(.paragraphStyle,
                                         value: typography.headingParagraph(level), range: lineRange)
                    storage.addAttribute(.glaukHeadingLevel, value: level, range: lineRange)
                }
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .boldMarker:
                if let open = pendingBoldOpen {
                    let contentStart = NSMaxRange(open.range)
                    let contentRange = NSRange(location: contentStart, length: span.range.location - contentStart)
                    if contentRange.length > 0, NSMaxRange(contentRange) <= storage.length {
                        // 本文固定ではなく「そこに今入っているフォント」を太らせる。
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
                let lineRange = (storage.string as NSString).lineRange(for: span.range)
                storage.addAttribute(.paragraphStyle,
                                     value: typography.listParagraph(indentOf(span, in: ns)),
                                     range: lineRange)
                // `-` は隠さず透明にする。隠すと幅が0になり、中黒を描く場所が無くなる。
                //   (テーブルの縦罫線と同じ手)
                if onCursorLine {
                    storage.addAttribute(.foregroundColor, value: typography.accent, range: span.range)
                } else if span.range.length == 1 {
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: span.range)
                    storage.addAttribute(.glaukBullet, value: true, range: span.range)
                } else {
                    // "1." のような番号付きはそのまま見せる
                    storage.addAttribute(.foregroundColor, value: typography.accent, range: span.range)
                }

            case .taskMarker:
                let lineRange = (storage.string as NSString).lineRange(for: span.range)
                storage.addAttribute(.paragraphStyle,
                                     value: typography.listParagraph(indentOf(span, in: ns)),
                                     range: lineRange)
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .taskOpen, .taskDone:
                let done = span.kind == .taskDone
                if onCursorLine {
                    storage.addAttribute(.foregroundColor, value: typography.muted, range: span.range)
                } else {
                    // 透明にして、その上に MarkdownLayoutManager が四角と鉤を描く
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: span.range)
                    storage.addAttribute(.glaukCheckbox, value: done, range: span.range)
                }
                if done {
                    // 済んだタスクは行の残りを薄く+打ち消す
                    let lineRange = (storage.string as NSString).lineRange(for: span.range)
                    let restStart = NSMaxRange(span.range)
                    let rest = NSRange(location: restStart,
                                       length: max(0, NSMaxRange(lineRange) - restStart))
                    if rest.length > 0 {
                        storage.addAttribute(.foregroundColor, value: typography.muted, range: rest)
                        storage.addAttribute(.strikethroughStyle,
                                             value: NSUnderlineStyle.single.rawValue, range: rest)
                    }
                }

            case .highlightMarker:
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .highlight:
                storage.addAttribute(.backgroundColor, value: typography.highlightBg, range: span.range)

            case .tag:
                storage.addAttribute(.foregroundColor, value: typography.tagText, range: span.range)
                // 下地は MarkdownLayoutManager が角丸で描く(.backgroundColor は角が立つ)
                storage.addAttribute(.glaukTag, value: true, range: span.range)

            case .commentMarker:
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .comment:
                // Obsidian では表示されない。消しはしないが、本文と区別できるまで落とす。
                storage.addAttribute(.foregroundColor, value: typography.commentText, range: span.range)

            case .mathMarker:
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .math:
                storage.addAttribute(.font, value: typography.math, range: span.range)
                storage.addAttribute(.foregroundColor, value: typography.mathText, range: span.range)

            case .footnote, .blockID:
                storage.addAttribute(.font, value: typography.superscript, range: span.range)
                storage.addAttribute(.foregroundColor, value: typography.muted, range: span.range)

            case .callout:
                let type = calloutType(ns.substring(with: span.range))
                lastCalloutType = type
                let lineRange = ns.lineRange(for: span.range)
                storage.addAttribute(.glaukCallout, value: type, range: lineRange)
                // 帯を描くので引用の縦棒は消す。両方出ると棒が2本並ぶ。
                storage.removeAttribute(.glaukQuote, range: lineRange)
                // タイトルは色付きの太字にする
                let titleStart = min(NSMaxRange(span.range) + 1, NSMaxRange(lineRange))
                let title = NSRange(location: titleStart,
                                    length: max(0, NSMaxRange(lineRange) - titleStart))
                if title.length > 0 {
                    let base = (storage.attribute(.font, at: title.location,
                                                  effectiveRange: nil) as? NSFont) ?? typography.body
                    storage.addAttribute(.font, value: typography.bold(base), range: title)
                    storage.addAttribute(.foregroundColor,
                                         value: typography.calloutTint(type), range: title)
                }
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .calloutBody:
                let lineRange = ns.lineRange(for: span.range)
                storage.addAttribute(.glaukCallout, value: lastCalloutType, range: lineRange)
                storage.removeAttribute(.glaukQuote, range: lineRange)

            case .codeAdded, .codeRemoved:
                let added = span.kind == .codeAdded
                storage.addAttribute(.foregroundColor,
                                     value: added ? typography.codeAdded : typography.codeRemoved,
                                     range: span.range)
                // 行まるごとの下地は MarkdownLayoutManager が描く。
                // 改行まで含めないと、折り返しのない短い行で帯が途切れる。
                storage.addAttribute(.glaukDiff, value: added, range: ns.lineRange(for: span.range))

            case .codeMeta:
                storage.addAttribute(.foregroundColor, value: typography.codeMeta, range: span.range)

            case .embedMarker, .escape:
                if !onCursorLine { storage.addAttribute(.glaukHidden, value: true, range: span.range) }

            case .autoLink:
                storage.addAttribute(.foregroundColor, value: typography.accent, range: span.range)
                storage.addAttribute(.underlineStyle,
                                     value: NSUnderlineStyle.single.rawValue, range: span.range)
                storage.addAttribute(.glaukLinkURL,
                                     value: ns.substring(with: span.range), range: span.range)

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
                storage.addAttribute(.underlineStyle,
                                     value: NSUnderlineStyle.single.rawValue, range: span.range)
                pendingLinkTextRange = span.range

            case .linkURL:
                let url = (storage.string as NSString).substring(with: span.range)
                storage.addAttribute(.glaukLinkURL, value: url, range: span.range)
                if let textRange = pendingLinkTextRange {
                    storage.addAttribute(.glaukLinkURL, value: url, range: textRange)
                    pendingLinkTextRange = nil
                }

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
                // 改行まで含めた行範囲に目印を付ける。そうしないと行と行の間で属性が切れ、
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
                    // 極小フォントは改行まで含めて掛ける。行の中身だけだと、
                    //   末尾の改行が本文サイズのまま残って1行分の隙間になる。
                    storage.addAttribute(.glaukHidden, value: true, range: lineRange)
                    storage.addAttribute(.font, value: typography.folded, range: lineRange)
                }

            case .tablePipe:
                if isSourceMode(span.range) {
                    storage.addAttribute(.foregroundColor, value: typography.tableRule, range: span.range)
                } else {
                    // 隠すのではなく透明にする。隠すと文字送りが0になって桁が詰まるので、
                    //   `|` の幅はそのまま列の余白として使い、その位置に縦罫線を描く。
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: span.range)
                    storage.addAttribute(.glaukTablePipe, value: true, range: span.range)
                }

            case .wikilinkName:
                let exists = currentTargetName.map(noteExists) ?? false
                if let currentTargetName, !currentTargetName.isEmpty {
                    storage.addAttribute(.glaukLinkTarget, value: currentTargetName,
                                         range: span.range)
                }
                if exists {
                    storage.addAttribute(.foregroundColor, value: typography.accent, range: span.range)
                    storage.addAttribute(.underlineStyle,
                                         value: NSUnderlineStyle.single.rawValue, range: span.range)
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
        // セルを個別に測って足し合わせると、境目ごとの丸めが積もって数ptずれる。
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
                return r.length > 0 ? typesetWidth(visibleText(storage, in: r)) : 0
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

        // CoreText と組版の幅の差に影響されないよう、罫線には列の目標位置を渡す。
        let padding = storage.layoutManagers.first?.textContainers.first?.lineFragmentPadding ?? 0
        let left = padding + typography.codeParagraph.firstLineHeadIndent
        var xs: [NSNumber] = [NSNumber(value: Double(left + rows[0].prefix[0]))]
        var running = rows[0].prefix[0]
        for width in segment {
            running += width
            xs.append(NSNumber(value: Double(left + running)))
        }
        storage.addAttribute(.glaukTableColumns, value: xs, range: table)
    }

    /// CoreText は .glaukHidden を解釈しないため、計測前に隠し文字を取り除く。
    private func visibleText(_ storage: NSTextStorage, in range: NSRange) -> NSAttributedString {
        let out = NSMutableAttributedString()
        storage.enumerateAttribute(.glaukHidden, in: range) { hidden, sub, _ in
            guard hidden == nil else { return }
            out.append(storage.attributedSubstring(from: sub))
        }
        return out
    }

    /// リストマーカーの手前にある空白から入れ子の深さを出す。
    /// タブは1段、スペースは2つで1段(Obsidian の既定に近い)。
    private func indentOf(_ span: Span, in ns: NSString) -> Int {
        let lineRange = ns.lineRange(for: span.range)
        var spaces = 0
        var tabs = 0
        var i = lineRange.location
        while i < span.range.location {
            switch ns.character(at: i) {
            case 0x20: spaces += 1
            case 0x09: tabs += 1
            default: return tabs + spaces / 2   // 引用の "> " など、空白以外が来たら打ち切り
            }
            i += 1
        }
        return tabs + spaces / 2
    }

    /// `[!warning]` / `[!warning|タイトル]` → "warning"
    private func calloutType(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("[!") { s.removeFirst(2) }
        if s.hasSuffix("]") { s.removeLast() }
        if let bar = s.firstIndex(of: "|") { s = String(s[s.startIndex..<bar]) }
        return s.trimmingCharacters(in: .whitespaces)
    }

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
        // テーブルは列幅を全行から決めるので、途中で切ると桁揃えが狂う
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
