#include "i2c.h"
#include "gpio.h"

// CR1 bits
#define I2C_CR1_PE (1u << 0)
#define I2C_CR1_START (1u << 8)
#define I2C_CR1_STOP (1u << 9)

// SR1 bits
#define I2C_SR1_SB (1u << 0)   // START was sent
#define I2C_SR1_ADDR (1u << 1) // address was sent and ACKed
#define I2C_SR1_BTF (1u << 2)  // last byte fully sent
#define I2C_SR1_TXE (1u << 7)  // DR is empty, write the next byte
#define I2C_SR1_AF (1u << 10)  // NACK received

// SR2 bits
#define I2C_SR2_BUSY (1u << 1)

// CCR bits
#define I2C_CCR_FS (1u << 15) // fast mode (400 kHz)

#define RCC_AHB1ENR_GPIOBEN (1u << 1)
#define RCC_APB1ENR_I2C1EN (1u << 21)
#define RCC_APB1RSTR_I2C1RST (1u << 21)

// APB1 clock in MHz. After reset the chip runs on HSI (16 MHz),
// and APB1 has no divider. Change this if you change the clock setup.
#define PCLK1_MHZ 16u

// Loop count before a wait gives up. At 16 MHz this is a few ms,
// which is much longer than one byte at 100 kHz (90 us).
#define I2C_TIMEOUT_LOOPS 50000u

void i2c1_init(u32 speed) {
  RCC->AHB1ENR |= RCC_AHB1ENR_GPIOBEN;
  RCC->APB1ENR |= RCC_APB1ENR_I2C1EN;
  (void)RCC->APB1ENR; // short wait after the clock enable (errata)

  // Reset the peripheral. This clears a BUSY flag left from an
  // earlier run, for example after you flash during a transfer.
  RCC->APB1RSTR |= RCC_APB1RSTR_I2C1RST;
  RCC->APB1RSTR &= ~RCC_APB1RSTR_I2C1RST;

  // PB8 = SCL, PB9 = SDA. Open-drain: devices only pull the lines low.
  // The OLED module has pull-up resistors. The internal ones (~40k)
  // are a weak backup, in case a module has none.
  const u8 pins[] = {PB8, PB9};
  for (u32 i = 0; i < 2; i++) {
    gpio_set_otype(GPIOB, pins[i], GPIO_OPEN_DRAIN);
    gpio_set_pull(GPIOB, pins[i], GPIO_PULL_UP);
    gpio_set_speed(GPIOB, pins[i], GPIO_SPEED_HIGH);
    gpio_set_af(GPIOB, pins[i], 4);
    gpio_set_mode(GPIOB, pins[i], GPIO_AF);
  }

  I2C1->CR1 = 0;          // PE must be off while you set the timing
  I2C1->CR2 = PCLK1_MHZ; // FREQ field: APB1 clock in MHz

  if (speed == I2C_400KHZ) {
    // Fast mode, duty 2:1. SCL period = 3 * CCR / PCLK1.
    // 16 MHz / (3 * 14) = 381 kHz (13 would be 410 kHz, above the limit).
    I2C1->CCR = I2C_CCR_FS | 14u;
    // Max rise time 300 ns: 300 ns * 16 MHz = 4.8, round down, + 1.
    I2C1->TRISE = (PCLK1_MHZ * 300u / 1000u) + 1u;
  } else {
    // Standard mode. SCL period = 2 * CCR / PCLK1.
    // 16 MHz / (2 * 80) = 100 kHz.
    I2C1->CCR = PCLK1_MHZ * 5u;
    // Max rise time 1000 ns: 1000 ns * 16 MHz = 16, + 1.
    I2C1->TRISE = PCLK1_MHZ + 1u;
  }

  I2C1->CR1 = I2C_CR1_PE; // turn I2C on last
}

// True after a byte was sent with no error. i2c1_end() then waits for
// that byte to finish. After an error, BTF never sets, so it must not wait.
static u8 s_pending = 0;

// Wait until all bits in `mask` are set in SR1.
// Stops early if the device sends a NACK.
static I2cResult wait_sr1(u32 mask) {
  for (u32 n = 0; n < I2C_TIMEOUT_LOOPS; n++) {
    u32 sr1 = I2C1->SR1;
    if (sr1 & I2C_SR1_AF) {
      I2C1->SR1 &= ~I2C_SR1_AF; // clear the NACK flag
      return I2C_NACK;
    }
    if ((sr1 & mask) == mask) {
      return I2C_OK;
    }
  }
  return I2C_TIMEOUT;
}

I2cResult i2c1_begin(u8 addr) {
  s_pending = 0;

  // Wait until no other transfer uses the bus.
  u32 n = 0;
  while (I2C1->SR2 & I2C_SR2_BUSY) {
    if (++n >= I2C_TIMEOUT_LOOPS) {
      return I2C_TIMEOUT;
    }
  }

  I2C1->CR1 |= I2C_CR1_START;
  I2cResult r = wait_sr1(I2C_SR1_SB);
  if (r != I2C_OK) {
    return r;
  }

  // 7-bit address in bits 7:1. Bit 0 = 0 means "write".
  I2C1->DR = (u32)(addr << 1);
  r = wait_sr1(I2C_SR1_ADDR);
  if (r != I2C_OK) {
    return r;
  }

  // The hardware clears ADDR when you read SR1 and then SR2.
  // Until then, it holds SCL low and the transfer cannot go on.
  (void)I2C1->SR1;
  (void)I2C1->SR2;
  return I2C_OK;
}

I2cResult i2c1_send(u8 byte) {
  I2cResult r = wait_sr1(I2C_SR1_TXE);
  if (r != I2C_OK) {
    s_pending = 0;
    return r;
  }
  I2C1->DR = byte;
  s_pending = 1;
  return I2C_OK;
}

I2cResult i2c1_end(void) {
  // Wait for the last byte to leave the shift register.
  I2cResult r = I2C_OK;
  if (s_pending) {
    r = wait_sr1(I2C_SR1_BTF);
    s_pending = 0;
  }

  I2C1->CR1 |= I2C_CR1_STOP;

  // The hardware clears STOP when the STOP condition is on the bus.
  // A START set before that point can be lost.
  u32 n = 0;
  while (I2C1->CR1 & I2C_CR1_STOP) {
    if (++n >= I2C_TIMEOUT_LOOPS) {
      return I2C_TIMEOUT;
    }
  }
  return r;
}

I2cResult i2c1_write(u8 addr, const u8 *data, u32 len) {
  I2cResult r = i2c1_begin(addr);
  for (u32 i = 0; i < len && r == I2C_OK; i++) {
    r = i2c1_send(data[i]);
  }
  I2cResult end = i2c1_end();
  return r != I2C_OK ? r : end;
}

I2cResult i2c1_probe(u8 addr) {
  I2cResult r = i2c1_begin(addr);
  i2c1_end();
  return r;
}
