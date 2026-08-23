//! 外部からのファイル変更を kqueue で検知する。
//!
//! ★ 素朴に「開いた fd を監視して NOTE_WRITE を待つ」だけでは動かない。
//!   多くのツール(Glauk自身を含む)は一時ファイルに書いて rename するので、
//!   パスが指す inode が差し替わり、監視していた側には WRITE が二度と来ない。
//!   RENAME/DELETE を受けて開き直す必要がある。
const std = @import("std");
const posix = std.posix;

/// file.zig が「今、自分が書いた」ことを記録する
var last_self_write_ms: i64 = 0;
var self_write_lock: std.Thread.Mutex = .{};

const SELF_WRITE_WINDOW_MS: i64 = 500;

pub export fn glauk_mark_self_write() callconv(.c) void {
    self_write_lock.lock();
    defer self_write_lock.unlock();
    last_self_write_ms = std.time.milliTimestamp();
}

fn isSelfWrite() bool {
    self_write_lock.lock();
    defer self_write_lock.unlock();
    const delta = std.time.milliTimestamp() - last_self_write_ms;
    return delta >= 0 and delta < SELF_WRITE_WINDOW_MS;
}

fn openAndRegister(kq: posix.fd_t, path: []const u8) !posix.fd_t {
    const file = try std.fs.cwd().openFile(path, .{});
    errdefer file.close();

    var changes = [_]posix.Kevent{.{
        .ident = @intCast(file.handle),
        .filter = std.c.EVFILT.VNODE,
        // ★ EV_CLEAR を付けないと「状態」として通知され続け、同じイベントを
        //   何度も受け取る。一度読んだらクリアする(エッジトリガ)。
        .flags = std.c.EV.ADD | std.c.EV.CLEAR,
        // NOTE_WRITE だけでは足りない。atomic save は RENAME/DELETE で来る。
        .fflags = std.c.NOTE.WRITE | std.c.NOTE.EXTEND |
            std.c.NOTE.RENAME | std.c.NOTE.DELETE | std.c.NOTE.ATTRIB,
        .data = 0,
        .udata = 0,
    }};
    _ = try posix.kevent(kq, &changes, &.{}, null);
    return file.handle;
}

/// 外部からの変更があるまでブロックする。true = 外部変更、false = 監視できない。
/// Swift 側は専用スレッドからループで呼ぶ。
pub export fn glauk_watch_next_external_change(path: [*:0]const u8) callconv(.c) bool {
    const p = std.mem.span(path);

    const kq = posix.kqueue() catch return false;
    defer posix.close(kq);

    var fd = openAndRegister(kq, p) catch return false;
    defer posix.close(fd);

    while (true) {
        var events: [1]posix.Kevent = undefined;
        const n = posix.kevent(kq, &.{}, &events, null) catch return false;
        if (n == 0) continue;

        const fflags = events[0].fflags;
        const replaced = (fflags & (std.c.NOTE.RENAME | std.c.NOTE.DELETE)) != 0;

        if (replaced) {
            // パスが別の inode を指すようになった。開き直して監視を続ける。
            posix.close(fd);
            // rename の直後はまだ新しいファイルが見えないことがある。少し待つ。
            std.Thread.sleep(20 * std.time.ns_per_ms);
            fd = openAndRegister(kq, p) catch return false;
        }

        // ★ 判定は再登録の「後」。自分の保存でも inode は差し替わるので、
        //   登録し直しは必ずやる。逆にすると自分が保存した後に監視が外れる。
        if (!isSelfWrite()) return true;
        // 自分の書き込みなら、通知せずに待ち直す
    }
}

const testing = std.testing;

test "自分の保存は窓の中なら握りつぶす" {
    glauk_mark_self_write();
    try testing.expect(isSelfWrite());

    self_write_lock.lock();
    last_self_write_ms = std.time.milliTimestamp() - (SELF_WRITE_WINDOW_MS + 10);
    self_write_lock.unlock();
    try testing.expect(!isSelfWrite());
}

test "kqueue が外部からの追記を拾う" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "note.md", .data = "v1" });

    const kq = try posix.kqueue();
    defer posix.close(kq);

    const file = try tmp.dir.openFile("note.md", .{});
    defer file.close();

    var changes = [_]posix.Kevent{.{
        .ident = @intCast(file.handle),
        .filter = std.c.EVFILT.VNODE,
        .flags = std.c.EV.ADD | std.c.EV.CLEAR,
        .fflags = std.c.NOTE.WRITE | std.c.NOTE.EXTEND,
        .data = 0,
        .udata = 0,
    }};
    _ = try posix.kevent(kq, &changes, &.{}, null);

    try tmp.dir.writeFile(.{ .sub_path = "note.md", .data = "v2 changed" });

    var events: [1]posix.Kevent = undefined;
    // ★ タイムアウトを必ず入れる。null だと壊れたときにテストが永久に固まる。
    var timeout = posix.timespec{ .sec = 2, .nsec = 0 };
    const n = try posix.kevent(kq, &.{}, &events, &timeout);

    try testing.expectEqual(@as(usize, 1), n);
    try testing.expect((events[0].fflags & std.c.NOTE.WRITE) != 0);
}

test "rename すると監視していた inode には WRITE が来ない" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "note.md", .data = "v1" });

    const kq = try posix.kqueue();
    defer posix.close(kq);
    const file = try tmp.dir.openFile("note.md", .{});
    defer file.close();

    var changes = [_]posix.Kevent{.{
        .ident = @intCast(file.handle),
        .filter = std.c.EVFILT.VNODE,
        .flags = std.c.EV.ADD | std.c.EV.CLEAR,
        .fflags = std.c.NOTE.WRITE | std.c.NOTE.EXTEND |
            std.c.NOTE.RENAME | std.c.NOTE.DELETE,
        .data = 0,
        .udata = 0,
    }};
    _ = try posix.kevent(kq, &changes, &.{}, null);

    // 一時ファイルに書いて置き換える = 多くのツールの保存の仕方
    try tmp.dir.writeFile(.{ .sub_path = "note.md.tmp", .data = "v2 replaced" });
    try tmp.dir.rename("note.md.tmp", "note.md");

    var events: [1]posix.Kevent = undefined;
    var timeout = posix.timespec{ .sec = 2, .nsec = 0 };
    const n = try posix.kevent(kq, &.{}, &events, &timeout);

    try testing.expectEqual(@as(usize, 1), n);
    // ★ ここが肝。届くのは WRITE ではなく DELETE(または RENAME)。
    //   WRITE だけを見ていると、この保存に永久に気づけない。
    const replaced = (events[0].fflags & (std.c.NOTE.RENAME | std.c.NOTE.DELETE)) != 0;
    try testing.expect(replaced);
    try testing.expect((events[0].fflags & std.c.NOTE.WRITE) == 0);
}

/// テスト用: 少し待ってからファイルを書き換えるスレッド
const DelayedWrite = struct {
    dir: std.fs.Dir,
    name: []const u8,
    data: []const u8,
    delay_ms: u64,

    fn run(self: *const DelayedWrite) void {
        std.Thread.sleep(self.delay_ms * std.time.ns_per_ms);
        self.dir.writeFile(.{ .sub_path = self.name, .data = self.data }) catch {};
    }
};

test "外部からの書き換えで待機が解ける" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "note.md", .data = "v1" });

    const dir_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir_path);
    const path = try std.fmt.allocPrintSentinel(testing.allocator, "{s}/note.md", .{dir_path}, 0);
    defer testing.allocator.free(path);

    const ctx = DelayedWrite{ .dir = tmp.dir, .name = "note.md", .data = "v2 外部から", .delay_ms = 150 };
    const t = try std.Thread.spawn(.{}, DelayedWrite.run, .{&ctx});
    defer t.join();

    try testing.expect(glauk_watch_next_external_change(path.ptr));
}

test "★ 自分の保存では発火しない(打鍵のたびに画面が光らない)" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "note.md", .data = "v1" });

    const dir_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir_path);
    const path = try std.fmt.allocPrintSentinel(testing.allocator, "{s}/note.md", .{dir_path}, 0);
    defer testing.allocator.free(path);

    // 自分が書いたことにして、すぐ書き換える。窓の中なので握りつぶされるはず。
    const Runner = struct {
        fn run(p: [*:0]const u8, out: *bool) void {
            out.* = glauk_watch_next_external_change(p);
        }
    };
    var returned = false;
    var fired = false;
    const t = try std.Thread.spawn(.{}, Runner.run, .{ path.ptr, &fired });

    std.Thread.sleep(80 * std.time.ns_per_ms); // 監視が始まるのを待つ
    glauk_mark_self_write();
    try tmp.dir.writeFile(.{ .sub_path = "note.md", .data = "v2 自分の保存" });
    std.Thread.sleep(250 * std.time.ns_per_ms);
    returned = fired;

    // ここまでで返っていないこと = 握りつぶせていること
    try testing.expect(!returned);

    // 窓を抜けてから外部変更を起こして、待機を解いてスレッドを回収する
    std.Thread.sleep(SELF_WRITE_WINDOW_MS * std.time.ns_per_ms);
    try tmp.dir.writeFile(.{ .sub_path = "note.md", .data = "v3 外部から" });
    t.join();
    try testing.expect(fired);
}
