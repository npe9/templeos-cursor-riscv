// Native RISC-V ports of the low-level primitives TempleOS writes in x86 assembly (Kernel/KUtils.HC).
// On RISC-V the x86 asm blocks in KUtils.HC are not RISC-V, so they are skipped; these native RISC-V
// asm definitions self-resolve the SAME functions by name (MemSet, MemCpy), so the kernel runs its
// OWN native RISC-V code rather than the C runtime overrides. Ordinary RISC-V calling convention:
// args in a0.., return in a0. Each is its own asm{} block (one function per block).
// U8 *MemSet(U8 *dst=a0, I64 dat=a1, I64 size=a2); returns dst+size (a0 walks to the end).
asm {
MemSet::
ms_loop:
	beq	a2,zero,ms_done
	sb	a1,0(a0)
	addi	a0,a0,1
	addi	a2,a2,-1
	j	ms_loop
ms_done:
	ret
}
// U8 *MemCpy(U8 *dst=a0, U8 *src=a1, I64 size=a2); returns dst+size.
asm {
MemCpy::
mc_loop:
	beq	a2,zero,mc_done
	lb	t0,0(a1)
	sb	t0,0(a0)
	addi	a0,a0,1
	addi	a1,a1,1
	addi	a2,a2,-1
	j	mc_loop
mc_done:
	ret
}
