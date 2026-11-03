const std = @import("std");

test {
    _ = @import("chip8.zig");
}
const chip = @import("chip8.zig");

// The IBM ROM ends with a jump to itself, so stop after a fixed number of
// instructions and print the screen once.
const max_cycles = 200;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) {
        std.debug.print("usage: {s} <rom path>\n", .{args[0]});
        return;
    }
    const rom_path = args[1];

    // One byte larger than the limit, so LoadRom can detect a ROM that is too large.
    var rom_buf: [chip.max_rom_size + 1]u8 = undefined;
    const rom = std.Io.Dir.cwd().readFile(init.io, rom_path, &rom_buf) catch |err| {
        std.debug.print("cannot read ROM '{s}': {s}\n", .{ rom_path, @errorName(err) });
        return err;
    };

    var c = chip.Chip8Init();
    try chip.LoadRom(&c, rom);

    var cycles: usize = 0;
    while (c.state == .RUNNING) {
        const inst = chip.Fetch(&c);
        chip.Execute(&c, inst);
        cycles += 1;
        if (cycles >= max_cycles) c.state = .QUIT;
    }

    printDisplay(&c);
}

// Print the 64x32 display. Each pixel is 2 characters wide, because a
// terminal character is about twice as tall as it is wide.
fn printDisplay(c: *const chip.Chip8) void {
    const width = 64;
    const height = 32;

    for (0..height) |row| {
        var line: [width * 2]u8 = undefined;
        for (0..width) |col| {
            const ch: u8 = if (c.display[row * width + col]) '#' else ' ';
            line[col * 2] = ch;
            line[col * 2 + 1] = ch;
        }
        std.debug.print("{s}\n", .{&line});
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
