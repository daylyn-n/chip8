  .section .rodata.chip8_rom, "a", %progbits
  .global chip8_rom
chip8_rom:
  .incbin "rom.bin"
  .global chip8_rom_end
chip8_rom_end:
