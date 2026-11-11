#ifndef GPIO_H
#define GPIO_H

#include "stm32.h"

enum { GPIO_INPUT = 0, GPIO_OUTPUT = 1, GPIO_AF = 2, GPIO_ANALOG = 3 };

void gpio_set_mode(GPIO *port, u8 pin, u32 mode);
void gpio_set_af(GPIO *port, u8 pin, u8 af);
#endif
