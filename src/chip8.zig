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
    i: u16 = 0,
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

//TODO
//Start with the minimum set needed to run the IBM logo ROM,
//the standard first test:
//00E0 clears the screen
//1NNN jumps
//6XNN sets VX
//7XNN adds to VX
//ANNN sets I
//DXYN draws a sprite
pub fn Execute(self: *Chip8, inst: Instructions) void {
    switch (inst.opcode) {
        0x0 => {},
        0x1 => {
            self.pc = inst.NNN;
        },
        0x2 => {},
        0x3 => {},
        0x4 => {},
        0x5 => {},
        0x6 => {},
        0x7 => {},
        0x8 => {},
        0x9 => {},
        0xA => {},
        0xB => {},
        0xC => {},
        0xD => {},
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
