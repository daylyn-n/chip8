#ifndef KEYPAD_H
#define KEYPAD_H

#include "stm32.h"

// 4x4 matrix keypad.
// Rows: open-drain outputs, idle high. Pull one low to scan it.
//   R1 = PA0 (A0), R2 = PA1 (A1), R3 = PA4 (A2), R4 = PB0 (A3)
// Columns: inputs with pull-up. 0 = a key in the active row is down.
//   C1 = PB10 (D6), C2 = PA8 (D7), C3 = PA9 (D8), C4 = PC7 (D9)

#define KEYPAD_ROWS 4
#define KEYPAD_COLS 4

void keypad_init(void);

#endif
