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
    {GPIOB, 10},
    {GPIOA, 8},
    {GPIOA, 9},
    {GPIOC, 7},
};

static const Pin s_cols[KEYPAD_COLS] = {
    {GPIOA, 0},
    {GPIOA, 1},
    {GPIOA, 4},
    {GPIOB, 0},
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

static void settle(void) {
  for (volatile u32 i = 0; i < 40; i++) {
  }
}

u32 keypad_scan(void) {
  u32 down = 0;
  for (u32 r = 0; r < KEYPAD_ROWS; r++) {
    gpio_write(s_rows[r].port, s_rows[r].pin, 0);
    settle();
    for (u32 c = 0; c < KEYPAD_COLS; c++) {
      if ((s_cols[c].port->IDR & (1u << s_cols[c].pin)) == 0) {
        down |= 1u << (r * KEYPAD_COLS + c);
      }
    }
    gpio_write(s_rows[r].port, s_rows[r].pin, 1);
  }
  settle();
  return down;
}

#define KEYPAD_WIRES (KEYPAD_ROWS + KEYPAD_COLS)

static const Pin s_wires[KEYPAD_WIRES] = {
    {GPIOA, 0}, {GPIOA, 1},  {GPIOA, 4}, {GPIOB, 0},
    {GPIOB, 10}, {GPIOA, 8}, {GPIOA, 9}, {GPIOC, 7},
};

static const Pin *wire(u32 i) { return &s_wires[i]; }

void keypad_probe_init(void) {
  RCC->AHB1ENR |=
      RCC_AHB1ENR_GPIOAEN | RCC_AHB1ENR_GPIOBEN | RCC_AHB1ENR_GPIOCEN;
  (void)RCC->AHB1ENR;

  for (u32 i = 0; i < KEYPAD_WIRES; i++) {
    const Pin *w = wire(i);
    gpio_write(w->port, w->pin, 1);
    gpio_set_otype(w->port, w->pin, GPIO_OPEN_DRAIN);
    gpio_set_pull(w->port, w->pin, GPIO_PULL_UP);
    gpio_set_speed(w->port, w->pin, GPIO_SPEED_LOW);
    gpio_set_mode(w->port, w->pin, GPIO_OUTPUT);
  }
}

u32 keypad_probe(void) {
  u32 found = 0;
  for (u32 i = 0; i < KEYPAD_WIRES; i++) {
    const Pin *a = wire(i);
    gpio_write(a->port, a->pin, 0);
    settle();
    for (u32 j = 0; j < KEYPAD_WIRES; j++) {
      const Pin *b = wire(j);
      if (j != i && (b->port->IDR & (1u << b->pin)) == 0) {
        found |= (1u << i) | (1u << j);
      }
    }
    gpio_write(a->port, a->pin, 1);
    settle();
  }
  return found;
}
