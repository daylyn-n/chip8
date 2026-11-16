#ifndef KEYPAD_H
#define KEYPAD_H

#include "stm32.h"

// 4x4 matrix keypad.
// Rows: open-drain outputs, idle high. Pull one low to scan it.
//   R1 = PB10 (D6), R2 = PA8 (D7), R3 = PA9 (D8), R4 = PC7 (D9)
// Columns: inputs with pull-up. 0 = a key in the active row is down.
//   C1 = PA0 (A0), C2 = PA1 (A1), C3 = PA4 (A2), C4 = PB0 (A3)

#define KEYPAD_ROWS 4
#define KEYPAD_COLS 4

void keypad_init(void);

// Scans all 16 keys. Bit (row * 4 + col) is 1 while that key is down.
// Bit 0 = row 1, column 1 (label "1"). Bit 15 = row 4, column 4 (label "D").
u32 keypad_scan(void);

// Wiring probe. Wires 0-7 are the pins A0 A1 A2 A3 D6 D7 D8 D9,
// in this fixed order, so the probe does not depend on s_rows/s_cols. keypad_probe() returns bit i set
// when wire i connects to another wire (a key joins the two wires).
// keypad_probe_init() replaces keypad_init(). Do not use both.
void keypad_probe_init(void);
u32 keypad_probe(void);

#endif
