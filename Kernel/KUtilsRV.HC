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
// I64 StrLen(U8 *s=a0); returns the length (bytes before the NUL).
asm {
StrLen::
	mv	t0,a0
sl_loop:
	lb	t1,0(a0)
	beq	t1,zero,sl_done
	addi	a0,a0,1
	j	sl_loop
sl_done:
	sub	a0,a0,t0
	ret
}
// U8 *StrCpy(U8 *dst=a0, U8 *src=a1); copies through the NUL, returns dst.
asm {
StrCpy::
	mv	t0,a0
scy_loop:
	lb	t1,0(a1)
	sb	t1,0(a0)
	beq	t1,zero,scy_done
	addi	a0,a0,1
	addi	a1,a1,1
	j	scy_loop
scy_done:
	mv	a0,t0
	ret
}
// I64 StrCmp(U8 *a=a0, U8 *b=a1); 0 if equal, else (U8)*a-(U8)*b at the first difference.
asm {
StrCmp::
scmp_loop:
	lbu	t0,0(a0)
	lbu	t1,0(a1)
	bne	t0,t1,scmp_done
	beq	t0,zero,scmp_done
	addi	a0,a0,1
	addi	a1,a1,1
	j	scmp_loop
scmp_done:
	sub	a0,t0,t1
	ret
}
// I64 StrNCmp(U8 *a=a0, U8 *b=a1, I64 n=a2); compares up to n bytes.
asm {
StrNCmp::
sncmp_loop:
	beq	a2,zero,sncmp_eq
	lbu	t0,0(a0)
	lbu	t1,0(a1)
	bne	t0,t1,sncmp_diff
	beq	t0,zero,sncmp_eq
	addi	a0,a0,1
	addi	a1,a1,1
	addi	a2,a2,-1
	j	sncmp_loop
sncmp_diff:
	sub	a0,t0,t1
	ret
sncmp_eq:
	li	a0,0
	ret
}
// I64 *MemSetI64(I64 *dst=a0, I64 v=a1, I64 cnt=a2); writes cnt words, returns dst.
asm {
MemSetI64::
	mv	t0,a0
msi_loop:
	beq	a2,zero,msi_done
	sd	a1,0(t0)
	addi	t0,t0,8
	addi	a2,a2,-1
	j	msi_loop
msi_done:
	ret
}
