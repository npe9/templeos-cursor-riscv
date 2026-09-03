/* sifive_e / FE310: XIP reset trampoline + DTIM-resident bootloader.
 *
 * .text.reset @ 0x20400000 (XIP): copy .boot into DTIM, jump to boot_main.
 * .text.boot  @ DTIM VMA: stack, .data copy, .bss clear, jump to XIP Kernel blob.
 *
 * Import patching is done on the host (patch_fe310_xip_imports.py) — XIP is ROM. */
.section .text.reset, "ax", @progbits
.global _start
.align 2
_start:
    csrr t0, mhartid
    bnez t0, 3f

    /* Copy bootloader .boot from flash LMA → DTIM VMA (8-byte words). */
    la   a0, __boot_start
    la   a1, __boot_load
    la   a2, __boot_end
1:
    bgeu a0, a2, 2f
    ld   t0, 0(a1)
    sd   t0, 0(a0)
    addi a0, a0, 8
    addi a1, a1, 8
    j    1b
2:
    /* Run bootloader from DTIM. */
    la   t0, boot_main
    jr   t0
3:
    wfi
    j    3b

.section .text.boot, "ax", @progbits
.global boot_main
.align 2
boot_main:
    li   t0, (1 << 13)          /* mstatus.FS */
    csrs mstatus, t0
    la   sp, __stack_top
    mv   s0, sp

    /* Prove we are executing from DTIM (bootloader-in-RAM). */
    call fe310_boot_banner

    /* Copy .data flash LMA → DTIM VMA. */
    la   a0, __data_start
    la   a1, __data_load
    la   a2, __data_end
4:
    bgeu a0, a2, 5f
    ld   t0, 0(a1)
    sd   t0, 0(a0)
    addi a0, a0, 8
    addi a1, a1, 8
    j    4b
5:
    /* Clear .bss in DTIM. */
    la   a0, __bss_start
    la   a1, __bss_end
6:
    bgeu a0, a1, 7f
    sd   zero, 0(a0)
    addi a0, a0, 8
    j    6b
7:
    /* Jump to HolyC Kernel blob in XIP (imports host-prepatched). */
    la   ra, after_user
    la   t0, _binary_blob_bin_start
    jalr zero, t0, 0

after_user:
    /* oracle_report is in XIP — JAL from DTIM cannot reach; use absolute. */
    la   t0, oracle_report
    jalr ra, t0, 0
8:
    wfi
    j    8b
