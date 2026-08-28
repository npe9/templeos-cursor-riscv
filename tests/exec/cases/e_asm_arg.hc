// Native RISC-V asm in an asm{} block (RISC-V calling convention: args in a0..a7). GetA3 returns
// its 3rd argument (a2). The compiler assembles the RISC-V opcodes directly — no x86, no translation.
I64 GetA3(I64 a, I64 b, I64 c);
asm {
GetA3::
	mv	a0,a2
	ret
}
I64 main() { return GetA3(10, 20, 42); }   // 42 = 0x2a
