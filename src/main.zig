const std = @import("std");
const chipz = @import("lib/chipz.zig");

pub fn main() anyerror!void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = &general_purpose_allocator.allocator;
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const file_path = args[1];

    var file_handle = try std.fs.openFileAbsolute(file_path, .{.read = true, .write = false});
    defer file_handle.close();

    var buffer = try file_handle.readToEndAlloc(gpa, 4096-0x200);
    defer gpa.free(buffer);

    var emu = chipz.ChipZ.init(gpa);
    emu.load_program(buffer);

    var x : usize = 0;
    var y : usize = 0;

    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n", .{});
    while(true) {
        emu.cycle();
        x = 0;
        y = 0;
        if(emu.flags.display_update) {
            while(x < 32) : (x += 1) {
                try stdout.print("\n", .{});
                while (y < 64) : (y += 1) {
                    if(emu.display[y][x]) {
                        try stdout.print("H", .{});
                    } 
                    else
                    {
                        try stdout.print(" ", .{});
                    }
                }
            }
        }
    }
}
