const std = @import("std");
const expect = std.testing.expect;

const State = enum {
    RUNNING,
    PAUSE,
    QUIT,
};

test "Correct state to int" {
    try expect(@backingInt(State.RUNNING) == 0);
    try expect(@backingInt(State.PAUSE) == 1);
    try expect(@backingInt(State.QUIT) == 2);
}
pub const Chip8 = struct {
    I: u16 = 0,
    stack: [16]u16 = @splat(0),
    stack_ptr: u8 = 0,
    memory: [4096]u8 = @splat(0),
    pc: u16 = 0x200, // chip8 ROM starts at 0x200
    V: [16]u8 = @splat(0),
    display: [64 * 32]bool = @splat(false),
    state: State = .RUNNING,
    pub const init = Chip8Init;
};

pub const Instructions = struct {
    raw: u16 = 0,
    opcode: u4 = 0,
    NNN: u12 = 0,
    NN: u8 = 0,
    N: u4 = 0,
    X: u4 = 0,
    Y: u4 = 0,
    pub const decode_ = Decode;
};

pub const StackError = error{ StackOverflow, StackUnderflow };
pub fn push(self: *Chip8, addr: u16) !u16 {
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

    // TODO LOAD ROM

    return c;
}

// TODO implement chip8 instructions
// fetch/decode/exectute loop

pub fn Decode(raw: u16) Instructions {
    return .{
        .raw = raw,
        .opcode = @truncate(raw >> 12),
        .NNN = @truncate(raw),
        .NN = @truncate(raw),
        .N = @truncate(raw),
        .X = @truncate(raw >> 8),
        .Y = @truncate(raw >> 4),
    };
}
pub fn Fetch(self: *Chip8) Instructions {
    const hi_bits: u16 = self.memory[self.pc];
    const low_bits: u16 = self.memory[self.pc + 1];
    self.pc += 2;
    return Decode((hi_bits << 8) | low_bits);
}

// helper for the draw instructino

// DXYN: draw an N-row sprite from memory[I] at (V[X], V[Y]).
// Each sprite byte is one row of 8 pixels; bit 7 is the leftmost pixel.
// Pixels are XORed onto the screen. VF = 1 if any pixel turns off.
pub fn Draw(self: *Chip8, inst: Instructions) void {
    const width = 64;
    const height = 32;

    // Only the start position wraps. usize so the index math cannot overflow.
    const x: usize = self.V[inst.X] % width;
    const y: usize = self.V[inst.Y] % height;

    self.V[0xF] = 0;

    for (0..inst.N) |row| {
        const screen_y = y + row;
        if (screen_y >= height) break; // clip at the bottom edge

        const sprite_byte = self.memory[self.I + row];

        for (0..8) |col| {
            const screen_x = x + col;
            if (screen_x >= width) break; // clip at the right edge

            const bit_on = sprite_byte & (@as(u8, 0x80) >> @intCast(col)) != 0;
            if (!bit_on) continue;

            const idx = screen_y * width + screen_x;
            if (self.display[idx]) self.V[0xF] = 1; // collision: pixel turns off
            self.display[idx] = !self.display[idx];
        }
    }
}

pub fn Execute(self: *Chip8, inst: Instructions) void {
    switch (inst.opcode) {
        0x0 => {
            if (inst.raw == 0x00E0) {
                self.display = @splat(false);
            }
        },
        0x1 => {
            self.pc = inst.NNN;
        },
        0x2 => {},
        0x3 => {},
        0x4 => {},
        0x5 => {},
        0x6 => {
            self.V[inst.X] = inst.NN;
        },

        0x7 => {
            self.V[inst.X] +%= inst.NN;
        },
        0x8 => {},
        0x9 => {},
        0xA => {
            self.I = inst.NNN;
        },
        0xB => {},
        0xC => {},
        0xD => {
            Draw(self, inst);
        },
        0xE => {},
        0xF => {},
    }
}

test "1NNN Jumps" {
    var c = Chip8Init();
    std.debug.print("PC at the start {X:0>3}\n", .{c.pc});
    c.memory[0x200] = 0x12;
    c.memory[0x201] = 0x34;
    const inst = Fetch(&c);
    Execute(&c, inst);

    std.debug.print("PC after fetch/decode/ex {X:0>3}\n", .{c.pc});
    try std.testing.expectEqual(c.pc, 0x234);
}

test "6XNN store in X reg" {
    var c = Chip8Init();
    // should store 0x2B in V[0xA]
    c.memory[0x200] = 0x6A;
    c.memory[0x201] = 0x2B;
    const inst = Fetch(&c);
    Execute(&c, inst);
    try std.testing.expectEqual(c.V[inst.X], 0x2B);
}

test "DXYN draws font 0, then XOR erases it and sets VF" {
    var c = Chip8Init();
    c.I = 0x050; // font for digit 0
    c.V[0] = 0;
    c.V[1] = 0;

    Execute(&c, Decode(0xD015));
    // Row 0 of the "0" glyph is 0xF0: four pixels on, then off.
    try std.testing.expectEqual(true, c.display[0]);
    try std.testing.expectEqual(true, c.display[3]);
    try std.testing.expectEqual(false, c.display[4]);
    // Row 1 is 0x90: pixel 0 and pixel 3 on.
    try std.testing.expectEqual(true, c.display[64 + 0]);
    try std.testing.expectEqual(false, c.display[64 + 1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    Execute(&c, Decode(0xD015));
    try std.testing.expect(std.mem.allEqual(bool, &c.display, false));
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);
}

test "DXYN clips at the right edge" {
    var c = Chip8Init();
    c.I = 0x050;
    c.V[0] = 62; // only 2 of the 4 lit columns fit
    c.V[1] = 0;

    Execute(&c, Decode(0xD011));
    try std.testing.expectEqual(true, c.display[62]);
    try std.testing.expectEqual(true, c.display[63]);
    try std.testing.expectEqual(false, c.display[64]); // must not wrap to row 1
}

test "ANNN with DXYN" {
    var c = Chip8Init();

    Execute(&c, Decode(0xA050));
    Execute(&c, Decode(0xD015));
    // Row 0 of the "0" glyph is 0xF0: four pixels on, then off.
    try std.testing.expectEqual(true, c.display[0]);
    try std.testing.expectEqual(true, c.display[3]);
    try std.testing.expectEqual(false, c.display[4]);
    // Row 1 is 0x90: pixel 0 and pixel 3 on.
    try std.testing.expectEqual(true, c.display[64 + 0]);
    try std.testing.expectEqual(false, c.display[64 + 1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    Execute(&c, Decode(0xD015));
    try std.testing.expect(std.mem.allEqual(bool, &c.display, false));
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);
}
