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

    var out_buf: [4096]u8 = undefined;
    var out = std.fs.File.stdout().writer(&out_buf);
    var total: usize = 0;
    while (true) {
        const n = pty.glauk_pty_read(id, &buf, buf.len);
        if (n <= 0) break;
        try out.interface.writeAll(buf[0..@intCast(n)]);
        total += @intCast(n);
        if (total > 8192) break; // 起動バナーが見えれば十分
    }
    try out.interface.flush();

    pty.glauk_pty_kill(id);
    std.debug.print("\n--- read {d} bytes, session killed (残りセッション {d}) ---\n", .{ total, pty.glauk_pty_session_count() });
}
