/* Milk-V Mars / JH7110: DDR @ 0x40000000; OpenSBI/U-Boot reserve ~2 MiB.
 * Plat image links at 0x40200000 (CONFIG_ENTRY_POINT). Contiguous layout so
 * plat.bin is small enough for U-Boot tftp/mmc load (no 8 MiB hole).
 * Same map as VisionFive 2 — separate linker script (do not share VF2 files).
 * No HTIF. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x40200000, LENGTH = 128M
}

SECTIONS {
  . = 0x40200000;

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
