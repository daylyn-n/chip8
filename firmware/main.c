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

// Display test for the OLED and the logic analyzer.
//
// display_init() finds the screen and turns it on. The loop then
// switches every second between "all pixels on" and "show RAM".
// RAM is random after power-on, so "show RAM" looks like noise.
//
// LED slow blink = OK. LED fast blink = an I2C transfer failed.
int main(void) {
  RCC->AHB1ENR |= (1u << 0); // GPIOA clock on, for the LED
  (void)RCC->AHB1ENR;
  gpio_set_mode(GPIOA, PA5, GPIO_OUTPUT);

  i2c1_init(I2C_100KHZ);

  if (display_init() != I2C_OK) {
    fail();
  }

  while (1) {
    if (display_command(0xA5) != I2C_OK) { // every pixel on, ignores RAM
      fail();
    }
    GPIOA->ODR ^= (1u << PA5);
    delay(1000000);

    if (display_command(0xA4) != I2C_OK) { // pixels follow RAM again
      fail();
    }
    GPIOA->ODR ^= (1u << PA5);
    delay(1000000);
  }
}
