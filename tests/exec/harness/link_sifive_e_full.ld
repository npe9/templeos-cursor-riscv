/* sifive_e / FE310 fuller tiny-Kernel: product XIP layout.
 *
 *   XIP/QSPI ROM @ 0x20400000 — reset trampoline + Kernel (oracle + HolyC blob)
 *   DTIM RAM     @ 0x80000000 — bootloader (.boot), .data, .bss, stack only
 *
 * Reset → tiny FLASH trampoline copies .boot LMA→VMA, then jumps into DTIM
 * bootloader. Bootloader copies .data, clears .bss, jumps to XIP Kernel blob.
 * Import slots are host-prepatched into the XIP image (ROM cannot be patched
 * at runtime) — see tests/scripts/patch_fe310_xip_imports.py.
 *
 * Not full Kernel_RV / REPL; DTIM is 16 KiB with no external DRAM. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  FLASH (rx) : ORIGIN = 0x20400000, LENGTH = 16M
  RAM (rwx)  : ORIGIN = 0x80000000, LENGTH = 16K
}

SECTIONS {
  /* Reset vector: QEMU sifive_e jumps here. Stays in XIP. */
  .text.reset : {
    KEEP(*(.text.reset))
  } > FLASH

  /* Bootloader: stored in flash (LMA), runs from DTIM (VMA). */
  .boot : {
    PROVIDE(__boot_start = .);
    *(.text.boot)
    . = ALIGN(8);
    PROVIDE(__boot_end = .);
  } > RAM AT> FLASH
  PROVIDE(__boot_load = LOADADDR(.boot));

  /* Kernel helpers (oracle) — execute in place from QSPI/XIP. */
  .text : {
    *(.text .text.*)
  } > FLASH

  .rodata : {
    *(.rodata .rodata.*)
  } > FLASH

  /* HolyC Kernel AOT blob — XIP (host-prepatched import slots). */
  .user_blob : {
    PROVIDE(__blob_start = .);
    blob_in.o(.data)
    PROVIDE(__blob_end = .);
  } > FLASH

  /* Writable Kernel data: LMA in flash, VMA in DTIM; bootloader copies. */
  .data : {
    PROVIDE(__data_start = .);
    EXCLUDE_FILE(blob_in.o) *(.data .data.*)
    *(.sdata .sdata.*)
    . = ALIGN(8);
    PROVIDE(__data_end = .);
  } > RAM AT> FLASH
  PROVIDE(__data_load = LOADADDR(.data));

  .bss : {
    PROVIDE(__bss_start = .);
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    . = ALIGN(8);
    PROVIDE(__bss_end = .);
  } > RAM

  /DISCARD/ : {
    *(.tohost)
  }

  . = ALIGN(16);
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
