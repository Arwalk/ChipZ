const std = @import("std");

const sdl_path = @embedFile("sdl_path.txt");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const packages = [_]std.build.Pkg {
        .{
            .name = "chipz",
            .path = "src/lib/chipz.zig"
        }
    };

    const exe = b.addExecutable("chipz", "src/main.zig");
    exe.addPackage(packages[0]);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addIncludeDir(sdl_path ++ "include");
    exe.addLibPath(sdl_path ++ "lib\\x64");
    b.installBinFile(sdl_path ++ "lib\\x64\\SDL2.dll", "SDL2.dll");
    exe.linkSystemLibrary("sdl2");
    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }


    // tests
    const test_step = b.step("test", "test everything");

    const tests = [_]*std.build.LibExeObjStep {
        b.addTest("tests/tests.zig"),
    };

    for (tests) |test_def| {
        for (packages) |package| {
            test_def.addPackage(package);
        }
        test_step.dependOn(&test_def.step);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
