//! Glauk core — Swift から呼べる関数は全て `glauk_` 接頭辞を持つ

pub const ffi = @import("ffi.zig");
pub const markdown = @import("markdown.zig");

export fn glauk_ping() callconv(.c) [*:0]const u8 {
    return "pong";
}

comptime {
    _ = ffi;
    _ = markdown;
}
