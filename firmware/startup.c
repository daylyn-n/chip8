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
