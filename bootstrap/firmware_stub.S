/* TempleOS/RISC-V firmware head — QEMU virt pflash @ 0x20000000.
 *
 * Reset lands here when the image is mapped as CFI flash (pflash @ FLASH_BASE).
 * For qemu -bios, use the RAM-linked payload (templeos-bios.elf) instead.
 * The stub copies the embedded RAM payload (REPL or kernel plat ELF flat
 * image) to RAM_BASE and jumps to it.  Payload _start clears BSS and runs main.
 *
 * Link with firmware.ld; payload is objcopy'd from a normal 0x80000000 ELF.
 */

.section .text.init
.global _start

#ifndef RAM_BASE
#define RAM_BASE 0x80000000
#endif

_start:
    csrw mie, zero
    csrw mip, zero

    csrr t0, mhartid
    bnez t0, _halt

    la   t0, _fw_payload_start
    la   t1, _fw_payload_end
    li   t2, RAM_BASE
1:
    bge  t0, t1, 2f
    ld   t3, 0(t0)
    sd   t3, 0(t2)
    addi t0, t0, 8
    addi t2, t2, 8
    j    1b
2:
    li   t0, RAM_BASE
    jr   t0

_halt:
    wfi
    j _halt
