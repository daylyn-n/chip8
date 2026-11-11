
#ifndef STM32_H
#define STM32_H
#include <stdint.h>

typedef uint32_t u32;
typedef uint8_t u8;

#define PA5 5 // onboard LED (LD2)
#define PB8 8 // I2C1 SCL (Arduino D15)
#define PB9 9 // I2C1 SDA (Arduino D14)

typedef struct {
  volatile u32 CR;
  volatile u32 PLLCFGR;
  volatile u32 CFGR;
  volatile u32 CIR;
  volatile u32 AHB1RSTR;
  volatile u32 AHB2RSTR;
  volatile u32 AHB3RSTR;
  volatile u32 RESERVED0;
  volatile u32 APB1RSTR; // bit 21 resets I2C1
  volatile u32 APB2RSTR;
  volatile u32 RESERVED1[2];
  volatile u32 AHB1ENR; // 0x30: bit 0 GPIOA, bit 1 GPIOB
  volatile u32 AHB2ENR;
  volatile u32 AHB3ENR;
  volatile u32 RESERVED2;
  volatile u32 APB1ENR; // 0x40: bit 21 I2C1
  volatile u32 APB2ENR; // 0x44: bit 12 SPI1
} RCC_Regs;
#define RCC_BASE 0x40023800UL
#define RCC ((RCC_Regs *)RCC_BASE)

typedef struct {
  volatile u32 MODER;
  volatile u32 OTYPER;
  volatile u32 OSPEEDR;
  volatile u32 PUPDR;
  volatile u32 IDR;
  volatile u32 ODR;
  volatile u32 BSRR;
  volatile u32 LCKR;
  volatile u32 AFR[2];
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
#define SPI1_BASE 0x40013000UL
#define SPI1 ((SPI *)SPI1_BASE)

typedef struct {
  volatile u32 CR1;
  volatile u32 CR2;
  volatile u32 OAR1;
  volatile u32 OAR2;
  volatile u32 DR;
  volatile u32 SR1;
  volatile u32 SR2;
  volatile u32 CCR;
  volatile u32 TRISE;
  volatile u32 FLTR;
} I2C;
#define I2C1_BASE 0x40005400UL
#define I2C1 ((I2C *)I2C1_BASE)

#endif
