#include "gpio.h"

void gpio_set_mode(GPIO *port, u8 pin, u32 mode) {
  port->MODER &= ~(3u << (pin * 2));
  port->MODER |= ((mode) << (pin * 2));
}

void gpio_set_af(GPIO *port, u8 pin, u8 af) {
  u8 reg = pin / 8;         // 0 for pins 0-7, 1 for pins 8-15
  u8 shift = (pin % 8) * 4; // 4 bits per pin
  port->AFR[reg] &= ~(0xFu << shift);
  port->AFR[reg] |= ((u32)(af) << shift);
}
