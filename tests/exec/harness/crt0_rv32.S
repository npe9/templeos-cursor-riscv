# RV32 P0 crt0: import-free. Install a fault vector, set sp, call the HolyC blob as
# I64 (*)(void), then report the low word of a0 on the virt 16550 UART. No resolve_imports:
# the P0 blob must not call the runtime (HOFYIMP1 slots stay unresolved).
.equ UART, 0x10000000
.section .text.init
.global _start

_start:
    csrr t0, mhartid
    bnez t0, halt
    la t0, trap_entry
    csrw mtvec, t0
    la sp, __stack_top
    la t0, _binary_blob_bin_start
    jalr ra, t0, 0
    li t1, UART
    beqz a0, ok
    la a1, msg_bad
    j puts
ok:
    la a1, msg_ok
puts:
    lbu t2, 0(a1)
    beqz t2, halt
    sb t2, 0(t1)
    addi a1, a1, 1
    j puts
halt:
    wfi
    j halt

    .align 2
trap_entry:
    li t1, UART
    la a1, msg_trap
    j puts

.section .rodata
msg_ok:   .asciz "rv32-p0: ret=0 OK\n"
msg_bad:  .asciz "rv32-p0: ret!=0 FAIL\n"
msg_trap: .asciz "rv32-p0: TRAP\n"
