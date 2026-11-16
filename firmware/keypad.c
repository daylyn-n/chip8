#include "keypad.h"
#include "gpio.h"

#define RCC_AHB1ENR_GPIOAEN (1u << 0)
#define RCC_AHB1ENR_GPIOBEN (1u << 1)
#define RCC_AHB1ENR_GPIOCEN (1u << 2)

typedef struct {
  GPIO *port;
  u8 pin;
} Pin;

static const Pin s_rows[KEYPAD_ROWS] = {
    {GPIOA, 0},
    {GPIOA, 1},
    {GPIOA, 4},
    {GPIOB, 0},
};

static const Pin s_cols[KEYPAD_COLS] = {
    {GPIOB, 10},
    {GPIOA, 8},
    {GPIOA, 9},
    {GPIOC, 7},
};

void keypad_init(void) {
  RCC->AHB1ENR |=
      RCC_AHB1ENR_GPIOAEN | RCC_AHB1ENR_GPIOBEN | RCC_AHB1ENR_GPIOCEN;
  (void)RCC->AHB1ENR;

  for (u32 i = 0; i < KEYPAD_ROWS; i++) {
    gpio_write(s_rows[i].port, s_rows[i].pin, 1);
    gpio_set_otype(s_rows[i].port, s_rows[i].pin, GPIO_OPEN_DRAIN);
    gpio_set_pull(s_rows[i].port, s_rows[i].pin, GPIO_NO_PULL);
    gpio_set_speed(s_rows[i].port, s_rows[i].pin, GPIO_SPEED_LOW);
    gpio_set_mode(s_rows[i].port, s_rows[i].pin, GPIO_OUTPUT);
  }

  for (u32 i = 0; i < KEYPAD_COLS; i++) {
    gpio_set_pull(s_cols[i].port, s_cols[i].pin, GPIO_PULL_UP);
    gpio_set_mode(s_cols[i].port, s_cols[i].pin, GPIO_INPUT);
  }
}
