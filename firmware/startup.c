#include "stm32.h"
int main(void);
// startup: runs on reset, before main
extern void _estack(void); // defined in f446re.ld

// Section bounds, defined in f446re.ld. Only their addresses matter.
// The linker script aligns all of them to 4 bytes.
extern u32 _sdata, _edata, _sidata; // .data: RAM start, RAM end, flash copy
extern u32 _sbss, _ebss;            // .bss: RAM start, RAM end

__attribute__((noreturn)) void _reset(void) {
  // .data: globals with a start value, for example `int x = 5;`.
  // The start values are stored in flash. Copy them into RAM.
  u32 *src = &_sidata;
  for (u32 *dst = &_sdata; dst < &_edata;) {
    *dst++ = *src++;
  }

  // .bss: globals with no start value, or a start value of 0.
  // C requires them to be 0. RAM holds random values at power-on.
  for (u32 *dst = &_sbss; dst < &_ebss;) {
    *dst++ = 0;
  }

  main();
  for (;;)
    (void)0;
}

/* 16 core entries + 91 STM32F446 interrupts */
__attribute__((section(".vectors"))) void (*const tab[16 + 91])(void) = {
    _estack, _reset};
