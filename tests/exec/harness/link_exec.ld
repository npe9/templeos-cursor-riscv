OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64M
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

  .data : {
    EXCLUDE_FILE(blob_in.o) *(.data .data.*)
  } > RAM

  .bss : {
    __bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    __bss_end = .;
  } > RAM

  /* HolyC AOT machine code from objcopy -I binary (lives in .data of blob_in.o) */
  .user_blob 0x80800000 : {
    blob_in.o(.data)
  } > RAM

  . = ALIGN(16);
  . += 0x100000;
  __stack_top = .;
}
