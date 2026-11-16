#ifndef CHIP8_FRONTEND_H
#define CHIP8_FRONTEND_H

#include "stm32.h"

#define CHIP8_WIDTH 64
#define CHIP8_HEIGHT 32

void chip8_to_oled(const bool display[CHIP8_WIDTH * CHIP8_HEIGHT],
                   u8 out[1024]);

#endif
