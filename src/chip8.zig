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
    // Both timers count down by 1, 60 times per second (see TickTimers).
    delay_timer: u8 = 0,
    sound_timer: u8 = 0, // the buzzer is on while this is above 0
    // keys[k] is true while hex key k (0x0 to 0xF) is down. Set by the platform.
    keys: [16]bool = @splat(false),
    // FX0A: the key that went down while waiting. null = no key seen yet.
    wait_key: ?u4 = null,
    rng: std.Random.DefaultPrng = .init(default_seed),
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
    // FX55 / FX65: true = I ends at I + X + 1 (original). false = I unchanged.
    memory_increments_i: bool = true,
    // BNNN: false = jump to NNN + V0 (original).
    // true = BXNN jumps to XNN + VX (CHIP-48 / SUPER-CHIP).
    jump_uses_vx: bool = false,
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
        c.memory[font_start + idx] = byte;
    }

    return c;
}

pub const font_start = 0x050; // 16 digits, 5 bytes each

// Memory addresses wrap at 4 KB, so a bad I can never index past the end.
fn WrapAddr(a: usize) usize {
    return a & 0xFFF;
}

// --- Platform interface: the frontend (SDL, STM32, ...) calls these. ---

// Call when hex key 0x0 to 0xF goes down or up.
pub fn SetKey(self: *Chip8, key: u4, down: bool) void {
    self.keys[key] = down;
}

// Call 60 times per second, separate from the instruction speed.
pub fn TickTimers(self: *Chip8) void {
    if (self.delay_timer > 0) self.delay_timer -= 1;
    if (self.sound_timer > 0) self.sound_timer -= 1;
}

// True while the buzzer must sound.
pub fn SoundOn(self: *const Chip8) bool {
    return self.sound_timer > 0;
}

pub const default_seed: u64 = 0xC8C8_C8C8;

// Set the seed for CXNN. The platform chooses the seed source:
// PC: OS random or the time. STM32: e.g. timer value at the first key press.
pub fn SeedRandom(self: *Chip8, seed: u64) void {
    self.rng.seed(seed);
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
// Addresses wrap at 4 KB: if pc is 0xFFF, the low byte comes from 0x000,
// and pc + 2 wraps to 0x001. So a broken ROM can never read past memory.
pub fn Fetch(self: *Chip8) Instructions {
    const hi_bits: u16 = self.memory[WrapAddr(self.pc)];
    const low_bits: u16 = self.memory[WrapAddr(@as(usize, self.pc) + 1)];
    self.pc = (self.pc + 2) & 0xFFF;
    return Decode((hi_bits << 8) | low_bits);
}

test "Fetch wraps at the end of memory" {
    var c = Chip8Init();
    c.pc = 0xFFF;
    c.memory[0xFFF] = 0x12;
    c.memory[0x000] = 0x34;
    const inst = Fetch(&c);
    try std.testing.expectEqual(@as(u16, 0x1234), inst.raw);
    try std.testing.expectEqual(@as(u16, 0x001), c.pc);
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

        const sprite_byte = self.memory[WrapAddr(self.I + row)];

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

// FX__: timers, keys, I, and memory. NN selects the operation.
pub fn Misc(self: *Chip8, inst: Instructions) void {
    const x = inst.X;
    switch (inst.NN) {
        // FX07: VX = delay timer
        0x07 => self.V[x] = self.delay_timer,
        // FX15: delay timer = VX
        0x15 => self.delay_timer = self.V[x],
        // FX18: sound timer = VX
        0x18 => self.sound_timer = self.V[x],

        // FX0A: wait for a key press, then store the key in VX.
        // Like the original, the key counts when it is RELEASED.
        // While waiting, pc goes back 2 so this instruction runs again.
        // The timers keep running while the program waits.
        0x0A => {
            if (self.wait_key) |k| {
                if (!self.keys[k]) {
                    self.V[x] = k;
                    self.wait_key = null;
                    return;
                }
            } else {
                for (self.keys, 0..) |down, k| {
                    if (down) {
                        self.wait_key = @intCast(k);
                        break;
                    }
                }
            }
            self.pc -= 2;
        },

        // FX1E: I = I + VX
        0x1E => self.I = @intCast(WrapAddr(@as(usize, self.I) + self.V[x])),

        // FX29: I = address of the font for the digit in VX (low nibble)
        0x29 => self.I = font_start + @as(u16, self.V[x] & 0xF) * 5,

        // FX33: store the decimal digits of VX at I, I+1, I+2.
        // Example: 156 -> 1, 5, 6.
        0x33 => {
            const v = self.V[x];
            self.memory[WrapAddr(self.I)] = v / 100;
            self.memory[WrapAddr(self.I + 1)] = (v / 10) % 10;
            self.memory[WrapAddr(self.I + 2)] = v % 10;
        },

        // FX55: store V0 to VX (inclusive) in memory, from I
        0x55 => {
            for (0..@as(usize, x) + 1) |r| self.memory[WrapAddr(self.I + r)] = self.V[r];
            if (self.quirks.memory_increments_i) self.I = @intCast(WrapAddr(@as(usize, self.I) + x + 1));
        },

        // FX65: load V0 to VX (inclusive) from memory, from I
        0x65 => {
            for (0..@as(usize, x) + 1) |r| self.V[r] = self.memory[WrapAddr(self.I + r)];
            if (self.quirks.memory_increments_i) self.I = @intCast(WrapAddr(@as(usize, self.I) + x + 1));
        },

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
            // opposite of 5XY0 skip if V[X] != V[Y]
            if (inst.N == 0 and self.V[inst.X] != self.V[inst.Y]) self.pc += 2;
        },
        0xA => {
            self.I = inst.NNN;
        },
        0xB => {
            // BNNN: jump to NNN + V0. Widen to u16 first: NNN is a u12, so
            // NNN + V0 could overflow. Wrap the result to stay inside memory.
            const offset: u16 = if (self.quirks.jump_uses_vx) self.V[inst.X] else self.V[0];
            self.pc = (@as(u16, inst.NNN) + offset) & 0xFFF;
        },
        // CXNN: VX = random byte AND NN. NN is a mask that limits the range.
        0xC => {
            self.V[inst.X] = self.rng.random().int(u8) & inst.NN;
        },
        0xD => {
            Draw(self, inst);
        },
        0xE => switch (inst.NN) {
            // EX9E: skip if the key in VX is down
            0x9E => {
                if (self.keys[self.V[inst.X] & 0xF]) self.pc += 2;
            },
            // EXA1: skip if the key in VX is up
            0xA1 => {
                if (!self.keys[self.V[inst.X] & 0xF]) self.pc += 2;
            },
            else => {},
        },
        0xF => Misc(self, inst),
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
fn Run8(c: *Chip8, raw: u16, vx: u8, vy: u8) !void {
    const inst = Decode(raw);
    c.V[inst.X] = vx;
    c.V[inst.Y] = vy;
    try Execute(c, inst);
}

test "8XY0 copies VY into VX" {
    var c = Chip8Init();
    try Run8(&c, 0x8120, 0x00, 0x42);
    try std.testing.expectEqual(@as(u8, 0x42), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0x42), c.V[2]);
}

test "8XY1 / 8XY2 / 8XY3 logic, VF reset quirk" {
    var c = Chip8Init();
    c.V[0xF] = 5;
    try Run8(&c, 0x8121, 0b1100, 0b1010);
    try std.testing.expectEqual(@as(u8, 0b1110), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    try Run8(&c, 0x8122, 0b1100, 0b1010);
    try std.testing.expectEqual(@as(u8, 0b1000), c.V[1]);

    try Run8(&c, 0x8123, 0b1100, 0b1010);
    try std.testing.expectEqual(@as(u8, 0b0110), c.V[1]);

    // With the quirk off, VF is not touched.
    c.quirks.logic_resets_vf = false;
    c.V[0xF] = 5;
    try Run8(&c, 0x8121, 1, 2);
    try std.testing.expectEqual(@as(u8, 5), c.V[0xF]);
}

test "8XY4 add with carry" {
    var c = Chip8Init();
    try Run8(&c, 0x8124, 200, 50);
    try std.testing.expectEqual(@as(u8, 250), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    try Run8(&c, 0x8124, 200, 100); // 300 wraps to 44
    try std.testing.expectEqual(@as(u8, 44), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);
}

test "8XY5 subtract, VF = no borrow" {
    var c = Chip8Init();
    try Run8(&c, 0x8125, 50, 20);
    try std.testing.expectEqual(@as(u8, 30), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);

    try Run8(&c, 0x8125, 20, 50); // -30 wraps to 226
    try std.testing.expectEqual(@as(u8, 226), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    try Run8(&c, 0x8125, 7, 7); // equal: no borrow
    try std.testing.expectEqual(@as(u8, 0), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);
}

test "8XY7 reverse subtract, VF = no borrow" {
    var c = Chip8Init();
    try Run8(&c, 0x8127, 20, 50);
    try std.testing.expectEqual(@as(u8, 30), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);

    try Run8(&c, 0x8127, 50, 20);
    try std.testing.expectEqual(@as(u8, 226), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);
}

test "8XY6 / 8XYE shifts use VY by default" {
    var c = Chip8Init();
    try Run8(&c, 0x8126, 0xFF, 0b0000_0011);
    try std.testing.expectEqual(@as(u8, 0b0000_0001), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);

    try Run8(&c, 0x812E, 0x00, 0b1000_0001);
    try std.testing.expectEqual(@as(u8, 0b0000_0010), c.V[1]);
    try std.testing.expectEqual(@as(u8, 1), c.V[0xF]);
}

test "8XY6 / 8XYE shift VX in place with the quirk off" {
    var c = Chip8Init();
    c.quirks.shift_uses_vy = false;
    try Run8(&c, 0x8126, 0b0000_0100, 0xFF);
    try std.testing.expectEqual(@as(u8, 0b0000_0010), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);

    try Run8(&c, 0x812E, 0b0100_0000, 0xFF);
    try std.testing.expectEqual(@as(u8, 0b1000_0000), c.V[1]);
    try std.testing.expectEqual(@as(u8, 0), c.V[0xF]);
}

test "8XY_ writes VF last when X is F" {
    var c = Chip8Init();
    try Run8(&c, 0x8F14, 200, 100); // VF = VF + V1, carry
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
fn RunSkip(c: *Chip8, raw: u16) !u16 {
    c.pc = 0x200;
    c.memory[0x200] = @truncate(raw >> 8);
    c.memory[0x201] = @truncate(raw);
    try Execute(c, Fetch(c));
    return c.pc;
}

test "3XNN skips if VX == NN" {
    var c = Chip8Init();
    c.V[3] = 0x42;
    try std.testing.expectEqual(@as(u16, 0x204), try RunSkip(&c, 0x3342)); // equal: skip
    try std.testing.expectEqual(@as(u16, 0x202), try RunSkip(&c, 0x3341)); // not equal
}

test "4XNN skips if VX != NN" {
    var c = Chip8Init();
    c.V[3] = 0x42;
    try std.testing.expectEqual(@as(u16, 0x202), try RunSkip(&c, 0x4342)); // equal
    try std.testing.expectEqual(@as(u16, 0x204), try RunSkip(&c, 0x4341)); // not equal: skip
}

test "5XY0 skips if VX == VY" {
    var c = Chip8Init();
    c.V[1] = 7;
    c.V[2] = 7;
    c.V[3] = 8;
    try std.testing.expectEqual(@as(u16, 0x204), try RunSkip(&c, 0x5120)); // equal: skip
    try std.testing.expectEqual(@as(u16, 0x202), try RunSkip(&c, 0x5130)); // not equal
    try std.testing.expectEqual(@as(u16, 0x202), try RunSkip(&c, 0x5121)); // invalid last nibble
}

test "CXNN masks the random byte with NN" {
    var c = Chip8Init();
    for (0..100) |_| {
        try Execute(&c, Decode(0xC000));
        try std.testing.expectEqual(@as(u8, 0), c.V[0]);

        try Execute(&c, Decode(0xC10F));
        try std.testing.expectEqual(@as(u8, 0), c.V[1] & 0xF0); // high bits always 0
    }
}

test "CXNN gives the same numbers for the same seed" {
    var a = Chip8Init();
    var b = Chip8Init();
    SeedRandom(&a, 1234);
    SeedRandom(&b, 1234);
    for (0..20) |_| {
        try Execute(&a, Decode(0xC0FF));
        try Execute(&b, Decode(0xC0FF));
        try std.testing.expectEqual(a.V[0], b.V[0]);
    }
}

test "CXNN gives more than one value" {
    var c = Chip8Init();
    var seen: [256]bool = @splat(false);
    var count: usize = 0;
    for (0..100) |_| {
        try Execute(&c, Decode(0xC0FF));
        if (!seen[c.V[0]]) {
            seen[c.V[0]] = true;
            count += 1;
        }
    }
    try std.testing.expect(count > 10);
}

test "9XY0 skips if VX != VY" {
    var c = Chip8Init();
    c.V[1] = 7;
    c.V[2] = 7;
    c.V[3] = 8;
    try std.testing.expectEqual(@as(u16, 0x202), try RunSkip(&c, 0x9120)); // equal
    try std.testing.expectEqual(@as(u16, 0x204), try RunSkip(&c, 0x9130)); // not equal: skip
}

test "BNNN jumps to NNN + V0, with no overflow" {
    var c = Chip8Init();
    c.V[0] = 0x10;
    try Execute(&c, Decode(0xB300));
    try std.testing.expectEqual(@as(u16, 0x310), c.pc);

    c.V[0] = 0xFF;
    try Execute(&c, Decode(0xBFFF)); // 0xFFF + 0xFF must not panic
    try std.testing.expectEqual(@as(u16, (0xFFF + 0xFF) & 0xFFF), c.pc);
}

test "BXNN uses VX with the quirk on" {
    var c = Chip8Init();
    c.quirks.jump_uses_vx = true;
    c.V[0] = 0x99;
    c.V[3] = 0x10;
    try Execute(&c, Decode(0xB300));
    try std.testing.expectEqual(@as(u16, 0x310), c.pc);
}

test "EX9E / EXA1 skip on key state" {
    var c = Chip8Init();
    c.V[2] = 0xA;
    SetKey(&c, 0xA, true);
    try std.testing.expectEqual(@as(u16, 0x204), try RunSkip(&c, 0xE29E)); // down: skip
    try std.testing.expectEqual(@as(u16, 0x202), try RunSkip(&c, 0xE2A1));

    SetKey(&c, 0xA, false);
    try std.testing.expectEqual(@as(u16, 0x202), try RunSkip(&c, 0xE29E));
    try std.testing.expectEqual(@as(u16, 0x204), try RunSkip(&c, 0xE2A1)); // up: skip
}

test "FX07 / FX15 / FX18 and TickTimers" {
    var c = Chip8Init();
    c.V[1] = 2;
    try Execute(&c, Decode(0xF115)); // delay = 2
    try Execute(&c, Decode(0xF118)); // sound = 2
    try std.testing.expect(SoundOn(&c));

    TickTimers(&c);
    try Execute(&c, Decode(0xF207)); // V2 = delay
    try std.testing.expectEqual(@as(u8, 1), c.V[2]);

    TickTimers(&c);
    TickTimers(&c); // must stop at 0, not wrap to 255
    try std.testing.expectEqual(@as(u8, 0), c.delay_timer);
    try std.testing.expect(!SoundOn(&c));
}

test "FX0A waits for a key press and release" {
    var c = Chip8Init();
    try LoadRom(&c, &.{ 0xF3, 0x0A }); // wait for key -> V3

    try Execute(&c, Fetch(&c)); // no key: repeat
    try std.testing.expectEqual(@as(u16, 0x200), c.pc);

    SetKey(&c, 0x7, true);
    try Execute(&c, Fetch(&c)); // key down: still waiting for release
    try std.testing.expectEqual(@as(u16, 0x200), c.pc);

    SetKey(&c, 0x7, false);
    try Execute(&c, Fetch(&c)); // released: done
    try std.testing.expectEqual(@as(u16, 0x202), c.pc);
    try std.testing.expectEqual(@as(u8, 0x7), c.V[3]);
}

test "FX1E adds VX to I" {
    var c = Chip8Init();
    c.I = 0x300;
    c.V[4] = 0x20;
    try Execute(&c, Decode(0xF41E));
    try std.testing.expectEqual(@as(u16, 0x320), c.I);
}

test "FX29 points I at the font digit" {
    var c = Chip8Init();
    c.V[5] = 0xA;
    try Execute(&c, Decode(0xF529));
    try std.testing.expectEqual(@as(u16, 0x050 + 0xA * 5), c.I);
}

test "FX33 stores decimal digits" {
    var c = Chip8Init();
    c.I = 0x300;
    c.V[6] = 156;
    try Execute(&c, Decode(0xF633));
    try std.testing.expectEqualSlices(u8, &.{ 1, 5, 6 }, c.memory[0x300..0x303]);
}

test "FX55 / FX65 store and load V0..VX" {
    var c = Chip8Init();
    c.I = 0x300;
    c.V[0] = 11;
    c.V[1] = 22;
    c.V[2] = 33;
    c.V[3] = 44; // not stored: X is 2
    try Execute(&c, Decode(0xF255));
    try std.testing.expectEqualSlices(u8, &.{ 11, 22, 33, 0 }, c.memory[0x300..0x304]);
    try std.testing.expectEqual(@as(u16, 0x303), c.I); // original quirk: I + X + 1

    c.V = @splat(0);
    c.I = 0x300;
    try Execute(&c, Decode(0xF265));
    try std.testing.expectEqualSlices(u8, &.{ 11, 22, 33, 0 }, c.V[0..4]);
}

test "FX55 leaves I unchanged with the quirk off" {
    var c = Chip8Init();
    c.quirks.memory_increments_i = false;
    c.I = 0x300;
    try Execute(&c, Decode(0xF255));
    try std.testing.expectEqual(@as(u16, 0x300), c.I);
}
