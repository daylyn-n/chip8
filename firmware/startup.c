#include "gpio.h"
#include "stm32.h"
int main(void);
static void delay(volatile u32 count);
// startup: runs on reset, before main
extern void _estack(void); // defined in f446re.ld

__attribute__((noreturn)) void _reset(void) {
  main();
  for (;;)
    (void)0;
}

/* 16 core entries + 91 STM32F446 interrupts */
__attribute__((section(".vectors"))) void (*const tab[16 + 91])(void) = {
    _estack, _reset};

int main(void) {
  // gpioa clock on
  RCC->AHB1ENR |= (1u << 0);

  gpio_set_mode(GPIOA, PA5, GPIO_OUTPUT);

  while (1) {
    GPIOA->ODR ^= (1u << PA5);
    delay(500000);
  }
}

void delay(volatile u32 count) {
  while (count--)
    ;
}
