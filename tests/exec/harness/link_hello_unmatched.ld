/* hello_unmatched.S — flat payload for JTAG load into FU740 DDR.
 *
 * 0x80200000 is the board's own S-mode payload slot, not a guess:
 *   - U-Boot board/sifive/unmatched/Kconfig:  TEXT_BASE default 0x80200000 if RISCV_SMODE
 *   - U-Boot sifive_unmatched_defconfig:      CONFIG_SYS_LOAD_ADDR=0x80200000 ($loadaddr)
 *   - arch/riscv/dts/binman.dtsi:             opensbi load 0x80000000, uboot load TEXT_BASE
 *     => firmware is bounded to the 2 MiB below 0x80200000, or the stock FIT would not boot
 *   - U-Boot's own Unmatched boot log:        "OF: fdt: Ignoring memory range 0x80000000 - 0x80200000"
 *                                            "node 0: [mem 0x0000000080200000-...]"
 * The copy of U-Boot proper that was loaded here is dead by the time you reach the
 * prompt: U-Boot relocates itself, and arch/riscv/cpu/fu740/dram.c caps ram_top at
 * SZ_4G, so live U-Boot sits just under 0x1_0000_0000 — about 2 GiB away.
 *
 * The payload is position-independent anyway (lla / PC-relative everywhere), so it
 * also runs from 0x84000000 if you would rather stay further from firmware.
 * BSS is inside the image so a flat `load_image` of the .bin needs no zeroing.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS {
  . = 0x80200000;

  .text.init : { *(.text.init) }
  .text      : { *(.text .text.*) }
  .rodata    : { *(.rodata .rodata.*) }
  .data      : { *(.data .data.*) }
  /* NOLOAD is deliberately NOT used: objcopy -O binary must emit these bytes so the
   * flat image carries its own stack space and nothing has to clear BSS first. */
  .bss       : { *(.bss .bss.*) *(COMMON) }

  /DISCARD/ : { *(.comment) *(.note*) *(.riscv.attributes) }
}
