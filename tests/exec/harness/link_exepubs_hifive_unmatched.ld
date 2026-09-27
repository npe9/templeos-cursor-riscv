/* HolyC REPL (Kernel_RV + Compiler_RV ExePutS loop) for the HiFive Unmatched.
 *
 * link_exepubs.ld with ONE change: the image starts at 0x80200000 instead of 0x80000000,
 * because on this board the first 2 MiB of DDR belongs to firmware — OpenSBI is resident
 * at 0x80000000 (measured: base 0x80000000, size 337 KB, and its PMP fences
 * 0x80000000-0x8005ffff off from S/U). 0x80200000 is the board's own S-mode payload slot;
 * see docs/HIFIVE_UNMATCHED.md §2 for the evidence.
 *
 * The blob VMA is moved DOWN, and that is about transfer time, not layout. link_exepubs.ld
 * puts the AOT blob at 0x80800000; with text starting at 0x80200000 that leaves a ~6 MiB
 * hole, and `objcopy -O binary` emits the hole as zeros. Measured on the first build: a
 * 10,732,328-byte flat image of which 7,241,518 bytes were zero — 67% padding. On this board
 * the image has to cross a 115200 serial link or a tftp hop, so those zeros are minutes.
 *
 * Safe to move because nothing refers to the blob by absolute address: crt0.S reaches it
 * through `la` (auipc-relative), the import trailer's slots are blob-relative offsets, and a
 * scan of the built image for 8-byte words pointing into 0x80800000..0x80a00000 found ZERO.
 * 0x80300000 leaves 1 MiB for text+rodata+data+bss; the plat image's whole C half is ~20 KiB.
 *
 * Still absolute, and deliberately unchanged, because these are properties of the Kconfig
 * memory map rather than of the link address:
 *   0x81000000  optional packed TOSB
 *   0x87F00000  stack top       (heap / CHeapCtrl come from CONFIG_* at runtime)
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

  .user_blob 0x80300000 : {
    *blob_in.o(.data)
  } > RAM

  .compiler_bin 0x81000000 : {
    KEEP(*compiler_full.o(.data .data.*))
    KEEP(*kernel_embed.o(.data .data.*))
  } > RAM

  . = 0x87F00000;
  __stack_top = .;
}
