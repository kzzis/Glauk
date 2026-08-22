const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "glaukcore",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            // ★ forkpty / execvp を使うので libc が要る
            .link_libc = true,
        }),
    });

    const install_lib = b.addInstallArtifact(lib, .{});
    const installed_library = b.getInstallPath(.lib, "libglaukcore.a");
    const repacked_library = b.fmt("{s}.repacked", .{installed_library});

    const repack = b.addSystemCommand(&.{
        "/usr/bin/libtool",
        "-static",
        "-o",
        repacked_library,
        installed_library,
    });
    repack.step.dependOn(&install_lib.step);

    const replace = b.addSystemCommand(&.{
        "/bin/mv",
        repacked_library,
        installed_library,
    });
    replace.step.dependOn(&repack.step);

    b.getInstallStep().dependOn(&replace.step);
    // --- PTY を Swift 抜きで試すCLI ---
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("src/pty_demo.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const demo = b.addExecutable(.{ .name = "pty-demo", .root_module = demo_mod });
    const run_demo = b.addRunArtifact(demo);
    if (b.args) |args| run_demo.addArgs(args);
    b.step("pty-demo", "Run the PTY demo CLI").dependOn(&run_demo.step);

    b.installFile("include/glauk.h", "include/glauk.h");
    b.installFile("include/module.modulemap", "include/module.modulemap");
}
