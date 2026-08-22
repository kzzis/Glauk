//! PTY を Swift 抜きで確かめるための小さなCLI。
//!   zig build pty-demo -- claude
//!
//! ★ UIと繋ぐ前にここで確認する。繋いだ状態で調べると
//!   「Zigが悪いのか SwiftTerm が悪いのか」が分からなくなる。
const std = @import("std");
const pty = @import("pty.zig");

pub fn main() !void {
    var buf: [4096]u8 = undefined;
    var args = std.process.args();
    _ = args.next();
    const which = args.next() orelse "claude";
    const agent: c_int = if (std.mem.eql(u8, which, "codex")) 1 else 0;

    const page = std.heap.page_allocator;
    const cwd = try std.process.getCwdAlloc(page);
    defer page.free(cwd);
    const cwd_z = try page.dupeZ(u8, cwd);
    defer page.free(cwd_z);

    const id = pty.glauk_pty_spawn(agent, cwd_z.ptr);
    if (id < 0) {
        std.debug.print("spawn failed\n", .{});
        return;
    }
    std.debug.print("spawned session {d} in {s}\n", .{ id, cwd });
    _ = pty.glauk_pty_resize(id, 40, 120);

    // ★ バッファに溜めない。溜めると、相手が黙っている間ずっと画面に何も出ない。
    //   端末に直接書く。
    const out = std.fs.File.stdout();
    const quiet_ms = 2000;
    var total: usize = 0;
    var reason: []const u8 = "上限に達した";
    while (true) {
        // ★ read はブロッキング。claude はバナーを出したあと入力を待つので、
        //   これが無いと永久に返ってこない。
        switch (pty.glauk_pty_poll(id, quiet_ms)) {
            0 => {
                reason = "出力が止まった";
                break;
            },
            1 => {},
            else => {
                reason = "pollエラー";
                break;
            },
        }
        const n = pty.glauk_pty_read(id, &buf, buf.len);
        if (n <= 0) {
            reason = "EOF(子プロセスが終了した)";
            break;
        }
        try out.writeAll(buf[0..@intCast(n)]);
        total += @intCast(n);
        if (total > 64 * 1024) break;
    }

    pty.glauk_pty_kill(id);
    std.debug.print("\n--- {d} バイト読んだ / {s} / セッションを終了(残り {d}) ---\n", .{ total, reason, pty.glauk_pty_session_count() });
}
