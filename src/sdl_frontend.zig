// SDL3 frontend: window (and later drawing, keys, and sound).
// All SDL code stays in this file. chip8.zig never imports SDL.
const std = @import("std");
const c = @import("sdl");

pub const scale = 10; // each CHIP-8 pixel is 10x10 screen pixels
pub const width = 64 * scale;
pub const height = 32 * scale;

pub const Error = error{ SdlInit, SdlWindow };

pub const Frontend = struct {
    window: *c.SDL_Window,

    pub fn init(title: [:0]const u8) Error!Frontend {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
            std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlInit;
        }
        errdefer c.SDL_Quit();

        const window = c.SDL_CreateWindow(title.ptr, width, height, 0) orelse {
            std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlWindow;
        };

        return .{ .window = window };
    }

    pub fn deinit(self: *Frontend) void {
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    // Sleep about one frame (60 per second). A simple delay for now;
    // exact timing comes later.
    pub fn waitFrame(self: *Frontend) void {
        _ = self;
        c.SDL_Delay(1000 / 60);
    }

    // Handle all waiting events. Returns false when the user closes the window.
    pub fn pollEvents(self: *Frontend) bool {
        _ = self;
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) return false;
        }
        return true;
    }
};
