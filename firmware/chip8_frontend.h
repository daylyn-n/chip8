#ifndef CHIP8_FRONTEND_H
#define CHIP8_FRONTEND_H

#include "stm32.h"

// C side of src/stm32_frontend.zig.

enum {
  CHIP8_OK = 0,
  CHIP8_ROM_TOO_LARGE = 1,
  CHIP8_STACK_OVERFLOW = 2,
  CHIP8_STACK_UNDERFLOW = 3,
};

// Resets the machine and copies the ROM to 0x200.
int chip8_init(const u8 *rom, u32 len);

// Runs one frame: 11 instructions, then one timer tick. Call 60 times/second.
int chip8_frame(void);

// Fills out with an OLED frame. Returns false if the screen did not change.
bool chip8_render(u8 out[1024]);

bool chip8_sound_on(void);

#endif
