/*When I was a kid with a Commodore 64, the 6502 chip had no multiply inst and this
is how we had to do it, except, I used more regs in this example.

Terry's lesson, on RISC-V. Shift-and-add is the same on any machine — it is what the
hardware multiplier does, unrolled where you can see it. What changes is everything
around it:

  x86                             RISC-V
  SHL1 AX / JNC (test carry)      srli to pull the bit out; there are no flags
  MOV AL,U8 SF_ARG1[RBP]          a0 already holds arg 1
  MUL (one inst, 128-bit in       mul (low half) + mulhu (high half) — two insts,
    RDX:RAX, an implicit pair)      two named registers, nothing implicit
  RET1 16 (callee pops args)      ret

The 64x64->128 case is the interesting one. x86 hides the second half of the product
in RDX because MUL has a fixed register pair; RISC-V makes you ask for it by name,
which is why RV64M has both mul and mulhu.
*/
asm {
//8bit * 8bit -> 16bit, the long way: for each of 8 bits of the multiplier, shift the
//running product left and add the multiplicand when that bit is set.
_MUL_BY_HAND_U8_U8_TO_U16::
	//a0 = n1, a1 = n2. Product accumulates in t3.
	andi	a0,a0,255
	andi	a1,a1,255
	li	t0,8		//bit counter
	li	t3,0		//product
	li	t4,128		//mask, walking down from bit 7 of n2
mul_loop:
	slli	t3,t3,1		//product <<= 1
	and	t2,a1,t4
	beqz	t2,mul_skip	//that bit of the multiplier is 0
	add	t3,t3,a0	//add the multiplicand in
mul_skip:
	srli	t4,t4,1
	addi	t0,t0,-1
	bnez	t0,mul_loop
	mv	a0,t3
	ret
}

asm {
//64bit * 64bit -> 128bit. Where x86 has one MUL leaving RDX:RAX, RV64M splits it:
//mul gives the low 64 bits, mulhu the high 64 of the UNSIGNED product.
_MUL_U64_U64_TO_U128::
	//a0 = n1, a1 = n2, a2 = &prod (U128: lo at +0, hi at +8).
	mul	t0,a0,a1
	mulhu	t1,a0,a1
	sd	t0,0(a2)
	sd	t1,8(a2)
	ret
}

//My convention is to put an underscore
//on C callable asm routines.
_extern _MUL_BY_HAND_U8_U8_TO_U16 U16 MulU8(U8 n1,U8 n2);

class U128
{
  U64 lo,hi;
};

_extern _MUL_U64_U64_TO_U128 U0 MulU64(I64 n1,I64 n2,U128 *_prod);

U0 MulByHand()
{
  U128 p;
  "2*7   =0x%X\n",MulU8(2,7);
  "100*10=0x%X\n",MulU8(100,10);

  MulU64(0x0123456789ABCDEF,0x1000001,&p);
  "0x0123466789ABCDEF*0x1000001=0x%016X%016X\n",p.hi,p.lo;
}

#ifndef RV_NO_DEMO_AUTORUN
MulByHand;
#endif
