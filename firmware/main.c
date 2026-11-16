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

#define SYSTICK_ENABLE (1u << 0)
#define SYSTICK_CPU_CLOCK (1u << 2)
#define SYSTICK_COUNTFLAG (1u << 16)

extern const u8 chip8_rom[];
extern const u8 chip8_rom_end[];

static u8 s_frame[1024];

static void led_on(bool on) {
  if (on) {
    GPIOA->ODR |= (1u << PA5);
  } else {
    GPIOA->ODR &= ~(1u << PA5);
  }
}

// CHIP-8 error: blink `code` times, pause, repeat forever.
static void chip8_fail(int code) {
  while (1) {
    for (int i = 0; i < code; i++) {
      led_on(true);
      delay(400000);
      led_on(false);
      delay(400000);
    }
    delay(2000000);
  }
}

// SysTick wraps 60 times per second. COUNTFLAG is set at each wrap.
static void systick_init_60hz(void) {
  SYSTICK->LOAD = CPU_HZ / 60u - 1u;
  SYSTICK->VAL = 0;
  SYSTICK->CTRL = SYSTICK_CPU_CLOCK | SYSTICK_ENABLE;
}

static void wait_frame(void) {
  while ((SYSTICK->CTRL & SYSTICK_COUNTFLAG) == 0) {
  }
}

// Runs the ROM from rom.bin (make ROM=...) at 60 frames per second.
// LED: on/off each second = running. Fast blink = I2C error.
// N blinks, then a pause = CHIP-8 error N (see chip8_frontend.h).
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

  int r = chip8_init(chip8_rom, (u32)(chip8_rom_end - chip8_rom));
  if (r != CHIP8_OK) {
    chip8_fail(r);
  }

  systick_init_60hz();
  u32 frames = 0;
  while (1) {
    wait_frame();

    r = chip8_frame();
    if (r != CHIP8_OK) {
      chip8_fail(r);
    }

    if (chip8_render(s_frame) && mcu_ram_to_display(s_frame) != I2C_OK) {
      fail();
    }

    if (++frames % 60u == 0) {
      GPIOA->ODR ^= (1u << PA5);
    }
  }
}
