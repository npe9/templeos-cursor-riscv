/* HolyC REPL (Kernel_RV + Compiler_RV ExePutS loop) for the HiFive Unmatched.
 *
 * link_exepubs.ld with ONE change: the image starts at 0x80200000 instead of 0x80000000,
 * because on this board the first 2 MiB of DDR belongs to firmware — OpenSBI is resident
 * at 0x80000000 (measured: base 0x80000000, size 337 KB, and its PMP fences
 * 0x80000000-0x8005ffff off from S/U). 0x80200000 is the board's own S-mode payload slot;
 * see docs/HIFIVE_UNMATCHED.md §2 for the evidence.
 *
 * The fixed VMAs below are deliberately unchanged from link_exepubs.ld. They are absolute
 * and the image would use them wherever it were loaded, so they are a property of the
 * Kconfig memory map, not of the link address:
 *   0x80800000  the AOT blob        0x81000000  optional packed TOSB
 *   0x87F00000  stack top           (heap/CHeapCtrl come from CONFIG_* at runtime)
 * That leaves 6 MiB for text+rodata+data+bss between 0x80200000 and the blob, versus 8 MiB
 * in the virt build. The REPL image is well inside that.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x80200000, LENGTH = 126M
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

  /* Exclude blob_in.o + compiler_full.o + kernel_embed.o — fixed VMAs below.
   * Patterns need a leading * so path-prefixed inputs (build/exec/…) match. */
  .data : {
    EXCLUDE_FILE(*blob_in.o *compiler_full.o *kernel_embed.o) *(.data .data.*)
  } > RAM

  .bss : {
    __bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    __bss_end = .;
  } > RAM

  .user_blob 0x80800000 : {
    *blob_in.o(.data)
  } > RAM

  .compiler_bin 0x81000000 : {
    KEEP(*compiler_full.o(.data .data.*))
    KEEP(*kernel_embed.o(.data .data.*))
  } > RAM

  . = 0x87F00000;
  __stack_top = .;
}
