/* RV32 P0 exec image for qemu-system-riscv32 -M virt: RAM @ 0x80000000, blob @ 0x80800000. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

SECTIONS {
  . = 0x80000000;
  .text.init : { *(.text.init) } > RAM
  .text : { *(.text .text.*) } > RAM
  .rodata : { *(.rodata .rodata.*) } > RAM
  .data : { EXCLUDE_FILE(blob_in.o) *(.data .data.*) } > RAM
  .bss : { *(.bss .bss.*) *(COMMON) } > RAM

  /* HolyC AOT machine code from objcopy -I binary (lives in .data of blob_in.o) */
  .user_blob 0x80800000 : { blob_in.o(.data) } > RAM

  . = ALIGN(16);
  . += 0x100000;
  __stack_top = .;
}
