const std = @import("std");

//define a chip8 struct
// for now, just keep I,

pub const Chip8 = struct { i: u16 = 0, stack: [16]u16 = @splat(0), stack_ptr: u8 = 0, memory: [4096]u8 = @splat(0) };

pub const StackError = error{ StackOverflow, StackUnderflow };
pub fn push(self: *Chip8, addr: u16) !void {
    if (self.stack_ptr == self.stack.len) return error.StackOverflow;
    self.stack[self.stack_ptr] = addr;
    self.stack_ptr += 1;
    return self.stack[self.stack_ptr];
}
pub fn pop(self: *Chip8) !u16 {
    if (self.stack_ptr == 0) return error.StackUnderflow;
    self.stack_ptr -= 1;
    return self.stack[self.stack_ptr];
}

pub fn Chip8Init() Chip8 {
    var c = Chip8{};
    const fonts = [_]u8{
        0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
        0x20, 0x60, 0x20, 0x20, 0x70, // 1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
        0x90, 0x90, 0xF0, 0x10, 0x10, // 4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
        0xF0, 0x10, 0x20, 0x40, 0x40, // 7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
        0xF0, 0x90, 0xF0, 0x90, 0x90, // A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
        0xF0, 0x80, 0x80, 0x80, 0xF0, // C
        0xE0, 0x90, 0x90, 0x90, 0xE0, // D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
        0xF0, 0x80, 0xF0, 0x80, 0x80, // F}
    };

    for (fonts, 0..) |byte, idx| {
        c.memory[0x050 + idx] = byte;
    }

    return c;
}

pub fn main() void {
    const c = Chip8Init();

    // 16 digits, 0 to F. Each digit is 5 bytes.
    for (0..16) |digit| {
        // Address of the first byte of this digit: 0x050, 0x055, 0x05A, ...
        const start = 0x050 + digit * 5;
        std.debug.print("digit {X} at 0x{X:0>3}\n", .{ digit, start });

        // The 5 bytes of this digit. The second counter starts at `start`,
        // so `addr` is the real memory address, not 0, 1, 2, ...
        for (c.memory[start..][0..5], start..) |byte, addr| {
            std.debug.print("  0x{X:0>3}: {X:0>2}  ", .{ addr, byte });

            // The 4 high bits of the byte are the 4 pixels, left to right.
            // 0x80 >> col selects bit 7, 6, 5, 4.
            for (0..4) |col| {
                const on = byte & (@as(u8, 0x80) >> @intCast(col)) != 0;
                std.debug.print("{s}", .{if (on) "#" else "."});
            }
            std.debug.print("\n", .{});
        }
    }
}
