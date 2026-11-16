const std = @import("std");
const chip = @import("chip8.zig");

pub const display_width = 64;
pub const display_height = 32;

pub const oled_width = 128;
pub const oled_pages = 8;
pub const oled_bytes = oled_width * oled_pages;

const Display = @FieldType(chip.Chip8, "display");

pub fn ToOled(display: *const Display, out: *[oled_bytes]u8) void {
    @memset(out, 0);
    for (0..display_height) |cy| {
        const page = cy / 4;
        const mask: u8 = @as(u8, 0b11) << @intCast((cy % 4) * 2);
        for (0..display_width) |cx| {
            if (display[cy * display_width + cx]) {
                out[page * oled_width + cx * 2] |= mask;
                out[page * oled_width + cx * 2 + 1] |= mask;
            }
        }
    }
}

pub const cycles_per_frame = 11;

pub const Status = enum(i32) {
    ok = 0,
    rom_too_large = 1,
    stack_overflow = 2,
    stack_underflow = 3,
};

var g_chip: chip.Chip8 = undefined;
var g_shown: Display = @splat(false);
var g_force_render = true;

export fn chip8_init(rom: [*]const u8, len: u32) i32 {
    g_chip = chip.Chip8Init();
    g_force_render = true;
    chip.LoadRom(&g_chip, rom[0..len]) catch return @intFromEnum(Status.rom_too_large);
    return @intFromEnum(Status.ok);
}

export fn chip8_frame() i32 {
    for (0..cycles_per_frame) |_| {
        chip.Execute(&g_chip, chip.Fetch(&g_chip)) catch |err| return @intFromEnum(switch (err) {
            error.StackOverflow => Status.stack_overflow,
            error.StackUnderflow => Status.stack_underflow,
        });
    }
    chip.TickTimers(&g_chip);
    return @intFromEnum(Status.ok);
}

export fn chip8_render(out: *[oled_bytes]u8) bool {
    if (!g_force_render and std.mem.eql(bool, &g_chip.display, &g_shown)) return false;
    g_shown = g_chip.display;
    g_force_render = false;
    ToOled(&g_chip.display, out);
    return true;
}

export fn chip8_sound_on() bool {
    return chip.SoundOn(&g_chip);
}

export fn chip8_set_key(key: u8, down: bool) void {
    chip.SetKey(&g_chip, @truncate(key), down);
}

export fn chip8_seed(seed: u32) void {
    chip.SeedRandom(&g_chip, seed);
}

test "ToOled: empty display gives an empty frame" {
    const display: Display = @splat(false);
    var out: [oled_bytes]u8 = @splat(0xAA);
    ToOled(&display, &out);
    try std.testing.expect(std.mem.allEqual(u8, &out, 0));
}

test "ToOled: pixel (0, 0) fills the top-left 2x2 block" {
    var display: Display = @splat(false);
    display[0] = true;
    var out: [oled_bytes]u8 = undefined;
    ToOled(&display, &out);
    try std.testing.expectEqual(@as(u8, 0x03), out[0]);
    try std.testing.expectEqual(@as(u8, 0x03), out[1]);
    for (out[2..]) |b| try std.testing.expectEqual(@as(u8, 0), b);
}

test "ToOled: row 3 uses the top bits of page 0, row 4 starts page 1" {
    var display: Display = @splat(false);
    display[3 * display_width + 5] = true;
    display[4 * display_width + 5] = true;
    var out: [oled_bytes]u8 = undefined;
    ToOled(&display, &out);
    try std.testing.expectEqual(@as(u8, 0xC0), out[10]);
    try std.testing.expectEqual(@as(u8, 0xC0), out[11]);
    try std.testing.expectEqual(@as(u8, 0x03), out[oled_width + 10]);
    try std.testing.expectEqual(@as(u8, 0x03), out[oled_width + 11]);
}

test "ToOled: bottom-right pixel fills the last two bytes" {
    var display: Display = @splat(false);
    display[display_width * display_height - 1] = true;
    var out: [oled_bytes]u8 = undefined;
    ToOled(&display, &out);
    try std.testing.expectEqual(@as(u8, 0xC0), out[oled_bytes - 2]);
    try std.testing.expectEqual(@as(u8, 0xC0), out[oled_bytes - 1]);
}

test "ToOled: full display gives a full frame" {
    const display: Display = @splat(true);
    var out: [oled_bytes]u8 = undefined;
    ToOled(&display, &out);
    try std.testing.expect(std.mem.allEqual(u8, &out, 0xFF));
}

test "chip8_init rejects a ROM that is too large" {
    const big: [chip.max_rom_size + 1]u8 = @splat(0);
    try std.testing.expectEqual(@intFromEnum(Status.rom_too_large), chip8_init(&big, big.len));
}

test "chip8_frame reports a stack underflow" {
    const rom = [_]u8{ 0x00, 0xEE };
    try std.testing.expectEqual(@intFromEnum(Status.ok), chip8_init(&rom, rom.len));
    try std.testing.expectEqual(@intFromEnum(Status.stack_underflow), chip8_frame());
}

test "chip8_render sends the first frame, then only changed frames" {
    const rom = [_]u8{ 0x12, 0x00 };
    try std.testing.expectEqual(@intFromEnum(Status.ok), chip8_init(&rom, rom.len));
    var out: [oled_bytes]u8 = undefined;
    try std.testing.expect(chip8_render(&out));
    try std.testing.expect(std.mem.allEqual(u8, &out, 0));
    try std.testing.expectEqual(@intFromEnum(Status.ok), chip8_frame());
    try std.testing.expect(!chip8_render(&out));
    g_chip.display[0] = true;
    try std.testing.expect(chip8_render(&out));
    try std.testing.expectEqual(@as(u8, 0x03), out[0]);
}

test "chip8_set_key sets and clears one key" {
    const rom = [_]u8{ 0x12, 0x00 };
    _ = chip8_init(&rom, rom.len);
    chip8_set_key(0xA, true);
    try std.testing.expect(g_chip.keys[0xA]);
    chip8_set_key(0xA, false);
    try std.testing.expect(!g_chip.keys[0xA]);
}
