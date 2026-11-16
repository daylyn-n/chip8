#include "display.h"

// The first byte of each I2C transfer is the control byte.
// It replaces the DC pin of the SPI version.
#define CONTROL_COMMAND 0x00 // the next bytes are commands
#define CONTROL_DATA 0x40    // the next bytes are pixels (for later)

// The address that answered in display_init(). 0 = not found.
static u8 s_addr = 0;

#define COLUMN_OFFSET 2

static u8 s_fb[1024];

I2cResult display_commands(const u8 *cmds, u32 len) {
  I2cResult r = i2c1_begin(s_addr);
  if (r == I2C_OK) {
    r = i2c1_send(CONTROL_COMMAND);
  }
  for (u32 i = 0; i < len && r == I2C_OK; i++) {
    r = i2c1_send(cmds[i]);
  }
  I2cResult end = i2c1_end(); // always free the bus, even after an error
  return r != I2C_OK ? r : end;
}

I2cResult display_command(u8 cmd) { return display_commands(&cmd, 1); }

// chapter 9 of the SSD1306 data sheet for each of the commands
//
static const u8 init_cmds[] = {
    0xAE, 0xD5, 0x80, 0xA8, 0x3F, 0xD3, 0x00, 0x40, 0x8D, 0x14, 0xA1, 0xC8,
    0xDA, 0x12, 0x81, 0x7F, 0xD9, 0xF1, 0xDB, 0x40, 0xA4, 0xA6, 0xAF,
};

I2cResult display_init(void) {
  s_addr = 0x3C;
  if (i2c1_probe(s_addr) != I2C_OK) {
    s_addr = 0x3D;
    I2cResult r = i2c1_probe(s_addr);
    if (r != I2C_OK) {
      s_addr = 0;
      return r;
    }
  }
  return display_commands(init_cmds, sizeof init_cmds);
}

I2cResult display_clear(void) {
  for (u32 i = 0; i < sizeof s_fb; i++) {
    s_fb[i] = 0;
  }
  for (u8 page = 0; page < 8; page++) {
    const u8 cmds[] = {0xB0 | page, 0x00, 0x10};
    I2cResult r = display_commands(cmds, sizeof cmds);
    if (r != I2C_OK) {
      return r;
    }

    r = i2c1_begin(s_addr);
    if (r == I2C_OK) {
      r = i2c1_send(CONTROL_DATA);
    }
    for (u32 i = 0; i < 132 && r == I2C_OK; i++) {
      r = i2c1_send(0x00);
    }
    I2cResult end = i2c1_end();
    if (r != I2C_OK) {
      return r;
    }
    if (end != I2C_OK) {
      return end;
    }
  }
  return I2C_OK;
}

I2cResult display_set_pixel(u8 x, u8 y, bool on) {
  if (x >= 128 || y >= 64) {
    return I2C_OK;
  }

  u8 page = y / 8;
  u8 mask = (u8)(1u << (y % 8));
  u8 *cell = &s_fb[page * 128u + x];
  if (on) {
    *cell |= mask;
  } else {
    *cell &= (u8)~mask;
  }

  u8 col = x + COLUMN_OFFSET;
  const u8 cmds[] = {0xB0 | page, col & 0x0F, 0x10 | (col >> 4)};
  I2cResult r = display_commands(cmds, sizeof cmds);
  if (r != I2C_OK) {
    return r;
  }

  r = i2c1_begin(s_addr);
  if (r == I2C_OK) {
    r = i2c1_send(CONTROL_DATA);
  }
  if (r == I2C_OK) {
    r = i2c1_send(*cell);
  }
  I2cResult end = i2c1_end();
  return r != I2C_OK ? r : end;
}

I2cResult mcu_ram_to_display(const u8 buffer[1024]) {
  for (u32 i = 0; i < sizeof s_fb; i++) {
    s_fb[i] = buffer[i];
  }

  for (u8 page = 0; page < 8; page++) {
    const u8 cmds[] = {0xB0 | page, COLUMN_OFFSET & 0x0F,
                       0x10 | (COLUMN_OFFSET >> 4)};
    I2cResult r = display_commands(cmds, sizeof cmds);
    if (r != I2C_OK) {
      return r;
    }

    r = i2c1_begin(s_addr);
    if (r == I2C_OK) {
      r = i2c1_send(CONTROL_DATA);
    }
    for (u32 i = 0; i < 128 && r == I2C_OK; i++) {
      r = i2c1_send(s_fb[page * 128u + i]);
    }
    I2cResult end = i2c1_end();
    if (r != I2C_OK) {
      return r;
    }
    if (end != I2C_OK) {
      return end;
    }
  }
  return I2C_OK;
}
