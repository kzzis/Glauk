const std = @import("std");

pub const SpanKind = enum(u8) {
    heading1 = 1,
    heading2 = 2,
    heading3 = 3,
    bold_marker = 4,
    wikilink_hidden = 5, // [[ ]] や alias記法の「隠す」部分
    wikilink_name = 6, // 画面に見せる部分(色付け・クリック対象)
    wikilink_target = 7, // Obsidianに渡す実体名の範囲
    code_fence = 8, // ``` の行そのもの(隠す)
    code_block = 9, // フェンスに挟まれた中身の行
    inline_code_marker = 10, // ` の1文字(隠す)
    inline_code = 11, // ` ` に挟まれた中身
    frontmatter = 12, // 文書先頭の --- ... --- 全体(たたむ)
};

/// Swiftに渡す構造体。UTF-16コードユニット単位。
pub const Span = extern struct {
    start: u32,
    len: u32,
    kind: u8,
};

/// Zig内部でだけ使う。こちらはバイト単位。
const ByteSpan = struct {
    start: usize,
    len: usize,
    kind: SpanKind,
};

fn utf16Len(bytes: []const u8) usize {
    var i: usize = 0;
    var units: usize = 0;
    while (i < bytes.len) {
        const n = std.unicode.utf8ByteSequenceLength(bytes[i]) catch 1;
        units += if (n == 4) @as(usize, 2) else 1;
        i += n;
    }
    return units;
}

fn scanLine(
    gpa: std.mem.Allocator,
    base: usize,
    line: []const u8,
    out: *std.ArrayList(ByteSpan),
) !void {
    var body_start: usize = 0;

    // --- 見出し: 行頭の # が1〜3個 + 直後にスペース ---
    var hashes: usize = 0;
    while (hashes < line.len and line[hashes] == '#') hashes += 1;
    if (hashes >= 1 and hashes <= 3 and hashes < line.len and line[hashes] == ' ') {
        const kind: SpanKind = switch (hashes) {
            1 => .heading1,
            2 => .heading2,
            else => .heading3,
        };
        // `# ` のスペースまで含めて隠す(隠したときに字下げが残らないように)
        try out.append(gpa, .{ .start = base, .len = hashes + 1, .kind = kind });
        body_start = hashes + 1;
    }

    var i: usize = body_start;
    while (i < line.len) {
        // --- インラインコード: ` ... ` ---
        // ★ 太字・wikilinkより先に見る。`**not bold**` のようにコードの中身は
        //   Markdownとして解釈してはいけないため。
        if (line[i] == '`') {
            if (std.mem.indexOfScalarPos(u8, line, i + 1, '`')) |close| {
                try out.append(gpa, .{ .start = base + i, .len = 1, .kind = .inline_code_marker });
                try out.append(gpa, .{ .start = base + close, .len = 1, .kind = .inline_code_marker });
                if (close > i + 1) {
                    try out.append(gpa, .{
                        .start = base + i + 1,
                        .len = close - i - 1,
                        .kind = .inline_code,
                    });
                }
                i = close + 1;
                continue;
            }
            i += 1; // 閉じが無い → マーカー扱いしない
            continue;
        }

        // --- 太字: ** ... ** ---
        if (i + 1 < line.len and line[i] == '*' and line[i + 1] == '*') {
            if (std.mem.indexOfPos(u8, line, i + 2, "**")) |close| {
                try out.append(gpa, .{ .start = base + i, .len = 2, .kind = .bold_marker });
                try out.append(gpa, .{ .start = base + close, .len = 2, .kind = .bold_marker });
                i = close + 2;
                continue;
            }
            i += 2; // 閉じが無い → マーカー扱いしない
            continue;
        }

        // --- wikilink: [[ ... ]] ---
        if (i + 1 < line.len and line[i] == '[' and line[i + 1] == '[') {
            if (std.mem.indexOfPos(u8, line, i + 2, "]]")) |close| {
                const inner_start = i + 2;
                const inner = line[inner_start..close];

                try out.append(gpa, .{ .start = base + i, .len = 2, .kind = .wikilink_hidden });
                try out.append(gpa, .{ .start = base + close, .len = 2, .kind = .wikilink_hidden });

                // target = `|` より前、かつ `#` より前
                const pipe = std.mem.indexOfScalar(u8, inner, '|');
                const target_end = blk: {
                    const upto = pipe orelse inner.len;
                    const hash = std.mem.indexOfScalar(u8, inner[0..upto], '#') orelse upto;
                    break :blk hash;
                };
                try out.append(gpa, .{
                    .start = base + inner_start,
                    .len = target_end,
                    .kind = .wikilink_target,
                });

                if (pipe) |p| {
                    // [[note|alias]] → "note|" を隠して "alias" を見せる
                    try out.append(gpa, .{
                        .start = base + inner_start,
                        .len = p + 1,
                        .kind = .wikilink_hidden,
                    });
                    try out.append(gpa, .{
                        .start = base + inner_start + p + 1,
                        .len = inner.len - p - 1,
                        .kind = .wikilink_name,
                    });
                } else {
                    try out.append(gpa, .{
                        .start = base + inner_start,
                        .len = inner.len,
                        .kind = .wikilink_name,
                    });
                }

                i = close + 2;
                continue;
            }
            i += 2;
            continue;
        }

        i += 1;
    }
}

/// 行頭(先頭の空白を除く)が ``` で始まるならフェンス行
fn fenceIndent(line: []const u8) ?usize {
    var n: usize = 0;
    while (n < line.len and (line[n] == ' ' or line[n] == '\t')) n += 1;
    if (line.len - n >= 3 and std.mem.startsWith(u8, line[n..], "```")) return n;
    return null;
}

/// `---` だけの行か(前後の空白は許す)
fn isDashFence(line: []const u8) bool {
    const t = std.mem.trim(u8, line, " \t\r");
    return t.len >= 3 and std.mem.allEqual(u8, t, '-');
}

/// 文書の先頭が `---` で始まり、閉じの `---` があるなら、その全体(末尾の改行を含む)を返す。
/// 閉じが無いときは null。閉じが無いまま全文をたたむと編集不能になるため。
fn frontmatterEnd(text: []const u8) ?usize {
    const first_end = std.mem.indexOfScalarPos(u8, text, 0, '\n') orelse return null;
    if (!isDashFence(text[0..first_end])) return null;

    var p: usize = first_end + 1;
    while (p <= text.len) {
        const e = std.mem.indexOfScalarPos(u8, text, p, '\n') orelse text.len;
        if (isDashFence(text[p..e])) {
            // 閉じの行の改行まで含めると、たたんだときに空行が残らない
            return if (e == text.len) text.len else e + 1;
        }
        if (e == text.len) break;
        p = e + 1;
    }
    return null;
}

fn scanAll(gpa: std.mem.Allocator, text: []const u8, out: *std.ArrayList(ByteSpan)) !void {
    var line_start: usize = 0;
    var in_fence = false;

    // --- フロントマター: 先頭の --- ... --- をひとまとまりで扱う ---
    if (frontmatterEnd(text)) |end| {
        try out.append(gpa, .{ .start = 0, .len = end, .kind = .frontmatter });
        line_start = end;
    }

    while (true) {
        const line_end = std.mem.indexOfScalarPos(u8, text, line_start, '\n') orelse text.len;
        const line = text[line_start..line_end];

        if (fenceIndent(line) != null) {
            // ``` の行は行ごと隠す。開き/閉じの両方が同じ扱い。
            try out.append(gpa, .{ .start = line_start, .len = line.len, .kind = .code_fence });
            in_fence = !in_fence;
        } else if (in_fence) {
            // ★ コードブロックの中身は Markdown として解釈しない(scanLineを呼ばない)
            if (line.len > 0) {
                try out.append(gpa, .{ .start = line_start, .len = line.len, .kind = .code_block });
            }
        } else {
            try scanLine(gpa, line_start, line, out);
        }

        if (line_end == text.len) break;
        line_start = line_end + 1;
    }
}

fn lessThanByStart(_: void, a: ByteSpan, b: ByteSpan) bool {
    return a.start < b.start;
}

fn toUtf16Spans(gpa: std.mem.Allocator, text: []const u8, byte_spans: []ByteSpan) ![]Span {
    // 位置順に並べてから1回だけ走査する(毎回先頭から数え直すとO(n²)になる)
    std.mem.sort(ByteSpan, byte_spans, {}, lessThanByStart);

    const result = try gpa.alloc(Span, byte_spans.len);
    errdefer gpa.free(result);

    var cursor: usize = 0;
    var units: usize = 0;
    for (byte_spans, 0..) |bs, idx| {
        units += utf16Len(text[cursor..bs.start]);
        cursor = bs.start;
        const span_units = utf16Len(text[bs.start .. bs.start + bs.len]);
        result[idx] = .{
            .start = @intCast(units),
            .len = @intCast(span_units),
            .kind = @intFromEnum(bs.kind),
        };
    }
    return result;
}

const allocator = @import("ffi.zig").allocator;

export fn glauk_parse_spans(
    text: [*]const u8,
    text_len: usize,
    out_count: *usize,
) callconv(.c) ?[*]Span {
    const slice = text[0..text_len];

    var byte_spans: std.ArrayList(ByteSpan) = .empty;
    defer byte_spans.deinit(allocator);
    scanAll(allocator, slice, &byte_spans) catch return null;

    const spans = toUtf16Spans(allocator, slice, byte_spans.items) catch return null;
    out_count.* = spans.len;
    return spans.ptr;
}

export fn glauk_free_spans(ptr: [*]Span, count: usize) callconv(.c) void {
    allocator.free(ptr[0..count]);
}

const testing = std.testing;

fn parse(gpa: std.mem.Allocator, text: []const u8) ![]Span {
    var byte_spans: std.ArrayList(ByteSpan) = .empty;
    defer byte_spans.deinit(gpa);
    try scanAll(gpa, text, &byte_spans);
    return toUtf16Spans(gpa, text, byte_spans.items);
}

test "heading marker span covers hashes and the space" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "## title");
    defer gpa.free(spans);

    try testing.expectEqual(@as(usize, 1), spans.len);
    try testing.expectEqual(@as(u32, 0), spans[0].start);
    try testing.expectEqual(@as(u32, 3), spans[0].len);
    try testing.expectEqual(@intFromEnum(SpanKind.heading2), spans[0].kind);
}

test "hash without a following space is not a heading" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "#tag");
    defer gpa.free(spans);
    try testing.expectEqual(@as(usize, 0), spans.len);
}

test "unclosed bold marker is ignored" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "a **b");
    defer gpa.free(spans);
    try testing.expectEqual(@as(usize, 0), spans.len);
}

test "offsets are UTF-16 code units, not bytes" {
    const gpa = testing.allocator;
    // "見出し" は 9バイト だが UTF-16 では 3
    const spans = try parse(gpa, "# 見出し\n**太字**");
    defer gpa.free(spans);

    try testing.expectEqual(@as(usize, 3), spans.len);
    try testing.expectEqual(@as(u32, 0), spans[0].start); // "# "
    try testing.expectEqual(@as(u32, 2), spans[0].len);
    try testing.expectEqual(@as(u32, 6), spans[1].start); // 2行目の "**"
    try testing.expectEqual(@as(u32, 10), spans[2].start); // 閉じの "**"
}

test "emoji outside the BMP counts as two UTF-16 units" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "🐙**x**"); // 🐙 は4バイト / UTF-16では2
    defer gpa.free(spans);
    try testing.expectEqual(@as(u32, 2), spans[0].start);
}

test "inline code marks the backticks and the content between them" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "see `code` here");
    defer gpa.free(spans);

    try testing.expectEqual(@as(usize, 3), spans.len);
    try testing.expectEqual(@intFromEnum(SpanKind.inline_code_marker), spans[0].kind);
    try testing.expectEqual(@as(u32, 4), spans[0].start);
    try testing.expectEqual(@intFromEnum(SpanKind.inline_code), spans[1].kind);
    try testing.expectEqual(@as(u32, 5), spans[1].start);
    try testing.expectEqual(@as(u32, 4), spans[1].len); // "code"
    try testing.expectEqual(@intFromEnum(SpanKind.inline_code_marker), spans[2].kind);
    try testing.expectEqual(@as(u32, 9), spans[2].start);
}

test "markdown inside inline code is not parsed" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "`**not bold**`");
    defer gpa.free(spans);

    for (spans) |s| {
        try testing.expect(s.kind != @intFromEnum(SpanKind.bold_marker));
    }
}

test "unclosed backtick is ignored" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "a ` b");
    defer gpa.free(spans);
    try testing.expectEqual(@as(usize, 0), spans.len);
}

test "fenced block hides the fences and marks the body" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "```swift\nlet x = 1\n```\n");
    defer gpa.free(spans);

    try testing.expectEqual(@as(usize, 3), spans.len);
    try testing.expectEqual(@intFromEnum(SpanKind.code_fence), spans[0].kind);
    try testing.expectEqual(@as(u32, 8), spans[0].len); // "```swift"
    try testing.expectEqual(@intFromEnum(SpanKind.code_block), spans[1].kind);
    try testing.expectEqual(@as(u32, 9), spans[1].len); // "let x = 1"
    try testing.expectEqual(@intFromEnum(SpanKind.code_fence), spans[2].kind);
}

test "markdown inside a fenced block is not parsed" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "```\n# not a heading\n**not bold** [[not a link]]\n```\n");
    defer gpa.free(spans);

    for (spans) |s| {
        try testing.expect(s.kind == @intFromEnum(SpanKind.code_fence) or
            s.kind == @intFromEnum(SpanKind.code_block));
    }
}

test "an unclosed fence keeps the rest of the document as code" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "```\n# still code\n");
    defer gpa.free(spans);

    try testing.expectEqual(@as(usize, 2), spans.len);
    try testing.expectEqual(@intFromEnum(SpanKind.code_fence), spans[0].kind);
    try testing.expectEqual(@intFromEnum(SpanKind.code_block), spans[1].kind);
}

test "frontmatter is one span covering the closing fence and its newline" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "---\na: 1\n---\n# 見出し");
    defer gpa.free(spans);

    try testing.expectEqual(@intFromEnum(SpanKind.frontmatter), spans[0].kind);
    try testing.expectEqual(@as(u32, 0), spans[0].start);
    try testing.expectEqual(@as(u32, 13), spans[0].len); // "---\na: 1\n---\n"
    // 続く見出しは通常どおり解析される
    try testing.expectEqual(@intFromEnum(SpanKind.heading1), spans[1].kind);
    try testing.expectEqual(@as(u32, 13), spans[1].start);
}

test "frontmatter without a closing fence is not folded" {
    const gpa = testing.allocator;
    // 閉じが無いのにたたむと文書全体が消えて編集できなくなる
    const spans = try parse(gpa, "---\na: 1\n# 見出し");
    defer gpa.free(spans);

    for (spans) |s| {
        try testing.expect(s.kind != @intFromEnum(SpanKind.frontmatter));
    }
}

test "--- in the middle of a document is not frontmatter" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "# 見出し\n---\na: 1\n---\n");
    defer gpa.free(spans);

    for (spans) |s| {
        try testing.expect(s.kind != @intFromEnum(SpanKind.frontmatter));
    }
}

test "markdown inside frontmatter is not parsed" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "---\ntitle: **bold** [[link]]\n---\n");
    defer gpa.free(spans);

    try testing.expectEqual(@as(usize, 1), spans.len);
    try testing.expectEqual(@intFromEnum(SpanKind.frontmatter), spans[0].kind);
}

test "alias form hides the target and shows the alias" {
    const gpa = testing.allocator;
    const spans = try parse(gpa, "[[note|alias]]");
    defer gpa.free(spans);

    var target: ?Span = null;
    var name: ?Span = null;
    for (spans) |s| {
        if (s.kind == @intFromEnum(SpanKind.wikilink_target)) target = s;
        if (s.kind == @intFromEnum(SpanKind.wikilink_name)) name = s;
    }
    try testing.expectEqual(@as(u32, 2), target.?.start); // "note"
    try testing.expectEqual(@as(u32, 4), target.?.len);
    try testing.expectEqual(@as(u32, 7), name.?.start); // "alias"
    try testing.expectEqual(@as(u32, 5), name.?.len);
}
