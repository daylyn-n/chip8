#include "chip8_frontend.h"
#include "display.h"
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

static bool s_chip8[CHIP8_WIDTH * CHIP8_HEIGHT];
static u8 s_frame[1024];

static void checkerboard(void) {
  for (u32 y = 0; y < CHIP8_HEIGHT; y++) {
    for (u32 x = 0; x < CHIP8_WIDTH; x++) {
      s_chip8[y * CHIP8_WIDTH + x] = (x / 4 + y / 4) % 2 == 0;
    }
  }
  chip8_to_oled(s_chip8, s_frame);
}

// Display test: draws a 64x32 CHIP-8 checkerboard of 4x4 squares.
// The Zig conversion scales it to 8x8 squares on the screen.
// LED slow blink = OK. LED fast blink = an I2C transfer failed.
int main(void) {
  RCC->AHB1ENR |= (1u << 0); // GPIOA clock on, for the LED
  (void)RCC->AHB1ENR;
  gpio_set_mode(GPIOA, PA5, GPIO_OUTPUT);

  i2c1_init(I2C_100KHZ);

  if (display_init() != I2C_OK) {
    fail();
  }
  if (display_clear() != I2C_OK) {
    fail();
  }

  checkerboard();
  if (mcu_ram_to_display(s_frame) != I2C_OK) {
    fail();
  }

  while (1) {
    GPIOA->ODR ^= (1u << PA5);
    delay(1000000);
  }
}
