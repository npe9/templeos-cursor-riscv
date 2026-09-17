# RV32 exec crt0: import-free. Install a fault vector, set sp, call the HolyC blob as
# I64 (*)(void), then print "ORACLE <a1><a0>" (16 hex digits: a1 = high word of the
# register-pair I64 result, a0 = low word) on the virt 16550 UART. A fault prints
# "TRAP mcause=… mepc=… mtval=… blob+…". No resolve_imports: the blob must not call the
# runtime (its HOFYIMP1 slots stay unresolved).
.equ UART, 0x10000000
.section .text.init
.global _start

_start:
    csrr t0, mhartid
    bnez t0, halt
    la t0, trap_entry
    csrw mtvec, t0
    li t0, (1 << 13)          # mstatus.FS = Initial: F64 code traps otherwise
    csrs mstatus, t0
    la sp, __stack_top
    la t0, _binary_blob_bin_start
    jalr ra, t0, 0
    mv s1, a0
    mv s2, a1
    la a0, msg_oracle
    call puts
    mv a0, s2
    call puthex
    mv a0, s1
    call puthex
    li a0, '\n'
    call putc
halt:
    wfi
    j halt

    .align 2
trap_entry:
    la sp, __trap_stack_top
    la a0, msg_trap
    call puts
    csrr a0, mcause
    call puthex
    la a0, msg_mepc
    call puts
    csrr a0, mepc
    call puthex
    la a0, msg_mtval
    call puts
    csrr a0, mtval
    call puthex
    la a0, msg_blob
    call puts
    csrr a0, mepc
    la t0, _binary_blob_bin_start
    sub a0, a0, t0
    call puthex
    li a0, '\n'
    call putc
    j halt

# putc(a0)
putc:
    li t0, UART
    sb a0, 0(t0)
    ret
# puts(a0 = NUL-terminated string)
puts:
    li t0, UART
1:  lbu t1, 0(a0)
    beqz t1, 2f
    sb t1, 0(t0)
    addi a0, a0, 1
    j 1b
2:  ret
# puthex(a0): 8 lowercase hex digits
puthex:
    li t0, UART
    li t2, 28
1:  srl t1, a0, t2
    andi t1, t1, 15
    addi t1, t1, '0'
    li t3, '9'
    ble t1, t3, 2f
    addi t1, t1, 39           # '0'+10+39 == 'a'
2:  sb t1, 0(t0)
    addi t2, t2, -4
    bgez t2, 1b
    ret

.section .rodata
msg_oracle: .asciz "ORACLE "
msg_trap:   .asciz "\nTRAP mcause=0x"
msg_mepc:   .asciz " mepc=0x"
msg_mtval:  .asciz " mtval=0x"
msg_blob:   .asciz " blob+0x"

.section .bss
.align 4
.space 1024
__trap_stack_top:
