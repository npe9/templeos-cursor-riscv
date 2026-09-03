OUTPUT_ARCH(riscv)
/* HolyC asm `_start` is at the start of the AOT blob — no crt0.S.
 * Mark blob as executable (QEMU/PMP): objcopy renames binary payload to .text. */
ENTRY(_binary_blob_bin_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

SECTIONS {
  . = 0x80000000;

  .user_blob 0x80000000 : {
    KEEP(*(.text))
    KEEP(*(.data))
    KEEP(*(.rodata*))
  } > RAM

  . = ALIGN(16);
  . += 0x100000;
  __stack_top = .;

  /DISCARD/ : {
    *(.comment)
    *(.note*)
  }
}
