#include "chip8_frontend.h"
#include "display.h"
#include "gpio.h"
#include "i2c.h"
#include "keypad.h"
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
#define SYSTICK_INTERRUPT (1u << 1)
#define SYSTICK_CPU_CLOCK (1u << 2)

// After a slow screen update, run at most this many missed frames.
#define MAX_CATCH_UP 6u

extern const u8 chip8_rom[];
extern const u8 chip8_rom_end[];

static u8 s_frame[1024];

// Keypad bit (row * 4 + col) -> CHIP-8 key. Mapped by position:
//   1 2 3 A      1 2 3 C
//   4 5 6 B  ->  4 5 6 D
//   7 8 9 C      7 8 9 E
//   * 0 # D      A 0 B F
static const u8 s_chip8_key[16] = {
    0x1, 0x2, 0x3, 0xC, 0x4, 0x5, 0x6, 0xD,
    0x7, 0x8, 0x9, 0xE, 0xA, 0x0, 0xB, 0xF,
};

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

// Counts SysTick wraps: 60 per second. Only the interrupt writes it.
static volatile u32 s_ticks = 0;

void systick_handler(void) { s_ticks++; }

static void systick_init_60hz(void) {
  SYSTICK->LOAD = CPU_HZ / 60u - 1u;
  SYSTICK->VAL = 0;
  SYSTICK->CTRL = SYSTICK_CPU_CLOCK | SYSTICK_INTERRUPT | SYSTICK_ENABLE;
}

// Reads the keypad and sends each key to the core.
// The first key press seeds the random numbers with the SysTick count.
static void update_keys(void) {
  static bool seeded = false;
  u32 down = keypad_scan();
  if (!seeded && down != 0) {
    chip8_seed(SYSTICK->VAL ^ (s_ticks << 18));
    seeded = true;
  }
  for (u32 i = 0; i < 16; i++) {
    chip8_set_key(s_chip8_key[i], ((down >> i) & 1u) != 0);
  }
}

// Runs the ROM from rom.bin (make ROM=...) at 60 frames per second.
// If a screen update is slow, the missed frames run after it,
// so the game speed and the CHIP-8 timers stay correct.
// LED: on/off each second = running. Fast blink = I2C error.
// N blinks, then a pause = CHIP-8 error N (see chip8_frontend.h).
int main(void) {
  RCC->AHB1ENR |= (1u << 0); // GPIOA clock on, for the LED
  (void)RCC->AHB1ENR;
  gpio_set_mode(GPIOA, PA5, GPIO_OUTPUT);

  i2c1_init(I2C_400KHZ);
  keypad_init();

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
  u32 done = 0;
  while (1) {
    while (s_ticks == done) {
    }

    u32 behind = s_ticks - done;
    if (behind > MAX_CATCH_UP) {
      done += behind - MAX_CATCH_UP;
      behind = MAX_CATCH_UP;
    }
    update_keys();
    for (; behind > 0; behind--) {
      r = chip8_frame();
      if (r != CHIP8_OK) {
        chip8_fail(r);
      }
      done++;
    }

    if (chip8_render(s_frame) && display_update(s_frame) != I2C_OK) {
      fail();
    }

    led_on((done / 60u) % 2u == 0);
  }
}
