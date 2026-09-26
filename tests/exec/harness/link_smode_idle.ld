/* smode_idle.S: 0x80400000, deliberately NOT the 0x80200000 slot the TempleOS payload
 * is loaded into. OpenSBI mrets here in S-mode; the takeover then overwrites 0x80200000
 * underneath it, which is fine because this stub never touches that memory. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x80400000;
  .text.init : { *(.text.init) }
  .text      : { *(.text .text.*) }
  .rodata    : { *(.rodata .rodata.*) }
  /DISCARD/ : { *(.comment) *(.note*) *(.riscv.attributes) }
}
