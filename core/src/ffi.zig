const std = @import("std");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

/// Swiftへ渡す全てのバッファはこのアロケータから配る
pub const allocator = debug_allocator.allocator();

/// コアが渡したバイト列を解放する(Swiftから呼ぶ)
export fn glauk_free_buffer(ptr: [*]u8, len: usize) callconv(.c) void {
    allocator.free(ptr[0..len]);
}

/// デバッグ用: リークしていたら true
export fn glauk_check_leaks() callconv(.c) bool {
    return debug_allocator.detectLeaks();
}
