# Call HolyC blob as I64 (*)(void); then print result for oracle harness.
.section .text.init
.global _start

_start:
    li t0, (1 << 13)          # mstatus.FS = Initial: F64 code traps otherwise
    csrs mstatus, t0
    la sp, __stack_top
    mv s0, sp

    la ra, after_user
    la t0, _binary_blob_bin_start
    jalr zero, t0, 0

after_user:
    call oracle_report
halt:
    wfi
    j halt
