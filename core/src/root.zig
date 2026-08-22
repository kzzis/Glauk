//! Glauk core — Swift から呼べる関数は全て `glauk_` 接頭辞を持つ

pub const ffi = @import("ffi.zig");
pub const markdown = @import("markdown.zig");
pub const syntax = @import("syntax.zig");
pub const file = @import("file.zig");
pub const watch = @import("watch.zig");
pub const notes = @import("notes.zig");
pub const pty = @import("pty.zig");

export fn glauk_ping() callconv(.c) [*:0]const u8 {
    return "pong";
}

comptime {
    _ = ffi;
    _ = markdown;
    _ = file;
    _ = watch;
    _ = notes;
    _ = pty;
}
