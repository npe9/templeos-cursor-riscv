// start.hc -- the low-level boot/startup, in NATIVE RISC-V assembly, editable and JIT-assembled
// to RAM. This is the RISC-V analog of start.s. Reset() runs it: Boot re-initializes M-mode
// (disables interrupts, sets FS/FPU, a fresh machine stack) and jumps to the REPL re-entry whose
// address Reset() left in the slot at 0x87000000. Edit any step -- e.g. the R boot marker or
// the stack address -- then Run("start.hc"); Reset();  and your edited boot code runs.
// CSRs are numeric: mstatus=0x300, mie=0x304, mip=0x344.
// Boot -- Boot()
// NAME
//   Boot - soft-reset entry (native RISC-V asm)
// SYNOPSIS
//   Boot();   // asm label Boot:: -- called by Reset(), not a HolyC frame
// DESCRIPTION
//   Machine startup / soft-reset vector. Clears mie/mip, sets sp and mstatus.FS, prints an
//   editable UART marker ('R'), then jalr to the re-entry address stored at MEM_FIXED by
//   Reset(). Edit this file and Run("start.hc"); Reset(); to live-patch boot.
// INPUTS
//   none (reads re-entry pointer from MEM_FIXED / 0x87000000)
// OUTPUTS
//   Does not return; jumps to REPL re-entry
// BUGS
//   Asm only -- Src/Man use this .hc unit. Asm immediates = MEM_UART / MEM_STACK / MEM_FIXED.
asm {
	Boot::
	csrw	0x304, zero	// mie = 0  (mask interrupts)
	csrw	0x344, zero	// mip = 0
	lifp	sp, 0x87F00000	// MEM_STACK — fresh machine stack (top of RAM on a 128M board)
	lifp	t0, 0x2000	// mstatus.FS = Initial -> FPU on
	csrs	0x300, t0
	lifp	a0, 0x10000000	// MEM_UART THR — print a boot marker you can edit:
	li	t0, 82		// R
	sb	t0, 0(a0)
	lifp	t0, 0x87000000	// MEM_FIXED — re-entry slot (Reset() stores the address here)
	ld	t1, 0(t0)
	jalr	zero, 0(t1)	// jump into the re-entry -- no return
}
