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

  /* Host-packed full Compiler.BIN (TOSB) for LoadBuf — see RVPhase3LoadFullCompiler.
   * Must EXCLUDE_FILE above or .data steals this section (was at 0x80003340). */
  .compiler_bin 0x81000000 : {
    KEEP(*compiler_full.o(.data .data.*))
  } > RAM

  . = 0x87F00000;
  __stack_top = .;
}
