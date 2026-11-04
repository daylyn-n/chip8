# chip8

A CHIP-8 emulator written in Zig (0.17).

## Run

```
zig build run -- rom/ibm_logo.ch8
zig build test
```

## STM32 port (planned)

The emulator core (`src/chip8.zig`) has no file I/O, no allocator, and no platform code, so the same core can run on a microcontroller.

The plan is to port it to an STM32F446RE with:

- an OLED screen (128x64, each CHIP-8 pixel drawn as a 2x2 block)
- a 4x4 button matrix for the 16-key CHIP-8 keypad
- a buzzer for the sound timer

The desktop version will use SDL for the window, input, and sound.
