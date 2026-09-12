# Call HolyC blob as I64 (*)(void); then print result for oracle harness.
# Multi-hart boards (icicle, …): only hart 0 runs the blob; others park in WFI
# so UART smoke lines are not interleaved across harts.
.section .text.init
.global _start

_start:
    csrr t0, mhartid
    bnez t0, halt
    # Install a trap vector FIRST. Without one, mtvec is 0, so any fault jumps to
    # address 0, faults again fetching there, and loops forever — a silent hang with
    # no output, indistinguishable from an infinite loop.
    # This is a floor, not a policy: guests that want their own handler install it
    # later and win (bootstrap/holy_rt.h RVTrapInit / RVPreemptInit / RVTrapDiag /
    # RVPreemptReal all csrw mtvec). What this covers is the window before that —
    # which is where the faults nobody could see were happening.
    la t0, trap_entry         # 4-aligned => mtvec MODE=0 (direct)
    csrw mtvec, t0
    li t0, (1 << 13)          # mstatus.FS = Initial: F64 code traps otherwise
    csrs mstatus, t0
    la sp, __stack_top
    mv s0, sp
    call resolve_imports       # fill the blob's runtime import slots (bootstrap/holy_rt.h)

    la ra, after_user
    la t0, _binary_blob_bin_start
    jalr zero, t0, 0

after_user:
    call oracle_report
halt:
    wfi
    j halt

# Fatal-fault handler: report mcause/mepc/mtval and stop. Runs on its own stack
# because the faulting sp may be exactly what is broken. Does not return — a trap
# here means the case is dead, and halting beats spinning silently.
    .align 2
trap_entry:
    la sp, __trap_stack_top
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    call trap_report
trap_halt:
    wfi
    j trap_halt

    .section .bss
    .align 4
trap_stack:
    .space 512
__trap_stack_top:

# QEMU spike HTIF console symbols (st_size must be 8). Linked @ 0x807FF000.
.section .tohost, "aw", @progbits
.align 6
.globl tohost
tohost:
    .dword 0
    .size tohost, 8
.align 6
.globl fromhost
fromhost:
    .dword 0
    .size fromhost, 8
