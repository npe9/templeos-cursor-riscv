# Bare-metal hello for HiFive Unmatched, linked at 0x80200000. Touches ONLY the SiFive UART0, so it
# runs identically whether entered in S-mode (U-Boot `go`) or M-mode (JTAG takeover). No CSRs.
# SiFive UART: TXDATA at +0, bit31 = FIFO full.
    .section .text
    .globl _start
_start:
    li   t0, 0x10010000
    la   t1, msg
1:  lbu  t2, 0(t1)
    beqz t2, 3f
2:  lw   t3, 0(t0)
    bltz t3, 2b
    sw   t2, 0(t0)
    addi t1, t1, 1
    j    1b
3:  wfi
    j    3b
msg:
    .asciz "\r\nTempleOS/RV64 hello from 0x80200000\r\n"
