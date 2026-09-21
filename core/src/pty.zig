//! PTY(擬似端末)の上でエージェントCLIを起動する。
//!
//! PTY preserves the agent CLIs’ interactive terminal UI.
const std = @import("std");
const c = @cImport({
    @cInclude("util.h"); // forkpty
    @cInclude("unistd.h"); // chdir, execvp, _exit
    @cInclude("stdlib.h"); // setenv
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

/// Return a session ID, or -1 on failure. Set the size before the CLI draws its first frame.
pub export fn glauk_pty_spawn(agent: c_int, cwd: [*:0]const u8, rows: u16, cols: u16) callconv(.c) i32 {
    // Validate foreign input before @enumFromInt, which traps on unknown values.
    if (agent != @intFromEnum(Agent.claude) and agent != @intFromEnum(Agent.codex)) {
        std.debug.print("[glauk] 知らないエージェント番号です: {d}\n", .{agent});
        return -1;
    }

    // Resolve the shell PATH before forking; the GUI PATH may omit installed CLIs.
    const path_z = resolvedUserPath();

    var master: c_int = -1;
    var ws: c.struct_winsize = .{
        .ws_row = if (rows > 0) rows else 24,
        .ws_col = if (cols > 0) cols else 80,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    const pid = c.forkpty(&master, null, null, &ws);
    if (pid < 0) {
        std.debug.print("[glauk] forkpty に失敗しました: errno={d}\n", .{std.c._errno().*});
        return -1;
    }

    if (pid == 0) {
        if (c.chdir(cwd) != 0) c._exit(126); // 移動できない

        // Launch directly to avoid shell job-control errors and startup output.
        _ = c.setenv("PATH", path_z, 1);
        // GUI environments may have no TERM or use dumb, disabling the CLI UI.
        _ = c.setenv("TERM", "xterm-256color", 1);
        _ = c.setenv("COLORTERM", "truecolor", 1);
        // 文字化けを避ける。既にあれば尊重する(第3引数 0 = 上書きしない)。
        _ = c.setenv("LANG", "en_US.UTF-8", 0);

        const kind = @as(Agent, @enumFromInt(agent));
        const name: [*:0]const u8 = switch (kind) {
            .claude => "claude",
            .codex => "codex",
        };
        const argv = [_:null]?[*:0]const u8{ name, null };
        _ = c.execvp(name, @ptrCast(@constCast(&argv)));
        // _exit avoids flushing inherited parent buffers after exec fails.
        c._exit(127);
    }

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

/// ユーザーのシェルが持っている PATH。初回だけ調べて覚える。
var user_path_buf: [4096]u8 = undefined;
var user_path_ready = false;
var user_path_lock: std.Thread.Mutex = .{};

/// Use an interactive login shell to include PATH additions from .zshrc.
fn resolvedUserPath() [*:0]const u8 {
    user_path_lock.lock();
    defer user_path_lock.unlock();
    if (user_path_ready) return @ptrCast(&user_path_buf);

    // 失敗したときのために、まず今の PATH を入れておく
    const current = std.posix.getenv("PATH") orelse "/usr/bin:/bin";
    const fallback_len = @min(current.len, user_path_buf.len - 1);
    @memcpy(user_path_buf[0..fallback_len], current[0..fallback_len]);
    user_path_buf[fallback_len] = 0;
    user_path_ready = true;

    const shell = std.posix.getenv("SHELL") orelse "/bin/zsh";
    var probe_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = probe_state.deinit();
    const probe = probe_state.allocator();

    const result = std.process.Child.run(.{
        .allocator = probe,
        .argv = &.{ shell, "-l", "-i", "-c", "printf %s \"$PATH\"" },
        .max_output_bytes = user_path_buf.len - 1,
    }) catch |err| {
        std.debug.print("[glauk] PATH を調べられませんでした: {s}\n", .{@errorName(err)});
        return @ptrCast(&user_path_buf);
    };
    defer probe.free(result.stdout);
    defer probe.free(result.stderr);

    const found = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (found.len == 0 or found.len >= user_path_buf.len) return @ptrCast(&user_path_buf);
    @memcpy(user_path_buf[0..found.len], found);
    user_path_buf[found.len] = 0;
    return @ptrCast(&user_path_buf);
}

fn lookup(id: i32) ?Session {
    sessions_lock.lock();
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
    // Release the lock before waitpid so other sessions can continue.
    sessions_lock.unlock();

    const s = (maybe orelse return).value;
    _ = c.kill(s.pid, c.SIGTERM);
    std.posix.close(s.master);
    _ = std.posix.waitpid(s.pid, 0); // ゾンビ(<defunct>)を残さない
}

/// Wait for data: 1 = ready, 0 = timeout, -1 = error.
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
    try testing.expectEqual(@as(i32, -1), glauk_pty_spawn(42, "/tmp", 24, 80));
    try testing.expectEqual(@as(usize, 0), glauk_pty_session_count());
}
