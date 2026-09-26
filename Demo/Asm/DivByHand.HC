/*Restoring division, one bit at a time — what you do when the chip has no divide
instruction. The algorithm is Terry's; the assembly is RISC-V because that is the
machine this runs on.

The x86 original, for comparison:

	XOR	RDX,RDX		//remainder = 0
	MOV	RCX,64		//64 bits
	MOV	RAX,SF_ARG1[RBP]
	MOV	RBX,SF_ARG2[RBP]
  @@1:	SHL1	RAX		//dividend <<= 1, MSB -> carry
	RCL1	RDX		//remainder = remainder<<1 | carry
	CMP	RBX,RDX
	JA	@@2		//divisor > remainder: bit stays 0
	INC	RAX		//set the quotient bit
	SUB	RDX,RBX
  @@2:	LOOP	@@1

Two differences worth seeing. x86 shifts the top bit of the dividend into the CARRY
FLAG and rotates it into the remainder; RISC-V has no flags, so the bit is extracted
with srli and OR'd in by hand — one extra instruction and nothing hidden. And the
arguments arrive in a0/a1 rather than on the stack at SF_ARG1[RBP], so there is no
frame to build and no RET1 to unwind it.
*/

asm {
_DIV_U64_BY_U64::
	//a0 = dividend (becomes the quotient in place), a1 = divisor.
	li	t0,64		//bit counter
	li	t1,0		//remainder
div_loop:
	srli	t2,a0,63	//the bit leaving the dividend
	slli	a0,a0,1
	slli	t1,t1,1
	or	t1,t1,t2	//remainder = remainder<<1 | bit
	bltu	t1,a1,div_skip	//remainder < divisor: quotient bit stays 0
	sub	t1,t1,a1
	addi	a0,a0,1		//set the quotient bit
div_skip:
	addi	t0,t0,-1
	bnez	t0,div_loop
	ret
}

_extern _DIV_U64_BY_U64 I64 DivU64ByU64(I64 dividend,I64 divisor);

#ifndef RV_NO_DEMO_AUTORUN
"123456/10=%d\n",DivU64ByU64(123456,10);
#endif
