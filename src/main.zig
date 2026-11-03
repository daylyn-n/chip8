const std = @import("std");

test {
    _ = @import("chip8.zig");
}
const chip = @import("chip8.zig");

pub fn main() void {
    var c = chip.Chip8Init();
    while (c.state == .RUNNING) {
        const inst = chip.Fetch(&c);
        chip.Execute(&c, inst);
    }
}

// 16 digits, 0 to F. Each digit is 5 bytes.

//   for (0..16) |digit| {
// Address of the first byte of this digit: 0x050, 0x055, 0x05A, ...
//     const start = 0x050 + digit * 5;
//   std.debug.print("digit {X} at 0x{X:0>3}\n", .{ digit, start });

// The 5 bytes of this digit. The second counter starts at `start`,
// so `addr` is the real memory address, not 0, 1, 2, ...
// for (c.memory[start..][0..5], start..) |byte, addr| {
//   std.debug.print("  0x{X:0>3}: {X:0>2}  ", .{ addr, byte });

// The 4 high bits of the byte are the 4 pixels, left to right.
// 0x80 >> col selects bit 7, 6, 5, 4.
// for (0..4) |col| {
//   const on = byte & (@as(u8, 0x80) >> @intCast(col)) != 0;
// std.debug.print("{s}", .{if (on) "#" else "."});
//}
//std.debug.print("\n", .{});
//}
//}
