// Regression for x86->RISC-V asm translation: a bare x86 asm function using the x86 stack calling
// convention (args at SF_ARGn[RBP]) is translated to RISC-V with a synthesized prologue that spills
// a0..a7 into the SF_ARG slots. GetA3 returns its 3rd argument.
I64 GetA3(I64 a, I64 b, I64 c);
asm {
GetA3::
	PUSH	RBP
	MOV	RBP,RSP
	MOV	RAX,U64 SF_ARG3[RBP]
	POP	RBP
	RET1	24
}
I64 main() { return GetA3(10, 20, 42); }   // 42 = 0x2a
