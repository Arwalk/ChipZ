const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const chipz_lib = b.addModule("chipz", .{
        .root_source_file = b.path("src/lib/chipz.zig"),
    });
    const exe = b.addExecutable(.{
        .name = "chipz",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (builtin.target.os.tag == .windows) {
        const sdl_path = @embedFile("sdl_path.txt");
        exe.addIncludeDir(sdl_path ++ "include");
        exe.addLibPath(sdl_path ++ "lib\\x64");
        b.installBinFile(sdl_path ++ "lib\\x64\\SDL2.dll", "SDL2.dll");
    }
    exe.root_module.addImport("chipz", chipz_lib);
    exe.linkSystemLibrary("sdl2");
    exe.linkLibC();
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // tests
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.root_module.addImport("chipz", chipz_lib);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "test everything");
    test_step.dependOn(&run_exe_unit_tests.step);
}
