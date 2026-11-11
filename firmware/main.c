#include "gpio.h"
#include "i2c.h"
#include "stm32.h"

static void delay(volatile u32 count) {
  while (count--) {
  }
}

// Blink the LED forever. Fast = error.
static void fail(void) {
  while (1) {
    GPIOA->ODR ^= (1u << PA5);
    delay(50000);
  }
}

// I2C test for the OLED and the logic analyzer.
//
// The test finds the OLED address, turns the display on, and then
// switches every second between "all pixels on" and "show RAM".
// RAM is random after power-on, so "show RAM" looks like noise.
// These commands are the same on the SSD1306 and the SH1106.
//
// LED slow blink = OK. LED fast blink = no device answered.
int main(void) {
  RCC->AHB1ENR |= (1u << 0); // GPIOA clock on, for the LED
  (void)RCC->AHB1ENR;
  gpio_set_mode(GPIOA, PA5, GPIO_OUTPUT);

  i2c1_init(I2C_100KHZ); // slow first: easy to read on the analyzer

  u8 addr = 0x3C;
  if (i2c1_probe(addr) != I2C_OK) {
    addr = 0x3D;
    if (i2c1_probe(addr) != I2C_OK) {
      fail();
    }
  }

  // 0x00 = control byte: "commands follow".
  const u8 on[] = {
      0x00,
      0xAE,       // display off
      0x8D, 0x14, // SSD1306: charge pump on (the SH1106 ignores it)
      0xAF,       // display on
  };
  if (i2c1_write(addr, on, sizeof on) != I2C_OK) {
    fail();
  }

  const u8 all_on[] = {0x00, 0xA5};   // every pixel on, ignores RAM
  const u8 show_ram[] = {0x00, 0xA4}; // normal: pixels follow RAM

  while (1) {
    if (i2c1_write(addr, all_on, sizeof all_on) != I2C_OK) {
      fail();
    }
    GPIOA->ODR ^= (1u << PA5);
    delay(1000000);

    if (i2c1_write(addr, show_ram, sizeof show_ram) != I2C_OK) {
      fail();
    }
    GPIOA->ODR ^= (1u << PA5);
    delay(1000000);
  }
}
