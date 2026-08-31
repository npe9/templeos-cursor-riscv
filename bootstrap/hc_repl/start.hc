// start.hc -- bare-metal entry in HolyC asm{} (replaces crt0.S).
// QEMU -bios none jumps to blob offset 0; holyc-riscv places `_start` first when present.
// STACK: top of a 128M virt board; FPU: mstatus.FS=Initial so F64 Print works.
asm {
	_start::
	li	t0, 8192		// 1<<13 = mstatus.FS Initial
	csrs	0x300, t0
	lifp	sp, 0x87F00000
	call	main
	halt_spin:
	wfi
	j	halt_spin
}
