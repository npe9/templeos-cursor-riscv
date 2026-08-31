// Unlabeled inline asm{} must emit and run (not silent no-op).
// TempleOS-style: asm mid-function leaves a0 as the RV return register.
// Imm subtract is addi with negative imm (no subi pseudo).
I64 AsmAdd3(I64 x)
{
  asm {
	addi a0,a0,3
  }
}

I64 AsmS2Probe()
{
  asm {
	li s2,0
	addi s2,s2,3
	mv a0,s2
  }
}

I64 AsmA7Probe()
{
  asm {
	li a7,20
	addi a7,a7,-4
	mv a0,a7
  }
}
// Semicolon separators + li + R-type sub (gas-style one-liners).
I64 AsmSemiSub()
{
  asm {
	li s2,1; li a7,4; sub a7,a7,s2; mv a0,a7
  }
}

I64 main()
{
  return AsmAdd3(39) + AsmS2Probe() + AsmA7Probe() + AsmSemiSub();
  // 42+3+16+3 = 64
}
