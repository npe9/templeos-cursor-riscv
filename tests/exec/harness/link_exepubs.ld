OUTPUT_ARCH(riscv)
ENTRY(_start)

/* ExePutS smoke: ~2MB HolyC blob needs room for stack ABOVE the blob and heap at 0x82000000. */
MEMORY {
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

SECTIONS {
  . = 0x80000000;

  .text.init : {
    *(.text.init)
  } > RAM

  .text : {
    *(.text .text.*)
  } > RAM

  .rodata : {
    *(.rodata .rodata.*)
  } > RAM

  /* Exclude blob_in.o + compiler_full.o — they have fixed VMAs below.
   * Patterns need a leading * so path-prefixed inputs (build/exec/…) match. */
  .data : {
    EXCLUDE_FILE(*blob_in.o *compiler_full.o) *(.data .data.*)
  } > RAM

  .bss : {
    __bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    __bss_end = .;
  } > RAM

  /* HolyC AOT blob — executable (code+data). Keep below heap arena 0x82000000. */
  .user_blob 0x80800000 : {
    *blob_in.o(.data)
  } > RAM

  /* Optional host-packed Compiler.BIN (TOSB) — last-resort bootstrap *bytes*.
   * Default phase3 smoke ships seed on RedSea virtio img (omit compiler_full.o).
   * Live Cmp is heap Load of A:/Compiler/Compiler.BIN (G9 relocatable seed).
   * PHASE3_LINK_COMPILER_BIN=1 links compiler_full.o into this section. */
  .compiler_bin 0x81000000 : {
    KEEP(*compiler_full.o(.data .data.*))
  } > RAM

  . = 0x87F00000;
  __stack_top = .;
}
