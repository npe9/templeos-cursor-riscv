// start.hc -- bare-metal entry in HolyC asm{} (replaces crt0.S).
// QEMU -bios none jumps to blob offset 0; holyc-riscv places `_start` first when present.
// STACK: top of a 128M virt board; FPU: mstatus.FS=Initial so F64 Print works.
//
// Far `call main` from asm can become a null GOT. Thin main() + BootContinue live
// here next to _start; ReplMain() is the late body in repl.hc (IC_CALL relocates).
//
// RV64: `lui sp, 0x87F00` sign-extends (bit31 set) → 0xffffffff87f00000 and the
// first sd faults to mtvec=0 (silent hang). Build 0x87F00000 via lui+slli.
// Do NOT use `m=&main; m();` — that codegen imbalances sp / jalr x0 and wedges boot.
I64 ReplMain();
I64 main()
{
  return ReplMain();
}

U0 BootContinue()
{
  main();
}

asm {
	_start::
	li	t0, 8192		// 1<<13 = mstatus.FS Initial
	csrs	0x300, t0
	lui	sp, 0x10FE0		// 0x10FE0000
	slli	sp, sp, 3		// 0x87F00000 = MEM_STACK
	call	BootContinue
	halt_spin:
	wfi
	j	halt_spin
}
