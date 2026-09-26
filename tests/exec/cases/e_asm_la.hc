// `la rd,label` — the address of a label inside an asm{} block, PC-relative.
//
// Before this, an asm{} block could not compute a label's address at all: `auipc` takes a raw
// 20-bit field and there was no pseudo that resolved a label, so there was no way to reach data
// or to take the address of code. That is one of the two things blocking
// Demo/Asm/AsmHelloWorld.HC's `MOV RSI,MY_WORLD_MSG` from being translated.
//
// Both directions are checked because the hi/lo split differs: a negative delta needs the +0x800
// carry correction, since addi's 12-bit immediate is sign-extended and hi20 must compensate.
// Verified by disassembly as well as by behaviour — a backward `la` over 8 bytes emits
// `auipc t0,0x0` then `addi t0,t0,-8`.
#include "/Kernel/Kernel_RV.PRJ"
asm {
LA_FWD::
	la	t0,laf_ok
	jr	t0
	li	a0,1
	ret
laf_ok:
	li	a0,90
	ret
}
asm {
LA_BACK::
	j	lab_go
lab_tgt:
	li	a0,77
	ret
lab_go:
	la	t0,lab_tgt
	jr	t0
	li	a0,2
	ret
}
_extern LA_FWD I64 LaFwd();
_extern LA_BACK I64 LaBack();
I64 main()
{
  RVKernelInit();
  return (LaFwd() == 90) * 1 + (LaBack() == 77) * 2;
  // 3
}
