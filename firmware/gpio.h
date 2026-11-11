#ifndef GPIO_H
#define GPIO_H

#include "stm32.h"

enum { GPIO_INPUT = 0, GPIO_OUTPUT = 1, GPIO_AF = 2, GPIO_ANALOG = 3 };
enum { GPIO_PUSH_PULL = 0, GPIO_OPEN_DRAIN = 1 };
enum { GPIO_NO_PULL = 0, GPIO_PULL_UP = 1, GPIO_PULL_DOWN = 2 };
enum { GPIO_SPEED_LOW = 0, GPIO_SPEED_MEDIUM = 1, GPIO_SPEED_FAST = 2, GPIO_SPEED_HIGH = 3 };

void gpio_set_mode(GPIO *port, u8 pin, u32 mode);
void gpio_set_af(GPIO *port, u8 pin, u8 af);
void gpio_set_speed(GPIO *port, u8 pin, u32 speed);
void gpio_set_otype(GPIO *port, u8 pin, u32 otype);
void gpio_set_pull(GPIO *port, u8 pin, u32 pull);
void gpio_write(GPIO *port, u8 pin, u8 value);
#endif
