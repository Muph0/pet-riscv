/* link.x */

MEMORY
{
  ROM   (rx) : ORIGIN = 0x00004000, LENGTH = 8K
  RAM  (rwx) : ORIGIN = 0x00008000, LENGTH = 8K
}

ENTRY(_start)

EXTERN(_start)

SECTIONS
{
  /* Put the entry point at the very beginning of the bin file */
  .text : {
    *(.text._start)
    *(.text .text.*)
    *(.rodata .rodata.*)

    . = ALIGN(4);
    _etext = .;
  } > ROM

  /* For this simple hello program, we map DATA and BSS directly into RAM,
     but because we want to produce a flat binary uploaded to ROM, any .data
     would need a copy section. For simplicity and to match the pure asm approach,
     we compile everything to ROM/RODATA and avoid initialized .data (.data size=0).
     Or we can place them into RAM but we must initialize them in _start - let's skip for simple echo!
     Instead we'll just put .data into ROM for safety or enforce no .data. */

  .data : {
    . = ALIGN(4);
    sdata = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    . = ALIGN(4);
    edata = .;
  } > ROM

  .bss (NOLOAD) : {
    . = ALIGN(4);
    sbss = .;
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    . = ALIGN(4);
    ebss = .;
  } > RAM

  /DISCARD/ : {
    *(.eh_frame)
  }
}