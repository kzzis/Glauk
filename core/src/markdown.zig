const std = @import("std");

pub const SpanKind = enum(u8) {
    heading1 = 1,
    heading2 = 2,
    heading3 = 3,
    bold_marker = 4,
    wikilink_hidden = 5, // [[ ]] や alias記法の「隠す」部分
    wikilink_name = 6, // 画面に見せる部分(色付け・クリック対象)
    wikilink_target = 7, // Obsidianに渡す実体名の範囲
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

fn scanAll(gpa: std.mem.Allocator, text: []const u8, out: *std.ArrayList(ByteSpan)) !void {
    var line_start: usize = 0;
    while (true) {
        const line_end = std.mem.indexOfScalarPos(u8, text, line_start, '\n') orelse text.len;
        try scanLine(gpa, line_start, text[line_start..line_end], out);
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
