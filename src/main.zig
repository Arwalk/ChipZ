const std = @import("std");
const chipz = @import("lib/chipz.zig");

const c = @cImport({
    @cInclude("SDL.h");
});

pub fn main() anyerror!void {
    _ = c.SDL_Init(c.SDL_INIT_VIDEO);
    defer c.SDL_Quit();

    var window = c.SDL_CreateWindow("hello gamedev", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, 640, 320, 0);
    defer c.SDL_DestroyWindow(window);

    var renderer = c.SDL_CreateRenderer(window, 0, c.SDL_RENDERER_PRESENTVSYNC);
    defer c.SDL_DestroyRenderer(renderer);

    var frame: usize = 0;

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

    var rect = c.SDL_Rect{ .x = 0, .y = 0, .w = 10, .h = 10 };

    mainloop: while(true) {
        var sdl_event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdl_event) != 0) {
            switch (sdl_event.type) {
                c.SDL_QUIT => break :mainloop,
                else => {},
            }
        }
        emu.cycle();
        x = 0;
        y = 0;
        if(emu.flags.display_update) {
            _ = c.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff);
            _ = c.SDL_RenderClear(renderer);
            while(x < 32) : (x += 1) {
                y = 0;
                while (y < 64) : (y += 1) {
                    rect.x = 10 * @intCast(c_int, y);
                    rect.y = 10 *  @intCast(c_int, x);
                    if(emu.display[y][x]) {
                        _ = c.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff);
                        _ = c.SDL_RenderFillRect(renderer, &rect);
                    } 
                    else
                    {
                        _ = c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xff);
                        _ = c.SDL_RenderFillRect(renderer, &rect);
                    }
                }
            }
            c.SDL_RenderPresent(renderer);
        }
    }
}
