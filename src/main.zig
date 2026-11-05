const std = @import("std");

test {
    _ = @import("chip8.zig");
}
const chip = @import("chip8.zig");
const sdl_frontend = @import("sdl_frontend.zig");

// About 700 instructions per second / 60 frames per second = ~11.
const cycles_per_frame = 11;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) {
        std.debug.print("usage: {s} <rom path> [test platform]\n", .{args[0]});
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

    // Optional: Timendus test ROMs read address 0x1FF to choose a platform
    // and skip their key menu (1 = CHIP-8). Remove when SDL input works.
    if (args.len >= 3) {
        c.memory[0x1FF] = std.fmt.parseInt(u8, args[2], 10) catch {
            std.debug.print("test platform must be a number, got '{s}'\n", .{args[2]});
            return error.InvalidArgument;
        };
    }

    var frontend = try sdl_frontend.Frontend.init("CHIP-8");
    defer frontend.deinit();

    // One pass = one frame (~60 per second).
    while (c.state == .RUNNING) {
        if (!frontend.pollEvents()) c.state = .QUIT;

        for (0..cycles_per_frame) |_| {
            try chip.Execute(&c, chip.Fetch(&c));
        }
        chip.tickTimers(&c);

        frontend.draw(&c.display);
        frontend.waitFrame();
    }

    // Print the last screen after the window closes.
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
