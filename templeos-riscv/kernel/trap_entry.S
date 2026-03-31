/* S-mode trap vector (QEMU virt -kernel -bios none enters supervisor mode). */
.section .text
.balign 4
.global trap_vector

trap_vector:
	/* Exchange sp with sscratch: sp = trap stack top, sscratch = faulting sp. */
	csrrw sp, sscratch, sp
	addi sp, sp, -288

	sd ra,   0(sp)
	sd gp,   8(sp)
	sd tp,  16(sp)
	sd t0,   24(sp)
	sd t1,   32(sp)
	sd t2,   40(sp)
	sd s0,   48(sp)
	sd s1,   56(sp)
	sd a0,   64(sp)
	sd a1,   72(sp)
	sd a2,   80(sp)
	sd a3,   88(sp)
	sd a4,   96(sp)
	sd a5,  104(sp)
	sd a6,  112(sp)
	sd a7,  120(sp)
	sd s2,  128(sp)
	sd s3,  136(sp)
	sd s4,  144(sp)
	sd s5,  152(sp)
	sd s6,  160(sp)
	sd s7,  168(sp)
	sd s8,  176(sp)
	sd s9,  184(sp)
	sd s10, 192(sp)
	sd s11, 200(sp)
	sd t3,  208(sp)
	sd t4,  216(sp)
	sd t5,  224(sp)
	sd t6,  232(sp)

	csrr a0, scause
	csrr a1, sepc
	csrr a2, stval
	call rv_s_trap_fatal

	/* No return expected; halt if C returns. */
1:	wfi
	j 1b
