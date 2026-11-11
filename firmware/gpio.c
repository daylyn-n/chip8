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

// How fast the pin edges switch. SPI clock pins need a fast setting.
void gpio_set_speed(GPIO *port, u8 pin, u32 speed) {
  port->OSPEEDR &= ~(3u << (pin * 2));
  port->OSPEEDR |= (speed << (pin * 2));
}

// Push-pull drives the pin high and low. Open-drain only pulls it low,
// and a resistor pulls it high. I2C needs open-drain.
void gpio_set_otype(GPIO *port, u8 pin, u32 otype) {
  port->OTYPER &= ~(1u << pin);
  port->OTYPER |= (otype << pin);
}

void gpio_set_pull(GPIO *port, u8 pin, u32 pull) {
  port->PUPDR &= ~(3u << (pin * 2));
  port->PUPDR |= (pull << (pin * 2));
}

// BSRR: writing bit n sets pin n, writing bit n+16 clears it.
// One write, so no read-modify-write is needed.
void gpio_write(GPIO *port, u8 pin, u8 value) {
  port->BSRR = value ? (1u << pin) : (1u << (pin + 16));
}
