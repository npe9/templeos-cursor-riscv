/* smode_idle.S at 0x84000000, deliberately far from the 0x80200000 slot the TempleOS
 * payload occupies. OpenSBI mrets here in S-mode; the takeover then overwrites the payload
 * region underneath it, which is fine because this stub never touches that memory.
 *
 * It was 0x80400000, which is only 2 MiB above the payload -- fine for the 323 KB plat
 * image and NOT fine for the 5.4 MB REPL image, which spans past it and silently clobbered
 * the stub before OpenSBI could enter it. The symptom was the whole takeover failing with no
 * S-mode banner. run_unmatched_takeover_smoke.sh now asserts the two do not overlap rather
 * than relying on this comment. 0x84000000 is clear in QEMU; on the board it is U-Boot's
 * kernel_addr_r, which does not matter because this stub is emulation-only scaffolding. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x84000000;
  .text.init : { *(.text.init) }
  .text      : { *(.text .text.*) }
  .rodata    : { *(.rodata .rodata.*) }
  /DISCARD/ : { *(.comment) *(.note*) *(.riscv.attributes) }
}
