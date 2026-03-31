/* TempleOS/RISC-V — entry before C kernel. */
.section .text.init
.global _start

_start:
    la sp, __stack_top
    mv s0, sp

    la t0, __bss_start
    la t1, __bss_end
1:
    beq t0, t1, 2f
    sd zero, 0(t0)
    addi t0, t0, 8
    j 1b
2:
    /* Trap stack for S-mode handler (sscratch swap). Phase A — TOS_X86_PARITY.md */
    la t0, trap_stack_top
    csrw sscratch, t0
    la t0, trap_vector
    csrw stvec, t0
    call kernel_main
3:
    wfi
    j 3b
