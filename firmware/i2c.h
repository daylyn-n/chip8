#ifndef I2C_H
#define I2C_H

#include "stm32.h"

// I2C1 master, transmit only.
// Pins: PB8 = SCL (D15), PB9 = SDA (D14), both AF4, open-drain.
// Addresses are 7-bit, for example 0x3C. The driver shifts them.

enum { I2C_100KHZ = 0, I2C_400KHZ = 1 };

typedef enum {
  I2C_OK = 0,
  I2C_NACK = 1,
  I2C_TIMEOUT = 2,
} I2cResult;

void i2c1_init(u32 speed);

I2cResult i2c1_write(u8 addr, const u8 *data, u32 len);

I2cResult i2c1_begin(u8 addr);
I2cResult i2c1_send(u8 byte);
I2cResult i2c1_end(void);

// Returns I2C_OK if a device answers at this address.
I2cResult i2c1_probe(u8 addr);

#endif
