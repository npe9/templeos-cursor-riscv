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
// Bit-field ops on a byte array: bit n is bit (n&7) of byte n>>3. Bt tests, Bts sets, Btr resets;
// each returns the OLD bit. LBts/LBtr are the locked variants (single core here -> identical).
asm {
Bt::
	srai	t0,a1,3
	add	t0,a0,t0
	lbu	t1,0(t0)
	andi	t2,a1,7
	srl	t1,t1,t2
	andi	a0,t1,1
	ret
}
asm {
Bts::
	srai	t0,a1,3
	add	t0,a0,t0
	lbu	t1,0(t0)
	andi	t2,a1,7
	srl	t3,t1,t2
	andi	t3,t3,1
	li	t4,1
	sll	t4,t4,t2
	or	t1,t1,t4
	sb	t1,0(t0)
	mv	a0,t3
	ret
}
asm {
Btr::
	srai	t0,a1,3
	add	t0,a0,t0
	lbu	t1,0(t0)
	andi	t2,a1,7
	srl	t3,t1,t2
	andi	t3,t3,1
	li	t4,1
	sll	t4,t4,t2
	not	t4,t4
	and	t1,t1,t4
	sb	t1,0(t0)
	mv	a0,t3
	ret
}
asm {
LBts::
	srai	t0,a1,3
	add	t0,a0,t0
	lbu	t1,0(t0)
	andi	t2,a1,7
	srl	t3,t1,t2
	andi	t3,t3,1
	li	t4,1
	sll	t4,t4,t2
	or	t1,t1,t4
	sb	t1,0(t0)
	mv	a0,t3
	ret
}
asm {
LBtr::
	srai	t0,a1,3
	add	t0,a0,t0
	lbu	t1,0(t0)
	andi	t2,a1,7
	srl	t3,t1,t2
	andi	t3,t3,1
	li	t4,1
	sll	t4,t4,t2
	not	t4,t4
	and	t1,t1,t4
	sb	t1,0(t0)
	mv	a0,t3
	ret
}
// I64 Bsf(I64 v): index of the lowest set bit, or -1 if v==0.  Bsr: the highest set bit.
asm {
Bsf::
	beq	a0,zero,bsf_zero
	mv	t0,a0
	li	a0,0
bsf_loop:
	andi	t1,t0,1
	bne	t1,zero,bsf_done
	srli	t0,t0,1
	addi	a0,a0,1
	j	bsf_loop
bsf_zero:
	li	a0,-1
bsf_done:
	ret
}
asm {
Bsr::
	beq	a0,zero,bsr_zero
	mv	t0,a0
	li	a0,63
bsr_loop:
	srl	t1,t0,a0
	andi	t1,t1,1
	bne	t1,zero,bsr_done
	addi	a0,a0,-1
	j	bsr_loop
bsr_zero:
	li	a0,-1
bsr_done:
	ret
}
// I64 ToUpper(I64 c): 'a'..'z' -> 'A'..'Z', else unchanged.
asm {
ToUpper::
	li	t0,97
	blt	a0,t0,tu_done
	li	t1,122
	blt	t1,a0,tu_done
	addi	a0,a0,-32
tu_done:
	ret
}
// I64 AbsI64(I64 v); MaxI64(a,b); ClampI64(x,lo,hi); SqrI64(x); SwapI64(*a,*b).
asm {
AbsI64::
	bge	a0,zero,abs_done
	neg	a0,a0
abs_done:
	ret
}
asm {
MaxI64::
	blt	a0,a1,max_b
	ret
max_b:
	mv	a0,a1
	ret
}
asm {
ClampI64::
	blt	a0,a1,clamp_lo
	blt	a2,a0,clamp_hi
	ret
clamp_lo:
	mv	a0,a1
	ret
clamp_hi:
	mv	a0,a2
	ret
}
asm {
SqrI64::
	mul	a0,a0,a0
	ret
}
asm {
SwapI64::
	ld	t0,0(a0)
	ld	t1,0(a1)
	sd	t1,0(a0)
	sd	t0,0(a1)
	li	a0,0
	ret
}
// BEqu(bf,n,val): set bit n to val (Bts if val, Btr if not); returns val. LBEqu is the locked variant.
asm {
BEqu::
	srai	t0,a1,3
	add	t0,a0,t0
	lbu	t1,0(t0)
	andi	t2,a1,7
	li	t4,1
	sll	t4,t4,t2
	beq	a2,zero,beq_clr
	or	t1,t1,t4
	j	beq_st
beq_clr:
	not	t4,t4
	and	t1,t1,t4
beq_st:
	sb	t1,0(t0)
	mv	a0,a2
	ret
}
asm {
LBEqu::
	srai	t0,a1,3
	add	t0,a0,t0
	lbu	t1,0(t0)
	andi	t2,a1,7
	li	t4,1
	sll	t4,t4,t2
	beq	a2,zero,lbeq_clr
	or	t1,t1,t4
	j	lbeq_st
lbeq_clr:
	not	t4,t4
	and	t1,t1,t4
lbeq_st:
	sb	t1,0(t0)
	mv	a0,a2
	ret
}
// I64 StrICmp(U8 *a, U8 *b): case-insensitive compare (lower both), 0 if equal.
asm {
StrICmp::
sic_loop:
	lbu	t0,0(a0)
	lbu	t1,0(a1)
	mv	t2,t0
	li	t4,65
	blt	t2,t4,sic_b
	li	t4,90
	blt	t4,t2,sic_b
	addi	t2,t2,32
sic_b:
	mv	t3,t1
	li	t4,65
	blt	t3,t4,sic_cmp
	li	t4,90
	blt	t4,t3,sic_cmp
	addi	t3,t3,32
sic_cmp:
	bne	t2,t3,sic_done
	beq	t0,zero,sic_done
	addi	a0,a0,1
	addi	a1,a1,1
	j	sic_loop
sic_done:
	sub	a0,t2,t3
	ret
}
// Doubly-linked circular queue ops on CQue {next@0, last@8}. QueIns(e,pred) inserts e after pred;
// QueInsRev(e,succ) before succ; QueRem(e) unlinks e; QueInit(h) makes an empty ring.
asm {
QueInit::
	sd	a0,0(a0)
	sd	a0,8(a0)
	li	a0,0
	ret
}
asm {
QueIns::
	ld	t0,0(a1)
	sd	t0,0(a0)
	sd	a1,8(a0)
	sd	a0,8(t0)
	sd	a0,0(a1)
	li	a0,0
	ret
}
asm {
QueInsRev::
	ld	t0,8(a1)
	sd	t0,8(a0)
	sd	a1,0(a0)
	sd	a0,0(t0)
	sd	a0,8(a1)
	li	a0,0
	ret
}
asm {
QueRem::
	ld	t0,8(a0)
	ld	t1,0(a0)
	sd	t1,0(t0)
	sd	t0,8(t1)
	li	a0,0
	ret
}
// ModU64(q,d): unsigned divmod in place — *q = *q/d, return *q%d (0 if d==0).
asm {
ModU64::
	beq	a1,zero,mu_z
	ld	t0,0(a0)
	divu	t1,t0,a1
	sd	t1,0(a0)
	remu	a0,t0,a1
	ret
mu_z:
	li	a0,0
	ret
}
// BFieldExtU32(bf,lo,hi): extract bits [lo..hi] of byte array bf as an integer (bit lo = LSB).
asm {
BFieldExtU32::
	li	a3,0
	mv	a4,a2
bfe_loop:
	blt	a4,a1,bfe_done
	srai	t0,a4,3
	add	t0,a0,t0
	lbu	t1,0(t0)
	andi	t2,a4,7
	srl	t1,t1,t2
	andi	t1,t1,1
	slli	a3,a3,1
	or	a3,a3,t1
	addi	a4,a4,-1
	j	bfe_loop
bfe_done:
	mv	a0,a3
	ret
}
// BFieldOrU32(bf,lo,hi): set bits [lo..hi] of byte array bf.
asm {
BFieldOrU32::
	mv	a4,a1
bfo_loop:
	blt	a2,a4,bfo_done
	srai	t0,a4,3
	add	t0,a0,t0
	lbu	t1,0(t0)
	andi	t2,a4,7
	li	t3,1
	sll	t3,t3,t2
	or	t1,t1,t3
	sb	t1,0(t0)
	addi	a4,a4,1
	j	bfo_loop
bfo_done:
	li	a0,0
	ret
}
// GetRSP/GetRBP: return the current stack / frame pointer. On RISC-V these are sp / fp(s0)
// directly (no x86 register file); used by KTask/KExcept to capture task context.
asm {
GetRSP::
	mv	a0,sp
	ret
}
asm {
GetRBP::
	mv	a0,fp
	ret
}
// LXchgI64(d,v): swap *d with v, return the old value. The runtime impl is a plain (non-atomic)
// load/store; QEMU virt boots single-core, so ld/sd is a faithful port.
asm {
LXchgI64::
	ld	t0,0(a0)
	sd	a1,0(a0)
	mv	a0,t0
	ret
}
// StrMatch(needle,hay,flags): return a pointer to the first occurrence of needle in hay, or 0.
// (flags is accepted for signature compatibility but unused, matching the runtime.)
asm {
StrMatch::
	mv	t0,a1
sm_outer:
	lbu	t1,0(t0)
	beq	t1,zero,sm_fail
	mv	t2,a0
	mv	t3,t0
sm_inner:
	lbu	t4,0(t2)
	beq	t4,zero,sm_hit
	lbu	t5,0(t3)
	bne	t4,t5,sm_next
	addi	t2,t2,1
	addi	t3,t3,1
	j	sm_inner
sm_next:
	addi	t0,t0,1
	j	sm_outer
sm_hit:
	mv	a0,t0
	ret
sm_fail:
	li	a0,0
	ret
}
// StrIMatch(needle,hay,flags): case-insensitive StrMatch (ASCII A-Z folded to lower before compare).
asm {
StrIMatch::
	mv	t0,a1
si_outer:
	lbu	t1,0(t0)
	beq	t1,zero,si_fail
	mv	t2,a0
	mv	t3,t0
si_inner:
	lbu	t4,0(t2)
	beq	t4,zero,si_hit
	lbu	t5,0(t3)
	li	t6,65
	blt	t4,t6,si_a_ok
	li	t6,90
	blt	t6,t4,si_a_ok
	addi	t4,t4,32
si_a_ok:
	li	t6,65
	blt	t5,t6,si_b_ok
	li	t6,90
	blt	t6,t5,si_b_ok
	addi	t5,t5,32
si_b_ok:
	bne	t4,t5,si_next
	addi	t2,t2,1
	addi	t3,t3,1
	j	si_inner
si_next:
	addi	t0,t0,1
	j	si_outer
si_hit:
	mv	a0,t0
	ret
si_fail:
	li	a0,0
	ret
}
// RV64D float math (native RISC-V, replacing the x87 FPU asm of original TempleOS). F64 args/returns
// travel as raw bits in a0, so each moves bits->fa0, computes, moves fa0->a0.
asm {
Sqrt::
	fmvdx	fa0,a0
	fsqrtd	fa0,fa0
	fmvxd	a0,fa0
	ret
}
// Floor: round toward -inf (fcvt.l.d rdn), then back to double.
asm {
Floor::
	fmvdx	fa0,a0
	fcvtld_rdn	t0,fa0
	fcvtdl	fa0,t0
	fmvxd	a0,fa0
	ret
}
// Trunc: round toward zero (rtz).
asm {
Trunc::
	fmvdx	fa0,a0
	fcvtld_rtz	t0,fa0
	fcvtdl	fa0,t0
	fmvxd	a0,fa0
	ret
}
// Round: nearest, ties away from zero (rmm) — matches HolyRound's symmetric x>=0?(I64)(x+.5):-(I64)(-x+.5).
asm {
Round::
	fmvdx	fa0,a0
	fcvtld_rmm	t0,fa0
	fcvtdl	fa0,t0
	fmvxd	a0,fa0
	ret
}
// GetTSC: read the RISC-V time CSR (rdtime = csrrs a0,time,x0), replacing x86 RDTSC. Used for
// timestamps/unique ids (FileSysRedSea unique_id, Mouse/Keyboard timing).
asm {
GetTSC::
	rdtime	a0
	ret
}
