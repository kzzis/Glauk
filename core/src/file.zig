const std = @import("std");
const ffi = @import("ffi.zig");
const watch = @import("watch.zig");

const MAX_FILE_BYTES = 32 * 1024 * 1024; // 32MB を上限にしておく

export fn glauk_read_file(path: [*:0]const u8, out_len: *usize) callconv(.c) ?[*]u8 {
    const data = std.fs.cwd().readFileAlloc(
        ffi.allocator,
        std.mem.span(path),
        MAX_FILE_BYTES,
    ) catch return null;
    out_len.* = data.len;
    return data.ptr;
}

export fn glauk_write_file(path: [*:0]const u8, data: [*]const u8, len: usize) callconv(.c) bool {
    const p = std.mem.span(path);
    var buf: [4096]u8 = undefined;

    var af = std.fs.cwd().atomicFile(p, .{ .write_buffer = &buf }) catch |err| {
        std.debug.print("[glauk] atomicFile failed for \"{s}\": {s}\n", .{ p, @errorName(err) });
        return false;
    };
    defer af.deinit();

    af.file_writer.interface.writeAll(data[0..len]) catch |err| {
        std.debug.print("[glauk] writeAll failed for \"{s}\": {s}\n", .{ p, @errorName(err) });
        return false;
    };
    af.file_writer.interface.flush() catch |err| {
        std.debug.print("[glauk] flush failed for \"{s}\": {s}\n", .{ p, @errorName(err) });
        return false;
    };
    af.finish() catch |err| {
        std.debug.print("[glauk] finish failed for \"{s}\": {s}\n", .{ p, @errorName(err) });
        return false;
    };

    watch.glauk_mark_self_write();
    return true;
}

export fn glauk_file_mtime_ms(path: [*:0]const u8) callconv(.c) i64 {
    const st = std.fs.cwd().statFile(std.mem.span(path)) catch return -1;
    return @intCast(@divFloor(st.mtime, std.time.ns_per_ms));
}

const testing = std.testing;

test "write then read round-trips, and mtime is populated" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir_path);
    const path = try std.fmt.allocPrintSentinel(
        testing.allocator, "{s}/note.md", .{dir_path}, 0);
    defer testing.allocator.free(path);

    try testing.expect(glauk_write_file(path, "hello", 5));

    var len: usize = 0;
    const ptr = glauk_read_file(path, &len) orelse return error.ReadFailed;
    defer ffi.allocator.free(ptr[0..len]);
    try testing.expectEqualStrings("hello", ptr[0..len]);

    try testing.expect(glauk_file_mtime_ms(path) > 0);
}

test "reading a missing file returns null rather than crashing" {
    var len: usize = 0;
    try testing.expect(glauk_read_file("/nope/definitely/missing.md", &len) == null);
}

test "atomic write replaces content completely (no leftover tail)" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir_path);
    const path = try std.fmt.allocPrintSentinel(
        testing.allocator, "{s}/n.md", .{dir_path}, 0);
    defer testing.allocator.free(path);

    try testing.expect(glauk_write_file(path, "a-long-first-version", 20));
    try testing.expect(glauk_write_file(path, "short", 5));

    var len: usize = 0;
    const ptr = glauk_read_file(path, &len) orelse return error.ReadFailed;
    defer ffi.allocator.free(ptr[0..len]);
    try testing.expectEqualStrings("short", ptr[0..len]); // 前の内容の残骸が無い
}
