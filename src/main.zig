const std = @import("std");

test {
    _ = @import("chip8.zig");
    _ = @import("sdl_frontend.zig");
}
const chip = @import("chip8.zig");
const sdl_frontend = @import("sdl_frontend.zig");

// About 700 instructions per second / 60 frames per second = ~11.
const cycles_per_frame = 11;

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

    // Seed CXNN from the operating system's random source, so each run
    // gives different numbers.
    var seed_bytes: [8]u8 = undefined;
    init.io.random(&seed_bytes);
    chip.SeedRandom(&c, std.mem.readInt(u64, &seed_bytes, .little));

    var frontend = try sdl_frontend.Frontend.Init("CHIP-8");
    defer frontend.Deinit();

    // One pass = one frame (~60 per second).
    while (c.state == .RUNNING) {
        if (!frontend.PollEvents(&c)) c.state = .QUIT;

        for (0..cycles_per_frame) |_| {
            try chip.Execute(&c, chip.Fetch(&c));
        }
        chip.TickTimers(&c);

        frontend.Draw(&c.display);
        frontend.Beep(chip.SoundOn(&c));
        frontend.WaitFrame();
    }
}
