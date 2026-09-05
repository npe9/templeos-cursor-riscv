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
// each returns the OLD bit. LBts/LBtr/LBtc use LR.W/SC.W on the containing aligned word (A-ext).
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
	// a0=bf, a1=bit → atomic set; return old bit
	srai	t0,a1,3
	add	t0,a0,t0
	andi	t1,t0,3
	sub	t2,t0,t1
	slli	t1,t1,3
	andi	t3,a1,7
	add	t1,t1,t3
	li	t3,1
	sll	t3,t3,t1
	lbts_retry:
	lr.w	t4,(t2)
	and	t5,t4,t3
	sltu	t5,zero,t5
	or	t6,t4,t3
	sc.w	t0,t6,(t2)
	bnez	t0,lbts_retry
	mv	a0,t5
	ret
}

asm {
	LBtr::
	srai	t0,a1,3
	add	t0,a0,t0
	andi	t1,t0,3
	sub	t2,t0,t1
	slli	t1,t1,3
	andi	t3,a1,7
	add	t1,t1,t3
	li	t3,1
	sll	t3,t3,t1
	lbtr_retry:
	lr.w	t4,(t2)
	and	t5,t4,t3
	sltu	t5,zero,t5
	not	t6,t3
	and	t6,t4,t6
	sc.w	t0,t6,(t2)
	bnez	t0,lbtr_retry
	mv	a0,t5
	ret
}

asm {
	LBtc::
	srai	t0,a1,3
	add	t0,a0,t0
	andi	t1,t0,3
	sub	t2,t0,t1
	slli	t1,t1,3
	andi	t3,a1,7
	add	t1,t1,t3
	li	t3,1
	sll	t3,t3,t1
	lbtc_retry:
	lr.w	t4,(t2)
	and	t5,t4,t3
	sltu	t5,zero,t5
	xor	t6,t4,t3
	sc.w	t0,t6,(t2)
	bnez	t0,lbtc_retry
	mv	a0,t5
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
	beq	t0,zero,qr_done
	ld	t1,0(a0)
	beq	t1,zero,qr_done
	sd	t1,0(t0)
	sd	t0,8(t1)
	qr_done:
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
// LXchgI64(d,v): atomic swap *d with v (amoswap.d), return the old value.
asm {
	LXchgI64::
	amoswap.d	a0,a1,(a0)
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
// Sqr: d*d (replaces KMathA _SQR x87; needed by AMathODE MassFind / state_scale).
asm {
	Sqr::
	fmvdx	fa0,a0
	fmuld	fa0,fa0,fa0
	fmvxd	a0,fa0
	ret
}
// Abs: clear sign bit (RV64D fabs.d).
asm {
	Abs::
	fmvdx	fa0,a0
	fabsd	fa0,fa0
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
// CPU status/introspection -> RISC-V CSR equivalents (replacing x86 RFLAGS/CPUID/INVLPG).
// GetRFlags/SetRFlags read/write mstatus (the M-mode status register, RISC-V's flags analog).
asm {
	GetRFlags::
	csrr	a0,0x300
	ret
}

asm {
	SetRFlags::
	csrw	0x300,a0
	ret
}
// InvlPg(a): flush the TLB entry for address a (sfence.vma). Legal in M-mode; a no-op with no MMU.
asm {
	InvlPg::
	sfencevma	a0
	ret
}
// CPUId(func,res): x86 CPUID has no RISC-V analog; fill the 32-byte res buffer with the RISC-V
// identity CSRs mvendorid/marchid/mimpid/misa (func in a0 is ignored, as in the runtime stub).
asm {
	CPUId::
	csrr	t0,0xF11
	sd	t0,0(a1)
	csrr	t0,0xF12
	sd	t0,8(a1)
	csrr	t0,0xF13
	sd	t0,16(a1)
	csrr	t0,0x301
	sd	t0,24(a1)
	li	a0,0
	ret
}
// Port I/O -> MMIO. RISC-V has no separate I/O port space; device registers are memory-mapped, so
// In*/Out* become plain loads/stores at the (address) operand and Rep* are count loops. The compiled
// x86 drivers (ATA/VGA/8259 PIC/i8042/CMOS) address legacy ports below 64KB, which map to NO device
// on QEMU virt, so accesses in that range are inert (a load returns 0, a store is dropped) -- the
// correct RISC-V behavior for an absent device -- while real MMIO addresses (Goldfish RTC 0x101000,
// etc.) do genuine load/store. Threshold 0x10000 = 1<<16 (x86 ports max at 0xFFFF; virt MMIO >=0x101000).
asm {
	InU8::
	li	t0,1
	slli	t0,t0,16
	bltu	a0,t0,inu8_none
	lbu	a0,0(a0)
	ret
	inu8_none:
	li	a0,0
	ret
}

asm {
	InU16::
	li	t0,1
	slli	t0,t0,16
	bltu	a0,t0,inu16_none
	lhu	a0,0(a0)
	ret
	inu16_none:
	li	a0,0
	ret
}

asm {
	InU32::
	li	t0,1
	slli	t0,t0,16
	bltu	a0,t0,inu32_none
	lwu	a0,0(a0)
	ret
	inu32_none:
	li	a0,0
	ret
}

asm {
	OutU8::
	li	t0,1
	slli	t0,t0,16
	bltu	a0,t0,outu8_none
	sb	a1,0(a0)
	outu8_none:
	li	a0,0
	ret
}

asm {
	OutU16::
	li	t0,1
	slli	t0,t0,16
	bltu	a0,t0,outu16_none
	sh	a1,0(a0)
	outu16_none:
	li	a0,0
	ret
}

asm {
	OutU32::
	li	t0,1
	slli	t0,t0,16
	bltu	a0,t0,outu32_none
	sw	a1,0(a0)
	outu32_none:
	li	a0,0
	ret
}
// RepInU16(buf,cnt,port): read cnt U16s from the MMIO port into buf (port fixed, buf advances);
// a legacy port (<64KB) zero-fills buf, matching the runtime stub.
asm {
	RepInU16::
	li	t1,1
	slli	t1,t1,16
	bltu	a2,t1,ri16_zero
	ri16_loop:
	beq	a1,zero,ri16_done
	lhu	t0,0(a2)
	sh	t0,0(a0)
	addi	a0,a0,2
	addi	a1,a1,-1
	j	ri16_loop
	ri16_zero:
	beq	a1,zero,ri16_done
	sh	zero,0(a0)
	addi	a0,a0,2
	addi	a1,a1,-1
	j	ri16_zero
	ri16_done:
	li	a0,0
	ret
}

asm {
	RepInU32::
	li	t1,1
	slli	t1,t1,16
	bltu	a2,t1,ri32_zero
	ri32_loop:
	beq	a1,zero,ri32_done
	lwu	t0,0(a2)
	sw	t0,0(a0)
	addi	a0,a0,4
	addi	a1,a1,-1
	j	ri32_loop
	ri32_zero:
	beq	a1,zero,ri32_done
	sw	zero,0(a0)
	addi	a0,a0,4
	addi	a1,a1,-1
	j	ri32_zero
	ri32_done:
	li	a0,0
	ret
}
// RepOutU32(buf,cnt,port): write cnt U32s from buf to the MMIO port (buf advances, port fixed);
// a legacy port (<64KB) drops the writes, matching the runtime stub.
asm {
	RepOutU32::
	li	t1,1
	slli	t1,t1,16
	bltu	a2,t1,ro32_done
	ro32_loop:
	beq	a1,zero,ro32_done
	lwu	t0,0(a0)
	sw	t0,0(a2)
	addi	a0,a0,4
	addi	a1,a1,-1
	j	ro32_loop
	ro32_done:
	li	a0,0
	ret
}
// RV64D transcendentals (native FPU, per "use the fpu for the float library"). RISC-V has no hardware
// ln/exp, so Ln/Exp port rt_ln/rt_exp (holy_rt.h) loop-for-loop on the FPU; 64-bit F64 constants come
// from the lifp macro. Exp(x): range-reduce by ln2, 30-term Taylor, scale by 2^k. (was x87 in TempleOS)
asm {
	Exp::
	fmvdx	ft0,a0
	lifp	t0,0x4086280000000000
	fmvdx	ft7,t0
	fltd	t0,ft7,ft0
	beq	t0,zero,exp_nohi
	lifp	a0,0x7FF0000000000000
	ret
	exp_nohi:
	lifp	t0,0xC087480000000000
	fmvdx	ft7,t0
	fltd	t0,ft0,ft7
	beq	t0,zero,exp_nolo
	li	a0,0
	ret
	exp_nolo:
	lifp	t0,0x3FE62E42FEFA39EF
	fmvdx	ft1,t0
	lifp	t0,0x4000000000000000
	fmvdx	ft3,t0
	li	t0,0
	fmvdx	ft8,t0
	lifp	t0,0x3FE0000000000000
	fmvdx	ft9,t0
	fdivd	ft4,ft0,ft1
	fled	t2,ft8,ft0
	beq	t2,zero,exp_negb
	faddd	ft4,ft4,ft9
	j	exp_bdone
	exp_negb:
	lifp	t2,0xBFE0000000000000
	fmvdx	ft7,t2
	faddd	ft4,ft4,ft7
	exp_bdone:
	fcvtld_rtz	t0,ft4
	fcvtdl	ft5,t0
	fmuld	ft5,ft5,ft1
	fsubd	ft4,ft0,ft5
	lifp	t2,0x3FF0000000000000
	fmvdx	ft5,t2
	fmvdx	ft6,t2
	li	t1,1
	exp_loop:
	li	t2,30
	bge	t1,t2,exp_scale
	fcvtdl	ft7,t1
	fdivd	ft7,ft4,ft7
	fmuld	ft6,ft6,ft7
	faddd	ft5,ft5,ft6
	addi	t1,t1,1
	j	exp_loop
	exp_scale:
	exp_up:
	bge	zero,t0,exp_updone
	fmuld	ft5,ft5,ft3
	addi	t0,t0,-1
	j	exp_up
	exp_updone:
	exp_dn:
	bge	t0,zero,exp_dndone
	fmuld	ft5,ft5,ft9
	addi	t0,t0,1
	j	exp_dn
	exp_dndone:
	fmvxd	a0,ft5
	ret
}
// Ln(x): range-reduce to [1,2) tracking the power of 2, atanh series (60 terms), + e*ln2. Ports rt_ln.
asm {
	Ln::
	fmvdx	ft0,a0
	li	t0,0
	fmvdx	ft9,t0
	fled	t0,ft0,ft9
	beq	t0,zero,ln_pos
	feqd	t0,ft0,ft9
	beq	t0,zero,ln_nan
	lifp	a0,0xFFF0000000000000
	ret
	ln_nan:
	lifp	a0,0x7FF8000000000000
	ret
	ln_pos:
	lifp	t0,0x3FF0000000000000
	fmvdx	ft1,t0
	lifp	t0,0x4000000000000000
	fmvdx	ft2,t0
	lifp	t0,0x3FE0000000000000
	fmvdx	ft3,t0
	lifp	t0,0x3FE62E42FEFA39EF
	fmvdx	ft4,t0
	li	t0,0
	ln_up:
	fled	t2,ft2,ft0
	beq	t2,zero,ln_updone
	fmuld	ft0,ft0,ft3
	addi	t0,t0,1
	j	ln_up
	ln_updone:
	ln_dn:
	fltd	t2,ft0,ft1
	beq	t2,zero,ln_dndone
	fmuld	ft0,ft0,ft2
	addi	t0,t0,-1
	j	ln_dn
	ln_dndone:
	fsubd	ft5,ft0,ft1
	faddd	ft9,ft0,ft1
	fdivd	ft5,ft5,ft9
	fmuld	ft6,ft5,ft5
	li	t2,0
	fmvdx	ft7,t2
	fmuld	ft8,ft5,ft1
	li	t1,1
	ln_loop:
	li	t2,60
	bge	t1,t2,ln_sdone
	fcvtdl	ft9,t1
	fdivd	ft10,ft8,ft9
	faddd	ft7,ft7,ft10
	fmuld	ft8,ft8,ft6
	addi	t1,t1,2
	j	ln_loop
	ln_sdone:
	fmuld	ft7,ft7,ft2
	fcvtdl	ft9,t0
	fmuld	ft9,ft9,ft4
	faddd	ft7,ft7,ft9
	fmvxd	a0,ft7
	ret
}
// Float-library compositions over the native FPU Ln/Exp (these compile to native RISC-V fmul/fdiv).
F64 Log2(F64 x)
{
  return Ln(x) / 0.6931471805599453;
}

F64 Log10(F64 x)
{
  return Ln(x) / 2.302585092994046;
}

F64 Pow10(F64 x)
{
  return Exp(x * 2.302585092994046);
}

F64 Pow(F64 a, F64 b)
{
  // Port of rt_pow: exact integer-exponent fast path, else Exp(b*Ln(a)).
  F64 r, base, bf;
  I64 n, neg, bi;
  if (b == 0.0)
    return 1.0;
  if (a == 0.0) {
    if (b > 0.0)
      return 0.0;
    else
      return 1.0 / (b - b);
  }
  bi = b;
  bf = bi;
  if (b == bf && b > -1024.0 && b < 1024.0) {
    n = bi;
    neg = 0;
    if (n < 0) {
      neg = 1;
      n = -n;
    }
    r = 1.0;
    base = a;
    while (n) {
      if (n & 1)
        r = r *base;
      base = base *base;
      n = n >> 1;
    }
    if (neg)
      return 1.0 / r;
    return r;
  }
  if (a < 0.0)
    return (a - a) / (a - a);
  // nan
  return Exp(b *Ln(a));
}
