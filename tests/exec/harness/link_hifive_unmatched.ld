/* SiFive HiFive Unmatched / FU740: DDR @ 0x80000000 (16 GiB); U-Boot SPL +
 * OpenSBI reserve the first 2 MiB, so the plat image links at 0x80200000.
 * Contiguous layout so plat.bin stays small for U-Boot/JTAG load. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x80200000, LENGTH = 128M
}

SECTIONS {
  . = 0x80200000;

  .text.init : {
    *(.text.init)
  } > RAM

  .text : {
    *(.text .text.*)
  } > RAM

  .rodata : {
    *(.rodata .rodata.*)
  } > RAM

  .data : {
    EXCLUDE_FILE(blob_in.o) *(.data .data.*)
  } > RAM

  .bss : {
    __bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    __bss_end = .;
  } > RAM

  /* No Spike HTIF on JH7110. */
  /DISCARD/ : {
    *(.tohost)
  }

  /* HolyC AOT blob packed after BSS (prefer ELF load_image on OpenOCD). */
  .user_blob : {
    blob_in.o(.data)
  } > RAM

  . = ALIGN(16);
  . += 0x10000;
  __stack_top = .;
}
