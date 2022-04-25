const std = @import("std");
const chipz = @import("chipz");

const Key = chipz.Key;

const c = @cImport({
    @cInclude("SDL.h");
});

const DISPLAY_EVENT: u32 = 0;

fn manage_timer_callback(interval: u32, params: ?*anyopaque) callconv(.C) u32 {
    if (params) |ptr| {
        var timer = @ptrCast(*u8, ptr);

        if (timer.* != 0) {
            if (@subWithOverflow(u8, timer.*, @intCast(u8, 1), timer)) {
                timer.* = 0;
            }
        }
    }

    return interval;
}

fn manage_cycle_callback(interval: u32, params: ?*anyopaque) callconv(.C) u32 {
    if (params) |ptr| {
        var emu = @ptrCast(*chipz.ChipZ, @alignCast(@alignOf(**chipz.ChipZ), ptr));

        if (emu.cycle()) {} else |_| {
            @panic("Faulting instruction");
        }
        if (emu.flags.display_update) {
            publish_event_display();
        }
    }

    return interval;
}

fn publish_event_display() void {
    var userevent = c.SDL_UserEvent{
        .type = c.SDL_USEREVENT,
        .code = DISPLAY_EVENT,
        .data1 = null,
        .data2 = null,
        .timestamp = 0,
        .windowID = 0,
    };

    var event = c.SDL_Event{
        .user = userevent,
    };

    _ = c.SDL_PushEvent(&event);
}

pub fn main() anyerror!void {
    _ = c.SDL_Init(c.SDL_INIT_VIDEO);
    defer c.SDL_Quit();

    var window = c.SDL_CreateWindow("chipz", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, 64, 32, 0);
    defer c.SDL_DestroyWindow(window);

    var renderer = c.SDL_CreateRenderer(window, 0, c.SDL_RENDERER_PRESENTVSYNC);
    defer c.SDL_DestroyRenderer(renderer);

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const file_path = args[1];

    var file_handle = try std.fs.cwd().openFile(file_path, .{ .read = true, .write = false });
    defer file_handle.close();

    var buffer = try file_handle.readToEndAlloc(gpa, 4096 - 0x200);
    defer gpa.free(buffer);

    var emu = chipz.ChipZ.init(gpa);
    emu.load_program(buffer);

    var x: usize = 0;
    var y: usize = 0;

    var size_mult: c_int = 10;
    var rect = c.SDL_Rect{ .x = 0, .y = 0, .w = size_mult, .h = size_mult };

    var current_window_h: c_int = size_mult * 32;
    var current_window_w: c_int = size_mult * 64;
    c.SDL_SetWindowSize(window, current_window_w, current_window_h);

    _ = c.SDL_AddTimer(16, manage_timer_callback, &emu.timer_delay);
    _ = c.SDL_AddTimer(16, manage_timer_callback, &emu.timer_sound);
    _ = c.SDL_AddTimer(1, manage_cycle_callback, &emu);

    mainloop: while (true) {
        var sdl_event: c.SDL_Event = undefined;
        var force_redraw: bool = false;
        defer force_redraw = false;
        while (c.SDL_PollEvent(&sdl_event) != 0) {
            switch (sdl_event.type) {
                c.SDL_QUIT => break :mainloop,
                c.SDL_KEYDOWN => {
                    switch (sdl_event.key.keysym.sym) {
                        c.SDLK_UP, c.SDLK_DOWN => {
                            const mult: c_int = if (sdl_event.key.keysym.sym == c.SDLK_UP) 1 else -1;
                            size_mult += mult;
                            current_window_h = size_mult * 32;
                            current_window_w = size_mult * 64;
                            c.SDL_SetWindowSize(window, current_window_w, current_window_h);
                            c.SDL_RenderPresent(renderer);
                            rect.w = size_mult;
                            rect.h = size_mult;
                            publish_event_display();
                        },

                        // inputs

                        c.SDLK_1 => emu.flags.current_key_pressed = Key.One,
                        c.SDLK_2 => emu.flags.current_key_pressed = Key.Two,
                        c.SDLK_3 => emu.flags.current_key_pressed = Key.Three,
                        c.SDLK_4 => emu.flags.current_key_pressed = Key.C,
                        c.SDLK_q => emu.flags.current_key_pressed = Key.Four,
                        c.SDLK_w => emu.flags.current_key_pressed = Key.Five,
                        c.SDLK_e => emu.flags.current_key_pressed = Key.Six,
                        c.SDLK_r => emu.flags.current_key_pressed = Key.D,
                        c.SDLK_a => emu.flags.current_key_pressed = Key.Seven,
                        c.SDLK_s => emu.flags.current_key_pressed = Key.Eight,
                        c.SDLK_d => emu.flags.current_key_pressed = Key.Nine,
                        c.SDLK_f => emu.flags.current_key_pressed = Key.E,
                        c.SDLK_z => emu.flags.current_key_pressed = Key.A,
                        c.SDLK_x => emu.flags.current_key_pressed = Key.Zero,
                        c.SDLK_c => emu.flags.current_key_pressed = Key.B,
                        c.SDLK_v => emu.flags.current_key_pressed = Key.F,

                        else => {},
                    }
                },

                c.SDL_KEYUP => emu.flags.current_key_pressed = null,

                c.SDL_USEREVENT => {
                    switch (sdl_event.user.code) {
                        DISPLAY_EVENT => {
                            x = 0;
                            y = 0;

                            _ = c.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff);
                            _ = c.SDL_RenderClear(renderer);
                            while (x < 32) : (x += 1) {
                                y = 0;
                                while (y < 64) : (y += 1) {
                                    rect.x = size_mult * @intCast(c_int, y);
                                    rect.y = size_mult * @intCast(c_int, x);
                                    if (emu.display[y][x]) {
                                        _ = c.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff);
                                    } else {
                                        _ = c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xff);
                                    }
                                    _ = c.SDL_RenderFillRect(renderer, &rect);

                                }
                            }
                            c.SDL_RenderPresent(renderer);
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
}
