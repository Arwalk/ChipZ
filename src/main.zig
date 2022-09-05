const std = @import("std");

const mainlib = @import("mainlib.zig");


const gpa = general_purpose_allocator.allocator();
var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const file_path = args[1];

    var file_handle = try std.fs.cwd().openFile(file_path, .{ .read = true, .write = false });
    defer file_handle.close();

    var buffer = try file_handle.readToEndAlloc(gpa, 4096 - 0x200);
    defer gpa.free(buffer);

    try mainlib.run(buffer);
}
