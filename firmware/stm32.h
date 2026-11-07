
#ifndef STM32_H
#define STM32_H
#include <stdint.h>

typedef uint32_t u32;
typedef uint8_t u8;

typedef struct {
  volatile u32 CR;
  volatile u32 PLLCFGR;
  volatile u32 CFGR;
  volatile u32 CIR;
  volatile u32 AHB1RSTR;
  volatile u32 AHB2RSTR;
  volatile u32 AHB3RSTR;
  volatile u32 RESERVED0;
  volatile u32 APB1RSTR;
  volatile u32 APB2RSTR;
  volatile u32 RESERVED1[2];
  volatile u32 AHB1ENR;
} RCC;
#define RCC_BASE 0x40023800UL
#define RCC ((RCC *)RCC_BASE)

typedef struct {
  volatile u32 MODER;
  volatile u32 OTYPER;
  volatile u32 OSPEEDR;
  volatile u32 PUPDR;
  volatile u32 IDR;
  volatile u32 ODR;
  volatile u32 BSRR;
  volatile u32 LCKR;
  volatile u32 AFRL;
  volatile u32 AFRH;
} GPIO;
#define GPIOA_BASE 0x40020000UL
#define GPIOB_BASE 0x40020400UL

#define GPIOA ((GPIO *)GPIOA_BASE)
#define GPIOB ((GPIO *)GPIOB_BASE)
typedef struct {
  volatile u32 CR1;
  volatile u32 CR2;
  volatile u32 SR;
  volatile u32 DR;
  volatile u32 CRCPR;
  volatile u32 RXCRCR;
  volatile u32 TXCRCR;
} SPI;
#define SPI1_BASE 0x40013000
#define SPI1 ((SPI *)SPI1_BASE)

#endif
