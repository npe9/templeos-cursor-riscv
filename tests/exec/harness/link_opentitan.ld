/* OpenTitan / Ibex: flash boot @ 0x20000400, 128 KiB SRAM @ 0x10000000.
 * QEMU -M opentitan jumps to flash; -bios none is rejected as a filename. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  FLASH (rx) : ORIGIN = 0x20000400, LENGTH = 512K
  RAM (rwx)  : ORIGIN = 0x10000000, LENGTH = 128K
}

SECTIONS {
  .text : {
    *(.text.init)
    *(.text .text.*)
  } > FLASH

  .rodata : {
    *(.rodata .rodata.*)
  } > FLASH

  .data : {
    *(.data .data.*)
  } > RAM

  .bss : {
    *(.bss .bss.*)
    *(COMMON)
  } > RAM

  . = ALIGN(16);
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
