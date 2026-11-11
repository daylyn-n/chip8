# SSD1306 / SH1106 OLED Cheat Sheet

128x64 OLED over I2C, address `0x3C`. Send commands after control byte `0x00`.

## 1. Commands

**Both** = SSD1306 and SH1106. **1306** = SSD1306 only. **1106** = SH1106 only.
"Reset" = the value after power-on.

### Display on/off and look

| Command | Chip | Meaning | Reset |
|---|---|---|---|
| `0xAE` | Both | Display off (sleep). RAM keeps its content. | yes |
| `0xAF` | Both | Display on. | |
| `0xA4` | Both | Pixels follow RAM (normal). | yes |
| `0xA5` | Both | Every pixel on. Ignores RAM. Good for tests. | |
| `0xA6` | Both | Normal: bit 1 = pixel on. | yes |
| `0xA7` | Both | Inverted: bit 0 = pixel on. | |
| `0x81, n` | Both | Contrast (brightness), `n` = `0x00` to `0xFF`. | `0x7F` (1306), `0x80` (1106) |

### Power

| Command | Chip | Meaning | Reset |
|---|---|---|---|
| `0x8D, 0x14` | 1306 | Charge pump **on**. Needed with a 3.3 V module, or the screen stays black. Send before `0xAF`. | off |
| `0x8D, 0x10` | 1306 | Charge pump off. | |
| `0xAD, 0x8B` | 1106 | DC-DC converter on. | on |
| `0xAD, 0x8A` | 1106 | DC-DC converter off. | |
| `0x30`-`0x33` | 1106 | Pump output voltage: 6.4 / 7.4 / 8.0 / 9.0 V. | `0x32` |

### Addressing (where pixel data goes)

| Command | Chip | Meaning | Reset |
|---|---|---|---|
| `0xB0` + page | Both | Page 0-7 (`0xB0`-`0xB7`). | page 0 |
| `0x00` + (col & 0x0F) | Both | Column, low 4 bits (`0x00`-`0x0F`). | 0 |
| `0x10` + (col >> 4) | Both | Column, high 4 bits (`0x10`-`0x1F`). | 0 |
| `0x20, mode` | 1306 | Addressing mode: `0x00` horizontal, `0x01` vertical, `0x02` page. | `0x02` |
| `0x21, start, end` | 1306 | Column range (horizontal/vertical mode only). | 0, 127 |
| `0x22, start, end` | 1306 | Page range (horizontal/vertical mode only). | 0, 7 |

**Page mode** (both chips): set page and column, send up to 128 bytes, repeat for each page.
**Horizontal mode** (SSD1306 only): set the ranges once, then send all 1024 bytes in one stream.

### Orientation and position

| Command | Chip | Meaning | Reset |
|---|---|---|---|
| `0xA0` | Both | Columns: column 0 = left edge. | yes |
| `0xA1` | Both | Columns mirrored: column 0 = right edge. | |
| `0xC0` | Both | Rows: normal scan direction. | yes |
| `0xC8` | Both | Rows mirrored: vertical flip. | |
| `0x40` + line | Both | Start line 0-63 (`0x40`-`0x7F`). Scrolls the image vertically. | `0x40` |
| `0xD3, n` | Both | Display offset, `n` = 0-63. Also shifts the image vertically. | 0 |

`0xA1` + `0xC8` = rotate 180 degrees from `0xA0` + `0xC0`.
If the image is upside down, swap between the two pairs.

### Panel hardware (set once, copy from a working example)

| Command | Chip | Meaning | Reset |
|---|---|---|---|
| `0xA8, n` | Both | Multiplex ratio: `n + 1` rows. `0x3F` = 64 rows. | `0x3F` |
| `0xDA, n` | Both | COM pin layout. `0x12` for 128x64, `0x02` for 128x32. | `0x12` |
| `0xD5, n` | Both | Clock: low 4 bits = divider - 1, high 4 bits = oscillator speed. | `0x80` (1306), `0x50` (1106) |
| `0xD9, n` | Both | Pre-charge: low 4 bits = phase 1, high 4 bits = phase 2. `0xF1` with the internal charge pump. | `0x22` |
| `0xDB, n` | Both | VCOMH (pixel drive level). `0x20` or `0x40` are common. | `0x20` (1306), `0x35` (1106) |
| `0xE3` | Both | No operation (NOP). | |

### Scrolling (SSD1306 only, hardware scroll)

| Command | Meaning |
|---|---|
| `0x26` / `0x27` + 6 bytes | Set up a horizontal scroll, right / left. |
| `0x29` / `0x2A` + 5 bytes | Set up a vertical and horizontal scroll. |
| `0xA3, top, rows` | Vertical scroll area. |
| `0x2F` | Start the scroll. |
| `0x2E` | Stop the scroll. Send this before you write RAM. |

Not needed for CHIP-8.

---

## 2. Init sequence (works on both chips)

This is `init_cmds` in `firmware/display.c`. Send it after control byte `0x00`.

```
0xAE          display off
0xD5, 0x80    clock
0xA8, 0x3F    64 rows
0xD3, 0x00    offset 0
0x40          start line 0
0x8D, 0x14    charge pump on (SSD1306; the SH1106 ignores it)
0xA1          columns mirrored  } upright with the pins at the top
0xC8          rows mirrored     } (use 0xA0 + 0xC0 if upside down)
0xDA, 0x12    COM pins for 128x64
0xD9, 0xF1    pre-charge
0xDB, 0x40    VCOMH
0x81, 0x7F    contrast
0xA4          pixels follow RAM
0xA6          normal colors
0xAF          display on
```

---

## 3. Wiring

Keep the Nucleo USB unplugged while you change wires.

### STM32 (Nucleo-F446RE) to OLED

| OLED pin | Nucleo pin | STM32 pin | Purpose |
|---|---|---|---|
| VCC | 3V3 | - | Power (3.3 V, not 5 V) |
| GND | GND | - | Ground |
| SCL | D15 | PB8 | I2C1 clock (AF4, open-drain) |
| SDA | D14 | PB9 | I2C1 data (AF4, open-drain) |

- The OLED module has its own pull-up resistors on SCL and SDA.
- Read the pin labels on the module. Some modules use the order GND, VCC, SCL, SDA.
- On a breadboard, put **each OLED pin in its own row**. If two pins share a row,
  they are shorted. VCC and GND in one row shorts the 3.3 V supply: the regulator
  gets hot, and the ST-Link cannot connect (`Failed to enter SWD mode`).

```
row 5 [VCC]  o o o o   -> 3V3
row 6 [GND]  o o o o   -> GND
row 7 [SCL]  o o o o   -> D15
row 8 [SDA]  o o o o   -> D14
```

### Logic analyzer

Plug the analyzer wires into free holes in the same rows as the OLED pins.

| Analyzer | Breadboard row | Signal |
|---|---|---|
| CH0 | SCL row | I2C clock |
| CH1 | SDA row | I2C data |
| GND | GND row | Ground (always connect it) |

- **Do not connect the analyzer 3.3V or 5V pin.** The analyzer gets power from its own USB cable.
- Connect GND first. Without a shared ground, the analyzer reads noise.

```
row 5 [VCC]  o o o o   -> 3V3
row 6 [GND]  o o o o   -> GND   + analyzer GND
row 7 [SCL]  o o o o   -> D15   + analyzer CH0
row 8 [SDA]  o o o o   -> D14   + analyzer CH1
```

### PulseView settings

| Setting | Value |
|---|---|
| Device | fx2lafw (shows as "Saleae Logic") |
| Sample rate | 24 MHz (12 MHz if USB errors) |
| Samples | 1 M |
| Decoder | I2C: SCL = D0, SDA = D1 |
| Trigger | Falling edge on D1 (SDA) |

To capture the start of the program: click **Run** first, then press the black
**reset button (B2)** on the Nucleo.

A good transfer:

```
Start | Address write: 3C | W | ACK | 00 | ACK | ... | ACK | Stop
```

NACK after the address = the screen does not answer. Check SCL/SDA and the address.
