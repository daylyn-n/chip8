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

export fn chip8_to_oled(display: *const Display, out: *[oled_bytes]u8) void {
    ToOled(display, out);
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
