#ifndef DISPLAY_H
#define DISPLAY_H

#include "i2c.h"
#include "stm32.h"
#include <stdbool.h>

// 1.3" 128x64 OLED over I2C1. The chip is an SH1106 or an SSD1306.
// The init steps below work on both chips.

// Finds the screen (0x3C or 0x3D), and sends the init commands.
// Call i2c1_init() first. Returns I2C_OK when the screen is ready.
I2cResult display_init(void);

// Sends one command, or a list of commands, in one transfer.
I2cResult display_command(u8 cmd);
I2cResult display_commands(const u8 *cmds, u32 len);

// Writes zeros to all 8 pages of the screens ram
// 1 page is a hortizontal band that is 8 pixels high
I2cResult display_clear(void);

I2cResult display_set_pixel(u8 x, u8 y, bool on);
I2cResult mcu_ram_to_display(const u8 buffer[1024]);
#endif
