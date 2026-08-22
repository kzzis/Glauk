//! PTY(擬似端末)の上でエージェントCLIを起動する。
//!
//! ★ なぜ普通のパイプでなく PTY なのか:
//!   claude や codex は「人間が端末で使っている」前提で動く。パイプだと
//!   色が消え、対話UIを諦め、ものによっては「TTYが必要」で終了する。
//!   PTY を使うと「端末だと思わせる」ことができる。
const std = @import("std");
const c = @cImport({
    @cInclude("util.h"); // forkpty
    @cInclude("unistd.h"); // chdir, execvp, _exit
    @cInclude("signal.h"); // kill
    @cInclude("sys/ioctl.h"); // TIOCSWINSZ
    @cInclude("poll.h"); // poll
});

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
const gpa = debug_allocator.allocator();

const Session = struct {
    master: std.posix.fd_t,
    pid: std.posix.pid_t,
};

var sessions: std.AutoHashMapUnmanaged(i32, Session) = .empty;
var sessions_lock: std.Thread.Mutex = .{};
var next_id: i32 = 1;

pub const Agent = enum(c_int) {
    claude = 0,
    codex = 1,
};

/// エージェントCLIを新しいPTY上で起動する。セッションIDを返す。失敗なら -1。
pub export fn glauk_pty_spawn(agent: c_int, cwd: [*:0]const u8) callconv(.c) i32 {
    // ★ 先に検査する。@enumFromInt に知らない値を渡すと安全モードで落ちる。
    //   Swift 側の書き間違いがアプリごと落とす事故になりうる。
    if (agent != @intFromEnum(Agent.claude) and agent != @intFromEnum(Agent.codex)) {
        std.debug.print("[glauk] 知らないエージェント番号です: {d}\n", .{agent});
        return -1;
    }

    var master: c_int = -1;
    var ws: c.struct_winsize = .{
        .ws_row = 24,
        .ws_col = 80,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    // ★ ここでプロセスが2つになる。両方が同じ場所から再開し、戻り値だけが違う。
    //   親 = 子のPID(正) / 子 = 0
    const pid = c.forkpty(&master, null, null, &ws);
    if (pid < 0) {
        // サンドボックス下では PTY を確保できずここに来る(errno=EPERM)。
        std.debug.print("[glauk] forkpty に失敗しました: errno={d}\n", .{std.c._errno().*});
        return -1;
    }

    if (pid == 0) {
        // ---- ここから子プロセス ----
        if (c.chdir(cwd) != 0) c._exit(126); // 移動できない
        switch (@as(Agent, @enumFromInt(agent))) {
            .claude => {
                const argv = [_:null]?[*:0]const u8{ "claude", null };
                _ = c.execvp("claude", @constCast(@ptrCast(&argv)));
            },
            .codex => {
                const argv = [_:null]?[*:0]const u8{ "codex", "--cd", cwd, null };
                _ = c.execvp("codex", @constCast(@ptrCast(&argv)));
            },
        }
        // ★ execvp は成功したら戻ってこない(中身が入れ替わる)。
        //   ここに来たのは失敗したときだけ。127 は「コマンドが無い」の慣習。
        //   exit ではなく _exit。exit だと親から引き継いだバッファを流して
        //   親の出力が二重に出る。
        c._exit(127);
    }

    // ---- ここから親プロセス ----
    sessions_lock.lock();
    defer sessions_lock.unlock();

    const id = next_id;
    sessions.put(gpa, id, .{ .master = master, .pid = pid }) catch {
        std.posix.close(master);
        return -1;
    };
    next_id += 1;
    return id;
}

fn lookup(id: i32) ?Session {
    sessions_lock.lock();
    // ★ defer が肝。早期 return を1つ足しただけでデッドロックしないように。
    defer sessions_lock.unlock();
    return sessions.get(id);
}

/// ブロッキング read。Swift 側は専用スレッドから呼ぶ。
/// 戻り値: 読めたバイト数 / 0 = EOF(子が終了) / -1 = エラー
pub export fn glauk_pty_read(id: i32, buf: [*]u8, buf_len: usize) callconv(.c) isize {
    const s = lookup(id) orelse return -1;
    const n = std.posix.read(s.master, buf[0..buf_len]) catch return -1;
    return @intCast(n);
}

pub export fn glauk_pty_write(id: i32, data: [*]const u8, len: usize) callconv(.c) bool {
    const s = lookup(id) orelse return false;
    var written: usize = 0;
    while (written < len) {
        written += std.posix.write(s.master, data[written..len]) catch return false;
    }
    return true;
}

pub export fn glauk_pty_resize(id: i32, rows: u16, cols: u16) callconv(.c) bool {
    const s = lookup(id) orelse return false;
    var ws: c.struct_winsize = .{
        .ws_row = rows,
        .ws_col = cols,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    return c.ioctl(s.master, c.TIOCSWINSZ, &ws) == 0;
}

pub export fn glauk_pty_kill(id: i32) callconv(.c) void {
    sessions_lock.lock();
    const maybe = sessions.fetchRemove(id);
    // ★ 表から取り出したら即座に解放する。この下の waitpid は子の終了を待つので
    //   ブロックしうる。ロックを持ったままブロックすると他のスレッドが全部止まる。
    sessions_lock.unlock();

    const s = (maybe orelse return).value;
    _ = c.kill(s.pid, c.SIGTERM);
    std.posix.close(s.master);
    _ = std.posix.waitpid(s.pid, 0); // ゾンビ(<defunct>)を残さない
}

/// 読めるデータが来るまで待つ。1=読める / 0=時間切れ / -1=エラー。
/// ★ read はブロッキングなので、これが無いと「相手が黙ったまま」のときに
///   永久に待つ。demo を有限時間で終わらせるために要る。
pub export fn glauk_pty_poll(id: i32, timeout_ms: i32) callconv(.c) i32 {
    const s = lookup(id) orelse return -1;
    var fds = [_]c.struct_pollfd{.{ .fd = s.master, .events = c.POLLIN, .revents = 0 }};
    const n = c.poll(&fds, 1, timeout_ms);
    if (n < 0) return -1;
    return if (n == 0) 0 else 1;
}

/// 生きているセッションの数(demo とテスト用)
pub export fn glauk_pty_session_count() callconv(.c) usize {
    sessions_lock.lock();
    defer sessions_lock.unlock();
    return sessions.count();
}

const testing = std.testing;

// forkpty はサンドボックスでは通らないので、ここでは表の出入りだけを確かめる。
// 起動そのものは `zig build pty-demo` で実機で見る。

test "知らないセッションIDは読み書きを断る" {
    try testing.expectEqual(@as(isize, -1), glauk_pty_read(9999, undefined, 0));
    try testing.expect(!glauk_pty_write(9999, "x", 1));
    try testing.expect(!glauk_pty_resize(9999, 24, 80));
    try testing.expectEqual(@as(i32, -1), glauk_pty_poll(9999, 0));
}

test "知らないIDをkillしても落ちない" {
    glauk_pty_kill(9999);
    try testing.expectEqual(@as(usize, 0), glauk_pty_session_count());
}

test "知らないエージェント番号はspawnせず -1 を返す" {
    // @enumFromInt に落ちる前に弾けているか
    try testing.expectEqual(@as(i32, -1), glauk_pty_spawn(42, "/tmp"));
    try testing.expectEqual(@as(usize, 0), glauk_pty_session_count());
}
