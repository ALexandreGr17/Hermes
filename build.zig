const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});


    const translate_c = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("libfuse/libfuse.h"),
    });

    translate_c.linkSystemLibrary("fuse3", .{ .use_pkg_config = .yes });

    const exe = b.addExecutable(.{
        .name = "fts",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("./src/main.zig"),
            .link_libc = true,

            .imports = &.{
                .{ .name = "libfusec", .module = translate_c.createModule() }
            }

        }),
        .use_llvm = true
    });

    exe.root_module.addCSourceFiles(.{
        .files = &[_][]const u8 {
            "libfuse/main.c"
        }
    });

    exe.root_module.linkSystemLibrary("fuse3", .{ .use_pkg_config = .yes });


    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step =  b.step("run", "run the exe");
    run_step.dependOn(&run_cmd.step);
}
