// start.hc -- the low-level boot/startup, in NATIVE RISC-V assembly, editable and JIT-assembled
// to RAM. This is the RISC-V analog of start.s. Reset() runs it: Boot re-initializes M-mode
// (disables interrupts, sets FS/FPU, a fresh machine stack) and jumps to the REPL re-entry whose
// address Reset() left in the slot at 0x87000000. Edit any step -- e.g. the 'R' boot marker or
// the stack address -- then Run("start.hc"); Reset();  and your edited boot code runs.
// CSRs are numeric: mstatus=0x300, mie=0x304, mip=0x344.
asm {
Boot::
	csrw	0x304, zero	// mie = 0  (mask interrupts)
	csrw	0x344, zero	// mip = 0
	lifp	sp, 0x87F00000	// fresh machine stack (top of RAM on a 128M board)
	lifp	t0, 0x2000	// mstatus.FS = Initial -> FPU on
	csrs	0x300, t0
	lifp	a0, 0x10000000	// UART THR -- print a boot marker you can edit:
	li	t0, 82		// 'R'
	sb	t0, 0(a0)
	lifp	t0, 0x87000000	// re-entry slot (Reset() stores the address here)
	ld	t1, 0(t0)
	jalr	zero, 0(t1)	// jump into the re-entry -- no return
}
