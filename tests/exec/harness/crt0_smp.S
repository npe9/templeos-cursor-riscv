# Multi-hart entry for QEMU virt -smp N with -bios none.
# Hart 0: primary stack, resolve imports, run HolyC blob, then oracle_report.
# Harts 1..N-1: per-hart stacks, park until mailbox entry is non-zero, then jalr.
# TempleOS-shaped: one master (hart0), secondaries are Seth workers — not N REPLs.
#
# Defaults must match templeos-riscv Kconfig (CLINT_BASE / SMP_MAILBOX_BASE) and
# Kernel/Drv/RVSmp.HC. Asm cannot include RVAutoConf — keep equ in sync by hand.
.section .text.init
.global _start

.equ CLINT_BASE, 0x02000000
.equ HART_STACK_SIZE, 0x10000
.equ MAX_HARTS, 8
.equ RV_SMP_ENTRY, 0x87001E00
.equ RV_SMP_ARG,   0x87001E08
.equ RV_SMP_DONE,  0x87001E10
.equ RV_SMP_ALIVE, 0x87001E18
.equ MIE_MSIE, 8

_start:
    csrr t0, mhartid
    li   t1, MAX_HARTS
    bgeu t0, t1, .Lpark_forever

    la   sp, __stack_top
    li   t1, HART_STACK_SIZE
    mul  t1, t0, t1
    sub  sp, sp, t1
    mv   s0, sp

    li   t1, (1 << 13)
    csrs mstatus, t1

    bnez t0, .Lsecondary

    # ---- hart 0: clear job mailbox (not alive bitmask), then run blob ----
    li   t0, RV_SMP_ENTRY
    sd   zero, 0(t0)
    sd   zero, 8(t0)
    sd   zero, 16(t0)
    call resolve_imports
    li   t0, RV_SMP_ALIVE
    li   t1, 1
    amoor.d zero, t1, (t0)

    la   ra, after_user
    la   t0, _binary_blob_bin_start
    jalr zero, t0, 0

after_user:
    call oracle_report
.Lpark_forever:
    wfi
    j    .Lpark_forever

.Lsecondary:
    csrr t2, mhartid
    li   t0, RV_SMP_ALIVE
    li   t1, 1
    sll  t1, t1, t2
    amoor.d zero, t1, (t0)

    # mie.MSIE so CLINT MSIP can retire WFI (busy-poll remains the progress path)
    li   t1, MIE_MSIE
    csrs mie, t1

.Lsec_wait:
    csrr t2, mhartid
    slli t3, t2, 2
    li   t4, CLINT_BASE
    add  t4, t4, t3
    sw   zero, 0(t4)

    li   t0, RV_SMP_ENTRY
    ld   t1, 0(t0)
    beqz t1, .Lsec_wfi

    amoswap.d t1, zero, (t0)
    beqz t1, .Lsec_wfi

    li   t0, RV_SMP_ARG
    ld   a0, 0(t0)
    jalr ra, t1, 0

    li   t0, RV_SMP_DONE
    li   t1, 1
    amoswap.d zero, t1, (t0)
    j    .Lsec_wait

.Lsec_wfi:
    # Busy-poll mailbox. mie.MSIE is armed so MSIP can wake a future WFI path;
    # pure WFI here makes QEMU virt -smp progress too slow for the smoke budget.
    j    .Lsec_wait
