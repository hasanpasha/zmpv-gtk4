const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    const gtk = b.dependency("gtk", .{});
    const zmpv = b.dependency("zmpv", .{});

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("main.zig"),
        .optimize = optimize,
        .target = target,
    });
    exe.root_module.addImport("gtk", gtk.module("gtk"));
    exe.root_module.addImport("zmpv", zmpv.module("zmpv"));
    exe.linkLibC();
    exe.linkSystemLibrary("gtk4");
    exe.linkSystemLibrary("mpv");
    exe.linkSystemLibrary("epoxy");
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
