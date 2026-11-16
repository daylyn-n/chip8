#include "display.h"
#include "gpio.h"
#include "i2c.h"
#include "keypad.h"
#include "stm32.h"

// Keypad wiring probe: make probe
// The OLED shows 8 boxes. From left to right they are the wires on
// A0 A1 A2 A3 D6 D7 D8 D9. Hold one key: the 2 wires that it joins fill.

#define BOX_WIDTH 12u
#define BOX_STEP 16u
#define BOX_FIRST_PAGE 2u
#define BOX_LAST_PAGE 5u

static u8 s_frame[1024];

void systick_handler(void) {}

static void fail(void) {
  while (1) {
    GPIOA->ODR ^= (1u << PA5);
    for (volatile u32 i = 0; i < 50000; i++) {
    }
  }
}

static void draw_box(u32 index, bool filled) {
  u32 x0 = index * BOX_STEP + 2u;
  u32 x1 = x0 + BOX_WIDTH - 1u;
  for (u32 page = BOX_FIRST_PAGE; page <= BOX_LAST_PAGE; page++) {
    for (u32 x = x0; x <= x1; x++) {
      u8 b = 0;
      if (filled || x == x0 || x == x1) {
        b = 0xFF;
      } else if (page == BOX_FIRST_PAGE) {
        b = 0x01;
      } else if (page == BOX_LAST_PAGE) {
        b = 0x80;
      }
      s_frame[page * 128u + x] = b;
    }
  }
}

int main(void) {
  RCC->AHB1ENR |= (1u << 0);
  (void)RCC->AHB1ENR;
  gpio_set_mode(GPIOA, PA5, GPIO_OUTPUT);

  i2c1_init(I2C_400KHZ);
  keypad_probe_init();

  if (display_init() != I2C_OK || display_clear() != I2C_OK) {
    fail();
  }

  while (1) {
    u32 found = keypad_probe();
    for (u32 i = 0; i < 8; i++) {
      draw_box(i, ((found >> i) & 1u) != 0);
    }
    if (display_update(s_frame) != I2C_OK) {
      fail();
    }
    gpio_write(GPIOA, PA5, found != 0);
  }
}
