const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // SDL3: translate the C header into a Zig module named "sdl".
    // pkg-config finds the SDL3 include path (install SDL3-devel).
    const sdl = b.addTranslateC(.{
        .root_source_file = b.path("src/sdl.h"),
        .target = target,
        .optimize = optimize,
    });
    sdl.linkSystemLibrary("SDL3", .{});

    const exe = b.addExecutable(.{
        .name = "chip8",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("sdl", sdl.createModule());
    exe.root_module.linkSystemLibrary("SDL3", .{});
    exe.root_module.link_libc = true;
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the emulator");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = exe.root_module });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
