const chipz = @import("lib/chipz.zig");
const ibm = @embedFile("../demo_files/IBM Logo.ch8");
const std = @import("std");
const buffer_alloc = std.heap.FixedBufferAllocator;

var stack : [24*2]u8 = undefined; 
var allocator : buffer_alloc = undefined;
var emu : chipz.ChipZ = undefined;


export fn onInit() void {
    stack = [_]u8{0} ** (24*2);
    allocator = buffer_alloc.init(&stack);
    emu = chipz.ChipZ.init(&allocator.allocator);
    var ibm_data : [132]u8 = [_]u8{0} ** 132;
    for (ibm) |byte, index| ibm_data[index] = byte;
    emu.load_program(&ibm_data);
    std.log.debug("test", .{});
}

export fn onAnimationFrame(timestamp: c_int) void {
    emu.cycle();
}

export fn need_display_update() bool {
    return emu.flags.display_update;
}

export fn get_display_data(data: *[64*32*4]u8) void {
    var x : usize = 0;
    var y : usize = 0;
    var current_index : usize = 0;
    x = 0;
    y = 0;
    if(emu.flags.display_update) {
        while(x < 32) : (x += 1) {
            y = 0;
            while (y < 64) : (y += 1) {
                if(emu.display[y][x]) {
                    data[current_index+0] = 255;
                    data[current_index+1] = 255;
                    data[current_index+2] = 255;
                    data[current_index+3] = 255;
                } 
                else
                {
                    data[current_index+0] = 0;
                    data[current_index+1] = 0;
                    data[current_index+2] = 0;
                    data[current_index+3] = 255;
                }
                current_index += 4;
            }
        }
    }
}