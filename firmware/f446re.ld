ENTRY(_reset);

MEMORY{
  flash(rx) : ORIGIN = 0x08000000, LENGTH = 512k
  sram(rwx) : ORIGIN = 0x20000000, LENGTH = 128k
}
/* stack pointer, recall stack grows downwards*/
_estack = ORIGIN(sram) + LENGTH(sram);


SECTIONS{

  /* we want to call the vector table in flash mem first
   * it will contain the entries for the SP and Reset Handler
   * */
  .vectors  : {KEEP(*(.vectors))}   > flash
  .text     : { *(.text*)}          > flash /* compiled code global constants*/
  .rodata   : { *(.rodata*) }       > flash /* string lits*/

  .data : {
    . = ALIGN(4);
   _sdata = .;
   *(.data SORT(.data.*))
   _edata = .;
  } > sram AT > flash
  _sidata = LOADADDR(.data);

  .bss : {
    _sbss = .;
    *(.bss SORT(.bss.*) COMMON)
    _ebss = .;
  } > sram

  . = ALIGN(8);
  _end = .;
}
