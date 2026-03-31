/* Same as kernel.ld but HolyC guest is blob_selfhost_in.o. */
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
    EXCLUDE_FILE(blob_selfhost_in.o compiler_blob_in.o) *(.data .data.*)
  } > RAM

  .bss : {
    __bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(16);
    trap_stack = .;
    . += 4096;
    trap_stack_top = .;
    __bss_end = .;
  } > RAM

  .user_blob 0x80100000 : {
    blob_selfhost_in.o(.data)
  } > RAM

  .compiler_blob 0x80200000 : {
    compiler_blob_in.o(.data)
  } > RAM

  .tos_api 0x80300000 : {
    kernel.o(.tos_api)
  } > RAM

  . = ALIGN(16);
  . += 0x100000;
  __stack_top = .;

  PROVIDE(compiler_blob_vma = 0x80200000);
  PROVIDE(tos_api_vma = 0x80300000);
}
