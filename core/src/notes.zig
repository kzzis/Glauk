//! ノートフォルダの走査。root 以下の `.md` を相対パスで集める。
//! ネットワークには一切触らない。Obsidian の vault をそのまま指定できる。
const std = @import("std");
const ffi = @import("ffi.zig");

/// シンボリックリンクのループなどで無限に潜らないための保険
const MAX_DEPTH = 16;

/// ノートが入っていないフォルダ。`.` 始まりを一律で弾くと
/// `.obsidian` / `.git` / `.trash` がまとめて消える。
fn isIgnoredDir(name: []const u8) bool {
    return std.mem.startsWith(u8, name, ".") or
        std.mem.eql(u8, name, "node_modules");
}

/// `dir` を歩いて、走査ルートからの相対パスを `out` に改行区切りで足す
fn scanDir(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    prefix: []const u8,
    depth: u8,
    out: *std.ArrayList(u8),
) !void {
    if (depth > MAX_DEPTH) return;

    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                if (!std.mem.endsWith(u8, entry.name, ".md")) continue;
                try out.appendSlice(allocator, prefix);
                try out.appendSlice(allocator, entry.name);
                try out.append(allocator, '\n');
            },
            .directory => {
                // ★ openDir の「前」に弾く。これが枝刈り。
                //   .git に入らないので .git/objects の何万ものファイルを一度も見ない。
                if (isIgnoredDir(entry.name)) continue;

                // 権限が無いフォルダやリンク切れが1つあっただけで索引全体が
                // 空になるのは困る。その1件だけ諦めて次へ進む。
                var child = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
                defer child.close();

                const child_prefix = try std.fmt.allocPrint(
                    allocator,
                    "{s}{s}/",
                    .{ prefix, entry.name },
                );
                defer allocator.free(child_prefix);

                try scanDir(allocator, child, child_prefix, depth + 1, out);
            },
            else => {},
        }
    }
}

fn scanInto(allocator: std.mem.Allocator, root: []const u8, out: *std.ArrayList(u8)) !void {
    var dir = try std.fs.cwd().openDir(root, .{ .iterate = true });
    defer dir.close();
    try scanDir(allocator, dir, "", 0, out);
}

/// root 以下の .md を改行区切りの相対パスで返す。解放は glauk_free_buffer。
export fn glauk_notes_scan(root: [*:0]const u8, out_len: *usize) callconv(.c) ?[*]u8 {
    var out: std.ArrayList(u8) = .empty;

    scanInto(ffi.allocator, std.mem.span(root), &out) catch |err| {
        out.deinit(ffi.allocator);
        std.debug.print(
            "[glauk] notes scan failed for \"{s}\": {s}\n",
            .{ std.mem.span(root), @errorName(err) },
        );
        return null;
    };

    const owned = out.toOwnedSlice(ffi.allocator) catch {
        out.deinit(ffi.allocator);
        return null;
    };
    out_len.* = owned.len;
    // 空フォルダでも null にはしない。null は「走査に失敗した」だけを意味させる。
    return owned.ptr;
}

const testing = std.testing;

test "scan finds nested markdown and skips dotfolders and non-markdown" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "top.md", .data = "" });
    try tmp.dir.makePath("sub");
    try tmp.dir.writeFile(.{ .sub_path = "sub/nested.md", .data = "" });
    try tmp.dir.writeFile(.{ .sub_path = "sub/image.png", .data = "" });
    try tmp.dir.makePath(".obsidian");
    try tmp.dir.writeFile(.{ .sub_path = ".obsidian/workspace.md", .data = "" });
    try tmp.dir.makePath(".git");
    try tmp.dir.writeFile(.{ .sub_path = ".git/COMMIT.md", .data = "" });
    try tmp.dir.makePath("node_modules");
    try tmp.dir.writeFile(.{ .sub_path = "node_modules/README.md", .data = "" });

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    try scanInto(testing.allocator, root, &out);

    try testing.expect(std.mem.indexOf(u8, out.items, "top.md") != null);
    try testing.expect(std.mem.indexOf(u8, out.items, "sub/nested.md") != null);
    try testing.expect(std.mem.indexOf(u8, out.items, "image.png") == null);
    try testing.expect(std.mem.indexOf(u8, out.items, "workspace.md") == null);
    try testing.expect(std.mem.indexOf(u8, out.items, "COMMIT.md") == null);
    try testing.expect(std.mem.indexOf(u8, out.items, "node_modules") == null);
}

test "scanning a missing folder fails cleanly" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    try testing.expectError(
        error.FileNotFound,
        scanInto(testing.allocator, "/nope/definitely/missing", &out),
    );
}

test "japanese note names survive the round trip" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("設計");
    try tmp.dir.writeFile(.{ .sub_path = "設計/データ移行メモ.md", .data = "" });

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    try scanInto(testing.allocator, root, &out);

    try testing.expect(std.mem.indexOf(u8, out.items, "設計/データ移行メモ.md") != null);
}

test "deeply nested notes are found, and MAX_DEPTH stops the descent" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // 3段は入る
    try tmp.dir.makePath("a/b/c");
    try tmp.dir.writeFile(.{ .sub_path = "a/b/c/deep.md", .data = "" });

    // MAX_DEPTH を超えた先は見に行かない
    var path: std.ArrayList(u8) = .empty;
    defer path.deinit(testing.allocator);
    for (0..MAX_DEPTH + 2) |_| try path.appendSlice(testing.allocator, "d/");
    try tmp.dir.makePath(path.items);
    try path.appendSlice(testing.allocator, "too-deep.md");
    try tmp.dir.writeFile(.{ .sub_path = path.items, .data = "" });

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    try scanInto(testing.allocator, root, &out);

    try testing.expect(std.mem.indexOf(u8, out.items, "a/b/c/deep.md") != null);
    try testing.expect(std.mem.indexOf(u8, out.items, "too-deep.md") == null);
}

test "an empty folder yields an empty list rather than an error" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    try scanInto(testing.allocator, root, &out);

    try testing.expectEqual(@as(usize, 0), out.items.len);
}

test "every line ends with a newline so Swift can split cleanly" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "one.md", .data = "" });
    try tmp.dir.writeFile(.{ .sub_path = "two.md", .data = "" });

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    try scanInto(testing.allocator, root, &out);

    try testing.expect(std.mem.endsWith(u8, out.items, "\n"));
    try testing.expectEqual(
        @as(usize, 2),
        std.mem.count(u8, out.items, "\n"),
    );
}
