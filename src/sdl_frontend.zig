// SDL3 frontend: window, drawing, keys, and sound.
// All SDL code stays in this file. chip8.zig never imports SDL.
const std = @import("std");
const c = @import("sdl");
// The frontend may use the core; the core never uses the frontend.
const chip = @import("chip8.zig");

// CHIP-8 screen size, in CHIP-8 pixels.
pub const display_width = 64;
pub const display_height = 32;

pub const scale = 10; // each CHIP-8 pixel is 10x10 screen pixels
pub const width = display_width * scale;
pub const height = display_height * scale;

// Pixel colors, as 0xAARRGGBB (the alpha byte is ignored).
const color_on: u32 = 0xFFFFFFFF; // white
const color_off: u32 = 0xFF000000; // black

// Beep sound: a square wave. A square wave is a tone that jumps between
// +volume and -volume. It sounds like an old computer beep.
const sample_rate = 48000; // samples per second
const beep_freq = 440; // Hz (the note A4)
const beep_volume: f32 = 0.1; // 0.0 to 1.0. Square waves are loud.
// Keep about 2 frames of sound queued. Less can stutter; more adds delay.
const queue_target_samples = sample_rate / 60 * 2;

pub const Error = error{ SdlInit, SdlWindow, SdlRenderer, SdlTexture };

pub const Frontend = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    // A 64x32 image in graphics memory. Draw() copies the display into it,
    // and the renderer stretches it to fill the window.
    texture: *c.SDL_Texture,
    // One u32 color per CHIP-8 pixel. Draw() fills it, then sends it to the texture.
    pixels: [display_width * display_height]u32 = @splat(color_off),
    // null if no audio device opened. The emulator then runs without sound.
    audio: ?*c.SDL_AudioStream = null,
    // Position inside one wave, 0.0 to 1.0. Kept between frames so the
    // wave does not jump, because a jump makes a click.
    phase: f32 = 0,

    pub fn Init(title: [:0]const u8) Error!Frontend {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO)) {
            std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlInit;
        }
        errdefer c.SDL_Quit();

        const window = c.SDL_CreateWindow(title.ptr, width, height, 0) orelse {
            std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlWindow;
        };

        errdefer c.SDL_DestroyWindow(window);

        const renderer = c.SDL_CreateRenderer(window, null) orelse {
            std.debug.print("SDL_CreateRenderer failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlRenderer;
        };
        errdefer c.SDL_DestroyRenderer(renderer);

        // STREAMING: the texture changes every frame.
        const texture = c.SDL_CreateTexture(
            renderer,
            c.SDL_PIXELFORMAT_XRGB8888,
            c.SDL_TEXTUREACCESS_STREAMING,
            display_width,
            display_height,
        ) orelse {
            std.debug.print("SDL_CreateTexture failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlTexture;
        };
        // NEAREST keeps the pixels sharp. The default blurs them when stretched.
        _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST);

        // Sound is optional: if it fails, print a warning and continue.
        const spec: c.SDL_AudioSpec = .{ .format = c.SDL_AUDIO_F32, .channels = 1, .freq = sample_rate };
        const audio = c.SDL_OpenAudioDeviceStream(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, null, null);
        if (audio) |stream| {
            // The device starts paused. It plays silence while the queue is empty.
            _ = c.SDL_ResumeAudioStreamDevice(stream);
        } else {
            std.debug.print("no sound: SDL_OpenAudioDeviceStream failed: {s}\n", .{c.SDL_GetError()});
        }

        return .{ .window = window, .renderer = renderer, .texture = texture, .audio = audio };
    }

    pub fn Deinit(self: *Frontend) void {
        if (self.audio) |stream| c.SDL_DestroyAudioStream(stream);
        c.SDL_DestroyTexture(self.texture);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    // Show the CHIP-8 display in the window. Takes only the pixel array,
    // so this file does not depend on the Chip8 struct.
    pub fn Draw(self: *Frontend, display: *const [display_width * display_height]bool) void {
        for (display, &self.pixels) |on, *px| {
            px.* = if (on) color_on else color_off;
        }

        // pitch = bytes in one row of pixels.
        _ = c.SDL_UpdateTexture(self.texture, null, &self.pixels, display_width * @sizeOf(u32));
        _ = c.SDL_RenderClear(self.renderer);
        // null, null = the full texture, stretched to the full window.
        _ = c.SDL_RenderTexture(self.renderer, self.texture, null, null);
        _ = c.SDL_RenderPresent(self.renderer);
    }

    // Call once per frame. While on is true, keep the beep queued.
    // When on is false, drop the queued sound so the beep stops at once.
    pub fn Beep(self: *Frontend, on: bool) void {
        const stream = self.audio orelse return;

        if (!on) {
            _ = c.SDL_ClearAudioStream(stream);
            return;
        }

        var chunk: [256]f32 = undefined;
        const step: f32 = @as(f32, beep_freq) / sample_rate; // phase per sample
        while (@divTrunc(c.SDL_GetAudioStreamQueued(stream), @sizeOf(f32)) < queue_target_samples) {
            for (&chunk) |*sample| {
                sample.* = if (self.phase < 0.5) beep_volume else -beep_volume;
                self.phase += step;
                if (self.phase >= 1.0) self.phase -= 1.0;
            }
            if (!c.SDL_PutAudioStreamData(stream, &chunk, @sizeOf(@TypeOf(chunk)))) break;
        }
    }

    // Sleep about one frame (60 per second). A simple delay for now;
    // exact timing comes later.
    pub fn WaitFrame(self: *Frontend) void {
        _ = self;
        c.SDL_Delay(1000 / 60);
    }

    // Handle all waiting events. Returns false when the user closes the window.
    // Key events update the machine's keys with chip.SetKey.
    // Escape also closes the emulator.
    pub fn PollEvents(self: *Frontend, machine: *chip.Chip8) bool {
        _ = self;
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => return false,
                c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
                    const key = event.key;
                    if (key.scancode == c.SDL_SCANCODE_ESCAPE) return false;
                    // Holding a key sends repeat KEY_DOWN events. The key is
                    // already down, so ignore them.
                    if (key.repeat) continue;
                    if (MapKey(key.scancode)) |k| chip.SetKey(machine, k, key.down);
                },
                else => {},
            }
        }
        return true;
    }
};

// Map a keyboard key to a CHIP-8 hex key. Scancodes are physical key
// positions, so the 4x4 block is the same on QWERTY, AZERTY, and so on.
//
//   CHIP-8 keypad      Keyboard
//   1 2 3 C            1 2 3 4
//   4 5 6 D            Q W E R
//   7 8 9 E            A S D F
//   A 0 B F            Z X C V
fn MapKey(scancode: c.SDL_Scancode) ?u4 {
    return switch (scancode) {
        c.SDL_SCANCODE_1 => 0x1,
        c.SDL_SCANCODE_2 => 0x2,
        c.SDL_SCANCODE_3 => 0x3,
        c.SDL_SCANCODE_4 => 0xC,
        c.SDL_SCANCODE_Q => 0x4,
        c.SDL_SCANCODE_W => 0x5,
        c.SDL_SCANCODE_E => 0x6,
        c.SDL_SCANCODE_R => 0xD,
        c.SDL_SCANCODE_A => 0x7,
        c.SDL_SCANCODE_S => 0x8,
        c.SDL_SCANCODE_D => 0x9,
        c.SDL_SCANCODE_F => 0xE,
        c.SDL_SCANCODE_Z => 0xA,
        c.SDL_SCANCODE_X => 0x0,
        c.SDL_SCANCODE_C => 0xB,
        c.SDL_SCANCODE_V => 0xF,
        else => null,
    };
}

test "MapKey covers all 16 CHIP-8 keys exactly once" {
    var seen: [16]bool = @splat(false);
    const keys = [_]c.SDL_Scancode{
        c.SDL_SCANCODE_1, c.SDL_SCANCODE_2, c.SDL_SCANCODE_3, c.SDL_SCANCODE_4,
        c.SDL_SCANCODE_Q, c.SDL_SCANCODE_W, c.SDL_SCANCODE_E, c.SDL_SCANCODE_R,
        c.SDL_SCANCODE_A, c.SDL_SCANCODE_S, c.SDL_SCANCODE_D, c.SDL_SCANCODE_F,
        c.SDL_SCANCODE_Z, c.SDL_SCANCODE_X, c.SDL_SCANCODE_C, c.SDL_SCANCODE_V,
    };
    for (keys) |sc| {
        const k = MapKey(sc).?;
        try std.testing.expect(!seen[k]); // no key mapped twice
        seen[k] = true;
    }
    try std.testing.expectEqual(@as(?u4, null), MapKey(c.SDL_SCANCODE_P));
}
