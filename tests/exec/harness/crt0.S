# Call HolyC blob as I64 (*)(void); then print result for oracle harness.
# Multi-hart boards (icicle, …): only hart 0 runs the blob; others park in WFI
# so UART smoke lines are not interleaved across harts.
.section .text.init
.global _start

_start:
    csrr t0, mhartid
    bnez t0, halt
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
