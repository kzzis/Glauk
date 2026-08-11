//! コードフェンスの中身を、言語ごとにざっくりトークン分けする。
//!
//! 完全なパーサではない。エディタの見た目に効く4種(キーワード / 文字列 / 数値 / コメント)
//! だけを拾う。行単位で処理し、ブロックコメントだけ行をまたぐ状態を持つ。
const std = @import("std");

pub const TokenKind = enum { keyword, string, number, comment };

pub const Token = struct {
    start: usize,
    len: usize,
    kind: TokenKind,
};

pub const Lang = struct {
    line_comment: []const u8 = "",
    block_open: []const u8 = "",
    block_close: []const u8 = "",
    /// 文字列の開始に使える引用符
    quotes: []const u8 = "\"",
    keywords: []const []const u8 = &.{},
};

const swift_kw = [_][]const u8{
    "actor",  "any",       "as",     "associatedtype", "async",    "await",   "break",    "case",
    "catch",  "class",     "continue", "default",      "defer",    "deinit",  "do",       "else",
    "enum",   "extension", "fallthrough", "false",     "fileprivate", "for",  "func",     "guard",
    "if",     "import",    "in",     "init",           "inout",    "internal", "is",      "let",
    "nil",    "open",      "operator", "private",      "protocol", "public",  "repeat",   "rethrows",
    "return", "self",      "Self",   "some",           "static",   "struct",  "subscript", "super",
    "switch", "throw",     "throws", "true",           "try",      "typealias", "var",    "weak",
    "where",  "while",     "lazy",   "mutating",       "nonisolated", "override", "required", "unowned",
};

const zig_kw = [_][]const u8{
    "align",   "allowzero", "and",    "anyframe", "anytype", "asm",      "async",  "await",
    "break",   "callconv",  "catch",  "comptime", "const",   "continue", "defer",  "else",
    "enum",    "errdefer",  "error",  "export",   "extern",  "false",    "fn",     "for",
    "if",      "inline",    "noalias", "null",    "or",      "orelse",   "packed", "pub",
    "resume",  "return",    "struct", "suspend",  "switch",  "test",     "threadlocal", "true",
    "try",     "undefined", "union",  "unreachable", "usingnamespace", "var", "volatile", "while",
    "u8",      "u16",       "u32",    "u64",      "usize",   "i8",       "i16",    "i32",
    "i64",     "isize",     "f32",    "f64",      "bool",    "void",     "type",
};

const js_kw = [_][]const u8{
    "as",     "async",  "await",   "break",  "case",    "catch",  "class",  "const",
    "continue", "debugger", "default", "delete", "do",   "else",   "enum",   "export",
    "extends", "false",  "finally", "for",    "from",    "function", "get",  "if",
    "implements", "import", "in",    "instanceof", "interface", "let", "new", "null",
    "of",     "private", "protected", "public", "readonly", "return", "set", "static",
    "super",  "switch", "this",    "throw",  "true",    "try",    "type",   "typeof",
    "undefined", "var", "void",    "while",  "with",    "yield",  "any",    "boolean",
    "number", "string", "unknown", "never",
};

const python_kw = [_][]const u8{
    "and",    "as",     "assert", "async",  "await",  "break",  "class",  "continue",
    "def",    "del",    "elif",   "else",   "except", "False",  "finally", "for",
    "from",   "global", "if",     "import", "in",     "is",     "lambda", "None",
    "nonlocal", "not",  "or",     "pass",   "raise",  "return", "True",   "try",
    "while",  "with",   "yield",  "self",
};

const rust_kw = [_][]const u8{
    "as",     "async",  "await",  "break",  "const",  "continue", "crate", "dyn",
    "else",   "enum",   "extern", "false",  "fn",     "for",    "if",     "impl",
    "in",     "let",    "loop",   "match",  "mod",    "move",   "mut",    "pub",
    "ref",    "return", "self",   "Self",   "static", "struct", "super",  "trait",
    "true",   "type",   "unsafe", "use",    "where",  "while",  "u8",     "u32",
    "u64",    "usize",  "i32",    "i64",    "f64",    "bool",   "str",    "String",
};

const go_kw = [_][]const u8{
    "break",  "case",   "chan",   "const",  "continue", "default", "defer", "else",
    "fallthrough", "for", "func",  "go",    "goto",   "if",     "import", "interface",
    "map",    "package", "range", "return", "select", "struct", "switch", "type",
    "var",    "nil",    "true",   "false",  "string", "int",    "error",  "bool",
};

const c_kw = [_][]const u8{
    "auto",   "bool",   "break",  "case",   "catch",  "char",   "class",  "const",
    "continue", "default", "delete", "do",   "double", "else",   "enum",   "extern",
    "false",  "float",  "for",    "goto",   "if",     "inline", "int",    "long",
    "namespace", "new", "nullptr", "private", "protected", "public", "return", "short",
    "signed", "sizeof", "static", "struct", "switch", "template", "this", "throw",
    "true",   "try",    "typedef", "typename", "union", "unsigned", "using", "virtual",
    "void",   "volatile", "while", "final", "import", "package", "super",
};

const bash_kw = [_][]const u8{
    "if",     "then",   "else",   "elif",   "fi",     "case",   "esac",   "for",
    "while",  "until",  "do",     "done",   "in",     "function", "return", "local",
    "export", "readonly", "declare", "echo", "cd",     "set",    "unset",  "source",
};

const json_kw = [_][]const u8{ "true", "false", "null" };

const yaml_kw = [_][]const u8{ "true", "false", "null", "yes", "no" };

/// ``` の後ろの言語名から設定を引く。未知の言語でも文字列と数値は拾う。
pub fn langFromInfo(info_raw: []const u8) Lang {
    const info = std.mem.trim(u8, info_raw, " \t\r");
    // "swift title=x" のように続きがあることがあるので最初の語だけ見る
    const name = blk: {
        const sp = std.mem.indexOfAny(u8, info, " \t{:") orelse info.len;
        break :blk info[0..sp];
    };

    var buf: [32]u8 = undefined;
    if (name.len > buf.len) return .{};
    const lower = std.ascii.lowerString(buf[0..name.len], name);

    const eq = std.mem.eql;
    if (eq(u8, lower, "swift")) {
        return .{ .line_comment = "//", .block_open = "/*", .block_close = "*/", .keywords = &swift_kw };
    }
    if (eq(u8, lower, "zig")) {
        return .{ .line_comment = "//", .keywords = &zig_kw };
    }
    if (eq(u8, lower, "js") or eq(u8, lower, "javascript") or eq(u8, lower, "ts") or
        eq(u8, lower, "typescript") or eq(u8, lower, "jsx") or eq(u8, lower, "tsx"))
    {
        return .{ .line_comment = "//", .block_open = "/*", .block_close = "*/",
                  .quotes = "\"'`", .keywords = &js_kw };
    }
    if (eq(u8, lower, "py") or eq(u8, lower, "python")) {
        return .{ .line_comment = "#", .quotes = "\"'", .keywords = &python_kw };
    }
    if (eq(u8, lower, "rust") or eq(u8, lower, "rs")) {
        return .{ .line_comment = "//", .block_open = "/*", .block_close = "*/", .keywords = &rust_kw };
    }
    if (eq(u8, lower, "go")) {
        return .{ .line_comment = "//", .block_open = "/*", .block_close = "*/",
                  .quotes = "\"`", .keywords = &go_kw };
    }
    if (eq(u8, lower, "c") or eq(u8, lower, "cpp") or eq(u8, lower, "c++") or
        eq(u8, lower, "h") or eq(u8, lower, "java") or eq(u8, lower, "cs") or eq(u8, lower, "csharp"))
    {
        return .{ .line_comment = "//", .block_open = "/*", .block_close = "*/",
                  .quotes = "\"'", .keywords = &c_kw };
    }
    if (eq(u8, lower, "sh") or eq(u8, lower, "bash") or eq(u8, lower, "zsh") or eq(u8, lower, "shell")) {
        return .{ .line_comment = "#", .quotes = "\"'", .keywords = &bash_kw };
    }
    if (eq(u8, lower, "json")) {
        return .{ .keywords = &json_kw };
    }
    if (eq(u8, lower, "yaml") or eq(u8, lower, "yml") or eq(u8, lower, "toml")) {
        return .{ .line_comment = "#", .quotes = "\"'", .keywords = &yaml_kw };
    }
    if (eq(u8, lower, "css") or eq(u8, lower, "scss")) {
        return .{ .block_open = "/*", .block_close = "*/", .quotes = "\"'" };
    }
    if (eq(u8, lower, "sql")) {
        return .{ .line_comment = "--", .quotes = "'\"" };
    }
    return .{};
}

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}
fn isIdentPart(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isKeyword(lang: Lang, word: []const u8) bool {
    for (lang.keywords) |k| {
        if (std.mem.eql(u8, k, word)) return true;
    }
    return false;
}

/// 1行をトークンに分ける。`in_block` はブロックコメントが行をまたいでいるかの状態。
pub fn tokenizeLine(
    gpa: std.mem.Allocator,
    base: usize,
    line: []const u8,
    lang: Lang,
    in_block: *bool,
    out: *std.ArrayList(Token),
) !void {
    var i: usize = 0;

    // 前の行から続くブロックコメント
    if (in_block.*) {
        if (lang.block_close.len > 0) {
            if (std.mem.indexOf(u8, line, lang.block_close)) |end| {
                const stop = end + lang.block_close.len;
                try out.append(gpa, .{ .start = base, .len = stop, .kind = .comment });
                in_block.* = false;
                i = stop;
            } else {
                if (line.len > 0) {
                    try out.append(gpa, .{ .start = base, .len = line.len, .kind = .comment });
                }
                return;
            }
        } else {
            in_block.* = false;
        }
    }

    while (i < line.len) {
        const c = line[i];

        // --- 行コメント: 行末まで ---
        if (lang.line_comment.len > 0 and
            std.mem.startsWith(u8, line[i..], lang.line_comment))
        {
            try out.append(gpa, .{ .start = base + i, .len = line.len - i, .kind = .comment });
            return;
        }

        // --- ブロックコメント ---
        if (lang.block_open.len > 0 and std.mem.startsWith(u8, line[i..], lang.block_open)) {
            const after = i + lang.block_open.len;
            if (lang.block_close.len > 0) {
                if (std.mem.indexOfPos(u8, line, after, lang.block_close)) |end| {
                    const stop = end + lang.block_close.len;
                    try out.append(gpa, .{ .start = base + i, .len = stop - i, .kind = .comment });
                    i = stop;
                    continue;
                }
            }
            try out.append(gpa, .{ .start = base + i, .len = line.len - i, .kind = .comment });
            in_block.* = true;
            return;
        }

        // --- 文字列 ---
        if (std.mem.indexOfScalar(u8, lang.quotes, c) != null) {
            var j = i + 1;
            while (j < line.len) {
                if (line[j] == '\\') {
                    j += 2;
                    continue;
                }
                if (line[j] == c) {
                    j += 1;
                    break;
                }
                j += 1;
            }
            const end = @min(j, line.len);
            try out.append(gpa, .{ .start = base + i, .len = end - i, .kind = .string });
            i = end;
            continue;
        }

        // --- 数値: 識別子の途中(x2 の 2 など)は拾わない ---
        if (std.ascii.isDigit(c) and (i == 0 or !isIdentPart(line[i - 1]))) {
            var j = i;
            while (j < line.len and (std.ascii.isAlphanumeric(line[j]) or line[j] == '_' or
                (line[j] == '.' and j + 1 < line.len and std.ascii.isDigit(line[j + 1]))))
            {
                j += 1;
            }
            try out.append(gpa, .{ .start = base + i, .len = j - i, .kind = .number });
            i = j;
            continue;
        }

        // --- 識別子 → キーワードなら色を付ける ---
        if (isIdentStart(c)) {
            var j = i;
            while (j < line.len and isIdentPart(line[j])) j += 1;
            if (isKeyword(lang, line[i..j])) {
                try out.append(gpa, .{ .start = base + i, .len = j - i, .kind = .keyword });
            }
            i = j;
            continue;
        }

        i += 1;
    }
}

const testing = std.testing;

fn collect(gpa: std.mem.Allocator, line: []const u8, lang: Lang, in_block: *bool) ![]Token {
    var list: std.ArrayList(Token) = .empty;
    errdefer list.deinit(gpa);
    try tokenizeLine(gpa, 0, line, lang, in_block, &list);
    return list.toOwnedSlice(gpa);
}

test "keywords, strings and numbers are picked up" {
    const gpa = testing.allocator;
    var in_block = false;
    const toks = try collect(gpa, "let x = 42 + \"hi\"", langFromInfo("swift"), &in_block);
    defer gpa.free(toks);

    try testing.expectEqual(@as(usize, 3), toks.len);
    try testing.expectEqual(TokenKind.keyword, toks[0].kind); // let
    try testing.expectEqual(TokenKind.number, toks[1].kind); // 42
    try testing.expectEqual(TokenKind.string, toks[2].kind); // "hi"
}

test "a line comment swallows the rest of the line" {
    const gpa = testing.allocator;
    var in_block = false;
    const toks = try collect(gpa, "let x = 1 // let \"y\" = 2", langFromInfo("swift"), &in_block);
    defer gpa.free(toks);

    // let, 1, コメント。コメントの中の let / "y" は拾わない
    try testing.expectEqual(@as(usize, 3), toks.len);
    try testing.expectEqual(TokenKind.comment, toks[2].kind);
    try testing.expectEqual(@as(usize, 10), toks[2].start);
}

test "block comments carry across lines" {
    const gpa = testing.allocator;
    const lang = langFromInfo("swift");
    var in_block = false;

    const a = try collect(gpa, "code /* start", lang, &in_block);
    defer gpa.free(a);
    try testing.expect(in_block);
    try testing.expectEqual(TokenKind.comment, a[a.len - 1].kind);

    const b = try collect(gpa, "still comment", lang, &in_block);
    defer gpa.free(b);
    try testing.expect(in_block);
    try testing.expectEqual(@as(usize, 1), b.len);

    const c = try collect(gpa, "end */ let x", lang, &in_block);
    defer gpa.free(c);
    try testing.expect(!in_block);
    try testing.expectEqual(TokenKind.comment, c[0].kind);
    try testing.expectEqual(TokenKind.keyword, c[1].kind); // 閉じたあとは通常どおり
}

test "a digit inside an identifier is not a number" {
    const gpa = testing.allocator;
    var in_block = false;
    const toks = try collect(gpa, "let x2 = 3", langFromInfo("swift"), &in_block);
    defer gpa.free(toks);

    try testing.expectEqual(@as(usize, 2), toks.len); // let と 3 のみ
    try testing.expectEqual(TokenKind.number, toks[1].kind);
    try testing.expectEqual(@as(usize, 9), toks[1].start);
}

test "an unknown language still highlights strings and numbers" {
    const gpa = testing.allocator;
    var in_block = false;
    const toks = try collect(gpa, "foo \"bar\" 7", langFromInfo("brainfuck"), &in_block);
    defer gpa.free(toks);

    try testing.expectEqual(@as(usize, 2), toks.len);
    try testing.expectEqual(TokenKind.string, toks[0].kind);
    try testing.expectEqual(TokenKind.number, toks[1].kind);
}

test "escaped quotes do not end the string early" {
    const gpa = testing.allocator;
    var in_block = false;
    const toks = try collect(gpa, "\"a\\\"b\" let", langFromInfo("swift"), &in_block);
    defer gpa.free(toks);

    try testing.expectEqual(TokenKind.string, toks[0].kind);
    try testing.expectEqual(@as(usize, 6), toks[0].len); // "a\"b"
    try testing.expectEqual(TokenKind.keyword, toks[1].kind);
}
