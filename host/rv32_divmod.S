# rv32_divmod.S — the one runtime helper the RV32 backend appends to every rv32 blob.
#
# 64-bit div/divu/rem/remu for host/rv32_lift.c, with rv64 M-extension semantics (x/0 = -1,
# x%0 = x, MIN/-1 = MIN, MIN%-1 = 0), and op 4: F64 -> I64 truncation (fcvt.l.d rtz; out of
# range saturates to MAX/MIN by sign). Position independent (branches only).
# The call site (rv32_lift.c, LiftHelperCall) does:
#     addi sp,sp,-32 ; x lo/hi -> 0/4(sp) ; y lo/hi -> 8/12(sp) ; t6 = op (0 div, 1 divu, 2 rem, 3 remu)
#     (op 4: the F64 bits are x; y is unused)
#     auipc a7,.. ; jalr a7,..(a7)            # link in a7: ra may be live (frameless code)
#     result lo/hi <- 16/20(sp) ; addi sp,sp,32
# Every register except t6/a7 is preserved.
#
# Regenerate the word table after editing:  tools/gen_rv32_stubs.sh  (writes host/rv32_stubs.inc)
    .text
    .globl rv32_divmod
rv32_divmod:
    addi sp, sp, -48
    sw a0, 0(sp)
    sw a1, 4(sp)
    sw a2, 8(sp)
    sw a3, 12(sp)
    sw a4, 16(sp)
    sw a5, 20(sp)
    sw a6, 24(sp)
    sw t0, 28(sp)
    sw t1, 32(sp)
    sw t2, 36(sp)
    sw t3, 40(sp)
    lw a0, 48(sp)            # n = x
    lw a1, 52(sp)
    lw a2, 56(sp)            # d = y
    lw a3, 60(sp)
    li t2, 4
    beq t6, t2, f2l
    li t0, 0                 # negate the quotient
    li t1, 0                 # negate the remainder
    andi t2, t6, 1           # divu / remu
    bnez t2, udiv
    bgez a1, xpos
    li t0, 1
    li t1, 1
    snez t3, a0              # n = -n
    neg a0, a0
    neg a1, a1
    sub a1, a1, t3
xpos:
    or t3, a2, a3
    bnez t3, ynz
    li t0, 0                 # x/0 = -1 whatever the sign of x
    j udiv
ynz:
    bgez a3, udiv
    xori t0, t0, 1
    snez t3, a2              # d = -d
    neg a2, a2
    neg a3, a3
    sub a3, a3, t3
udiv:                        # restoring division: q in a0:a1, r in a4:a5
    li a4, 0
    li a5, 0
    li a6, 64
loop:
    srli t3, a4, 31          # r = r << 1 | q >> 63
    slli a5, a5, 1
    or a5, a5, t3
    srli t3, a1, 31
    slli a4, a4, 1
    or a4, a4, t3
    srli t3, a0, 31          # q <<= 1
    slli a1, a1, 1
    or a1, a1, t3
    slli a0, a0, 1
    bltu a5, a3, next        # r < d ?
    bne a5, a3, take
    bltu a4, a2, next
take:
    sltu t3, a4, a2          # r -= d
    sub a4, a4, a2
    sub a5, a5, a3
    sub a5, a5, t3
    ori a0, a0, 1
next:
    addi a6, a6, -1
    bnez a6, loop
    andi t2, t6, 2           # rem / remu: result is r
    beqz t2, pick
    mv a0, a4
    mv a1, a5
    mv t0, t1
pick:
    beqz t0, out
    snez t3, a0
    neg a0, a0
    neg a1, a1
    sub a1, a1, t3
    j out
f2l:                         # a1:a0 = F64 bits -> a1:a0 = trunc to I64
    srli a2, a1, 20
    andi a2, a2, 0x7FF       # biased exponent
    li t3, 1023
    bltu a2, t3, f2l_zero    # |x| < 1
    li t3, 1086
    bgeu a2, t3, f2l_sat     # |x| >= 2^63, inf, NaN
    li t3, 0xFFFFF
    and a3, a1, t3
    lui t3, 0x100
    or a3, a3, t3            # a3:a0 = mantissa | 1 << 52
    addi a2, a2, -1075       # value = mantissa << a2
    bltz a2, f2l_right
f2l_left:
    beqz a2, f2l_sign
    srli t3, a0, 31
    slli a3, a3, 1
    or a3, a3, t3
    slli a0, a0, 1
    addi a2, a2, -1
    j f2l_left
f2l_right:
    neg a2, a2
f2l_rloop:
    beqz a2, f2l_sign
    slli t3, a3, 31
    srli a0, a0, 1
    or a0, a0, t3
    srli a3, a3, 1
    addi a2, a2, -1
    j f2l_rloop
f2l_sign:
    bgez a1, f2l_pos
    snez t3, a0
    neg a0, a0
    neg a3, a3
    sub a3, a3, t3
f2l_pos:
    mv a1, a3
    j out
f2l_zero:
    li a0, 0
    li a1, 0
    j out
f2l_sat:
    bltz a1, f2l_min
    li a0, -1
    li a1, 0x7FFFFFFF
    j out
f2l_min:
    li a0, 0
    li a1, 0x80000000
out:
    sw a0, 64(sp)
    sw a1, 68(sp)
    lw a0, 0(sp)
    lw a1, 4(sp)
    lw a2, 8(sp)
    lw a3, 12(sp)
    lw a4, 16(sp)
    lw a5, 20(sp)
    lw a6, 24(sp)
    lw t0, 28(sp)
    lw t1, 32(sp)
    lw t2, 36(sp)
    lw t3, 40(sp)
    addi sp, sp, 48
    jr a7
