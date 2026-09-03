/* sifive_e / FE310: XIP flash + 16 KiB DTIM.
 * QEMU reset jumps to 0x20400000 (riscv.sifive.e.xip); DTIM is 0x80000000..0x80003fff.
 * Put code + HolyC blob in flash; keep .data/.bss/stack in DTIM. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  FLASH (rx) : ORIGIN = 0x20400000, LENGTH = 16M
  RAM (rwx)  : ORIGIN = 0x80000000, LENGTH = 16K
}

SECTIONS {
  .text.init : {
    *(.text.init)
  } > FLASH

  .text : {
    *(.text .text.*)
  } > FLASH

  .rodata : {
    *(.rodata .rodata.*)
  } > FLASH

  /* HolyC AOT blob (objcopy -I binary → .data of blob_in.o) lives in XIP. */
  .user_blob : {
    blob_in.o(.data)
  } > FLASH

  .data : {
    EXCLUDE_FILE(blob_in.o) *(.data .data.*)
    *(.sdata .sdata.*)
  } > RAM

  .bss : {
    __bss_start = .;
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    __bss_end = .;
  } > RAM

  /* crt0.S defines HTIF .tohost — discard on boards without Spike HTIF. */
  /DISCARD/ : {
    *(.tohost)
  }

  . = ALIGN(16);
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
