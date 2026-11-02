const std = @import("std");

test {
    _ = @import("chip8.zig");
}
const chip = @import("chip8.zig");

pub fn main() void {
    var c = chip.Chip8Init();
    while (true) {
        const inst = chip.Fetch(&c);
        _ = inst;
    }
}
