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
    quirks: Quirks = .{},
    pub const init = Chip8Init;
};

// Some instructions behave differently on different CHIP-8 versions.
// The defaults follow the original COSMAC VIP interpreter.
pub const Quirks = struct {
    // 8XY6 / 8XYE: true = shift V[Y] into V[X] (original).
    // false = shift V[X] in place (CHIP-48 / SUPER-CHIP).
    shift_uses_vy: bool = true,
    // 8XY1 / 8XY2 / 8XY3: true = also set VF to 0 (original).
    logic_resets_vf: bool = true,
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
// stack_ptr is the index of the next FREE slot (0 = empty, 16 = full).
pub fn push(self: *Chip8, addr: u16) StackError!void {
    if (self.stack_ptr == self.stack.len) return error.StackOverflow;
    self.stack[self.stack_ptr] = addr;
    self.stack_ptr += 1;
}
pub fn pop(self: *Chip8) StackError!u16 {
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

pub const rom_start = 0x200;
pub const max_rom_size = 4096 - rom_start; // 3584 bytes

pub const LoadRomError = error{RomTooLarge};

// Copy ROM bytes into memory at 0x200. No file I/O here, so tests can pass
// a plain byte array. main.zig reads the file.
pub fn LoadRom(self: *Chip8, rom: []const u8) LoadRomError!void {
    if (rom.len > max_rom_size) return error.RomTooLarge;
    @memcpy(self.memory[rom_start..][0..rom.len], rom);
}

test "LoadRom copies bytes to 0x200" {
    var c = Chip8Init();
    try LoadRom(&c, &.{ 0x00, 0xE0, 0x12, 0x00 });
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0xE0, 0x12, 0x00 }, c.memory[0x200..0x204]);
}

test "LoadRom rejects a ROM that is too large" {
    var c = Chip8Init();
    const big: [max_rom_size + 1]u8 = @splat(0);
    try std.testing.expectError(error.RomTooLarge, LoadRom(&c, &big));
}

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

pub fn Draw(self: *Chip8, inst: Instructions) void {
    const width = 64;
    const height = 32;

    // Only the start position wraps. usize so the index math cannot overflow.
    const x: usize = self.V[inst.X] % width;
    const y: usize = self.V[inst.Y] % height;

    self.V[0xF] = 0;

    for (0..inst.N) |row| {
        const screen_y = y + row;
        if (screen_y >= height) break;

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

// 8XY_: register-to-register math and logic. N selects the operation.
// VF is always written LAST, so if X is F the flag wins over the result.
pub fn Arithmetic(self: *Chip8, inst: Instructions) void {
    const vx = self.V[inst.X];
    const vy = self.V[inst.Y];

    switch (inst.N) {
        // 8XY0: VX = VY
        0x0 => self.V[inst.X] = vy,

        // 8XY1 / 8XY2 / 8XY3: OR, AND, XOR
        0x1, 0x2, 0x3 => {
            self.V[inst.X] = switch (inst.N) {
                0x1 => vx | vy,
                0x2 => vx & vy,
                else => vx ^ vy,
            };
            if (self.quirks.logic_resets_vf) self.V[0xF] = 0;
        },

        // 8XY4: VX = VX + VY, VF = 1 on carry (sum > 255)
        0x4 => {
            const sum, const carry = @addWithOverflow(vx, vy);
            self.V[inst.X] = sum;
            self.V[0xF] = carry;
        },

        // 8XY5: VX = VX - VY, VF = 1 if there is NO borrow (VX >= VY)
        0x5 => {
            const diff, const borrow = @subWithOverflow(vx, vy);
            self.V[inst.X] = diff;
            self.V[0xF] = 1 - borrow;
        },

        // 8XY7: VX = VY - VX, VF = 1 if there is NO borrow (VY >= VX)
        0x7 => {
            const diff, const borrow = @subWithOverflow(vy, vx);
            self.V[inst.X] = diff;
            self.V[0xF] = 1 - borrow;
        },

        // 8XY6: shift right by 1, VF = the bit that falls out (bit 0)
        0x6 => {
            const src = if (self.quirks.shift_uses_vy) vy else vx;
            self.V[inst.X] = src >> 1;
            self.V[0xF] = src & 0x01;
        },

        // 8XYE: shift left by 1, VF = the bit that falls out (bit 7)
        0xE => {
            const src = if (self.quirks.shift_uses_vy) vy else vx;
            self.V[inst.X] = src << 1;
            self.V[0xF] = src >> 7;
        },

        // 8XY8 to 8XYD and 8XYF do not exist. Ignore them for now.
        else => {},
    }
}

pub const ExecuteError = StackError;

pub fn Execute(self: *Chip8, inst: Instructions) ExecuteError!void {
    switch (inst.opcode) {
        0x0 => switch (inst.raw) {
            // 00E0: clear the screen
            0x00E0 => self.display = @splat(false),
            // 00EE: return from a subroutine
            0x00EE => self.pc = try pop(self),
            // 0NNN: old machine-code call, not used by modern emulators
            else => {},
        },
        0x1 => {
            self.pc = inst.NNN;
        },
        // 2NNN: call the subroutine at NNN. Fetch already moved pc past this
        // instruction, so the saved pc is the return address.
        0x2 => {
            try push(self, self.pc);
            self.pc = inst.NNN;
        },
        // 3XNN: skip if VX == NN
        0x3 => {
            if (self.V[inst.X] == inst.NN) self.pc += 2;
        },
        // 4XNN: skip if VX != NN
        0x4 => {
            if (self.V[inst.X] != inst.NN) self.pc += 2;
        },
        // 5XY0: skip if VX == VY. The last nibble must be 0; 5XY1 to 5XYF
        // do not exist, so they do nothing.
        0x5 => {
            if (inst.N == 0 and self.V[inst.X] == self.V[inst.Y]) self.pc += 2;
        },
        0x6 => {
            self.V[inst.X] = inst.NN;
        },

        0x7 => {
            self.V[inst.X] +%= inst.NN;
        },
        0x8 => {
            Arithmetic(self, inst);
        },
        0x9 => {
            if (inst.N == 0 and self.V[inst.X] != self.V[inst.Y]) self.pc += 2;
        },
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
    c.memory[0x200] = 0x12;
    c.memory[0x201] = 0x34;
    const inst = Fetch(&c);
    try Execute(&c, inst);

    try std.testing.expectEqual(c.pc, 0x234);
}

test "6XNN store in X reg" {
    var c = Chip8Init();
    // should store 0x2B in V[0xA]
    c.memory[0x200] = 0x6A;
    c.memory[0x201] = 0x2B;
    const inst = Fetch(&c);
    try Execute(&c, inst);
    try std.testing.expectEqual(c.V[inst.X], 0x2B);
}

test "DXYN draws font 0, then XOR erases it and sets VF" {
    var c = Chip8Init();
    c.I = 0x050; // font for digit 0
    c.V[0] = 0;
    c.V[1] = 0;

    try Execute(&c, Decode(0xD015));
    // Row 0 of the "0" glyph is 0xF0: four pixels on, then off.
    try std.testing.expectEqual(true, c.display[0]);
    try std.testing.expectEqual(true, c.display[3]);
    try std.testing.expectEqual(false, c.display[4]);
    // Row 1 is 0x90: pixel 0 and pixel 3 on.
    try std.testing.expectEqual(true, c.display[64 + 0]);
    try std.testing.expectEqual(false, c.display[64 + 1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    try Execute(&c, Decode(0xD015));
    try std.testing.expect(std.mem.allEqual(bool, &c.display, false));
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);
}

test "DXYN clips at the right edge" {
    var c = Chip8Init();
    c.I = 0x050;
    c.V[0] = 62; // only 2 of the 4 lit columns fit
    c.V[1] = 0;

    try Execute(&c, Decode(0xD011));
    try std.testing.expectEqual(true, c.display[62]);
    try std.testing.expectEqual(true, c.display[63]);
    try std.testing.expectEqual(false, c.display[64]); // must not wrap to row 1
}

test "ANNN with DXYN" {
    var c = Chip8Init();

    try Execute(&c, Decode(0xA050));
    try Execute(&c, Decode(0xD015));
    // Row 0 of the "0" glyph is 0xF0: four pixels on, then off.
    try std.testing.expectEqual(true, c.display[0]);
    try std.testing.expectEqual(true, c.display[3]);
    try std.testing.expectEqual(false, c.display[4]);
    // Row 1 is 0x90: pixel 0 and pixel 3 on.
    try std.testing.expectEqual(true, c.display[64 + 0]);
    try std.testing.expectEqual(false, c.display[64 + 1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    try Execute(&c, Decode(0xD015));
    try std.testing.expect(std.mem.allEqual(bool, &c.display, false));
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);
}

// Helper for the 8XY_ tests: set V[X] and V[Y], run one instruction.
fn run8(c: *Chip8, raw: u16, vx: u8, vy: u8) !void {
    const inst = Decode(raw);
    c.V[inst.X] = vx;
    c.V[inst.Y] = vy;
    try Execute(c, inst);
}

test "8XY0 copies VY into VX" {
    var c = Chip8Init();
    try run8(&c, 0x8120, 0x00, 0x42);
    try std.testing.expectEqual(@as(u8, 0x42), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0x42), c.V[2]);
}

test "8XY1 / 8XY2 / 8XY3 logic, VF reset quirk" {
    var c = Chip8Init();
    c.V[0xF] = 5;
    try run8(&c, 0x8121, 0b1100, 0b1010);
    try std.testing.expectEqual(@as(u8, 0b1110), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    try run8(&c, 0x8122, 0b1100, 0b1010);
    try std.testing.expectEqual(@as(u8, 0b1000), c.V[1]);

    try run8(&c, 0x8123, 0b1100, 0b1010);
    try std.testing.expectEqual(@as(u8, 0b0110), c.V[1]);

    // With the quirk off, VF is not touched.
    c.quirks.logic_resets_vf = false;
    c.V[0xF] = 5;
    try run8(&c, 0x8121, 1, 2);
    try std.testing.expectEqual(@as(u8, 5), c.V[0xF]);
}

test "8XY4 add with carry" {
    var c = Chip8Init();
    try run8(&c, 0x8124, 200, 50);
    try std.testing.expectEqual(@as(u8, 250), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    try run8(&c, 0x8124, 200, 100); // 300 wraps to 44
    try std.testing.expectEqual(@as(u8, 44), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);
}

test "8XY5 subtract, VF = no borrow" {
    var c = Chip8Init();
    try run8(&c, 0x8125, 50, 20);
    try std.testing.expectEqual(@as(u8, 30), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);

    try run8(&c, 0x8125, 20, 50); // -30 wraps to 226
    try std.testing.expectEqual(@as(u8, 226), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    try run8(&c, 0x8125, 7, 7); // equal: no borrow
    try std.testing.expectEqual(@as(u8, 0), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);
}

test "8XY7 reverse subtract, VF = no borrow" {
    var c = Chip8Init();
    try run8(&c, 0x8127, 20, 50);
    try std.testing.expectEqual(@as(u8, 30), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);

    try run8(&c, 0x8127, 50, 20);
    try std.testing.expectEqual(@as(u8, 226), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);
}

test "8XY6 / 8XYE shifts use VY by default" {
    var c = Chip8Init();
    try run8(&c, 0x8126, 0xFF, 0b0000_0011);
    try std.testing.expectEqual(@as(u8, 0b0000_0001), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);

    try run8(&c, 0x812E, 0x00, 0b1000_0001);
    try std.testing.expectEqual(@as(u8, 0b0000_0010), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);
}

test "8XY6 / 8XYE shift VX in place with the quirk off" {
    var c = Chip8Init();
    c.quirks.shift_uses_vy = false;
    try run8(&c, 0x8126, 0b0000_0100, 0xFF);
    try std.testing.expectEqual(@as(u8, 0b0000_0010), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    try run8(&c, 0x812E, 0b0100_0000, 0xFF);
    try std.testing.expectEqual(@as(u8, 0b1000_0000), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);
}

test "8XY_ writes VF last when X is F" {
    var c = Chip8Init();
    try run8(&c, 0x8F14, 200, 100); // VF = VF + V1, carry
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]); // flag, not the sum 44
}

test "2NNN calls and 00EE returns" {
    var c = Chip8Init();
    // 0x200: call 0x300.  0x300: return.
    try LoadRom(&c, &.{ 0x23, 0x00 });
    c.memory[0x300] = 0x00;
    c.memory[0x301] = 0xEE;

    try Execute(&c, Fetch(&c)); // 2300
    try std.testing.expectEqual(@as(u16, 0x300), c.pc);
    try std.testing.expectEqual(@as(u8, 1), c.stack_ptr);
    try std.testing.expectEqual(@as(u16, 0x202), c.stack[0]); // return address

    try Execute(&c, Fetch(&c)); // 00EE
    try std.testing.expectEqual(@as(u16, 0x202), c.pc);
    try std.testing.expectEqual(@as(u8, 0), c.stack_ptr);
}

test "nested calls return in reverse order" {
    var c = Chip8Init();
    try push(&c, 0x111);
    try push(&c, 0x222);
    try std.testing.expectEqual(@as(u16, 0x222), try pop(&c));
    try std.testing.expectEqual(@as(u16, 0x111), try pop(&c));
}

test "stack overflow and underflow are errors" {
    var c = Chip8Init();
    try std.testing.expectError(error.StackUnderflow, Execute(&c, Decode(0x00EE)));

    for (0..16) |_| try Execute(&c, Decode(0x2400));
    try std.testing.expectError(error.StackOverflow, Execute(&c, Decode(0x2400)));
    try std.testing.expectEqual(@as(u8, 16), c.stack_ptr);
}

// Helper for the skip tests: run one instruction from 0x200 and return the new pc.
fn runSkip(c: *Chip8, raw: u16) !u16 {
    c.pc = 0x200;
    c.memory[0x200] = @truncate(raw >> 8);
    c.memory[0x201] = @truncate(raw);
    try Execute(c, Fetch(c));
    return c.pc;
}

test "3XNN skips if VX == NN" {
    var c = Chip8Init();
    c.V[3] = 0x42;
    try std.testing.expectEqual(@as(u16, 0x204), try runSkip(&c, 0x3342)); // equal: skip
    try std.testing.expectEqual(@as(u16, 0x202), try runSkip(&c, 0x3341)); // not equal
}

test "4XNN skips if VX != NN" {
    var c = Chip8Init();
    c.V[3] = 0x42;
    try std.testing.expectEqual(@as(u16, 0x202), try runSkip(&c, 0x4342)); // equal
    try std.testing.expectEqual(@as(u16, 0x204), try runSkip(&c, 0x4341)); // not equal: skip
}

test "5XY0 skips if VX == VY" {
    var c = Chip8Init();
    c.V[1] = 7;
    c.V[2] = 7;
    c.V[3] = 8;
    try std.testing.expectEqual(@as(u16, 0x204), try runSkip(&c, 0x5120)); // equal: skip
    try std.testing.expectEqual(@as(u16, 0x202), try runSkip(&c, 0x5130)); // not equal
    try std.testing.expectEqual(@as(u16, 0x202), try runSkip(&c, 0x5121)); // invalid last nibble
}
