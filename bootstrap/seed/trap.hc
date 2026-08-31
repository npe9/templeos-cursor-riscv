// trap.hc -- thin TrapVec + TrapCtxSave/TrapCtxRestore asm; HolyC SetTrap/TrapInit/…
// Policy lives in C trapvec (slot 0x87000010). Asm is only GPR frame + mret.
// Do NOT call SetTrap/TrapInit at file load time (mtvec swap mid-boot is unsafe).
//
// Remaining asm (must stay asm):
//   TrapVec        — mtvec entry: `j TrapCtxSave` (not jal; keep trapped ra)
//   TrapCtxSave    — push 144-byte frame, call C trapvec via slot, jump TrapCtxRestore
//   TrapCtxRestore — pop frame, mret (also callable alone for unwind)
asm {
	TrapVec::
	j	TrapCtxSave

	TrapCtxSave::
	addi	sp, sp, -144
	sd	ra, 0(sp)
	sd	t0, 8(sp)
	sd	t1, 16(sp)
	sd	t2, 24(sp)
	sd	t3, 32(sp)
	sd	t4, 40(sp)
	sd	t5, 48(sp)
	sd	t6, 56(sp)
	sd	a0, 64(sp)
	sd	a1, 72(sp)
	sd	a2, 80(sp)
	sd	a3, 88(sp)
	sd	a4, 96(sp)
	sd	a5, 104(sp)
	sd	a6, 112(sp)
	sd	a7, 120(sp)
	sd	s0, 128(sp)
	mv	a0, sp
	lifp	t0, 0x87000010
	ld	t1, 0(t0)
	jalr	ra, 0(t1)
	j	TrapCtxRestore

	TrapCtxRestore::
	ld	ra, 0(sp)
	ld	t0, 8(sp)
	ld	t1, 16(sp)
	ld	t2, 24(sp)
	ld	t3, 32(sp)
	ld	t4, 40(sp)
	ld	t5, 48(sp)
	ld	t6, 56(sp)
	ld	a0, 64(sp)
	ld	a1, 72(sp)
	ld	a2, 80(sp)
	ld	a3, 88(sp)
	ld	a4, 96(sp)
	ld	a5, 104(sp)
	ld	a6, 112(sp)
	ld	a7, 120(sp)
	ld	s0, 128(sp)
	addi	sp, sp, 144
	mret
}

asm {
	HcEcall::
	ecall
	ret
	HcCsrsMieTimer::
	li	t0, 128
	csrs	0x304, t0
	ret
	HcCsrsMstatusMie::
	li	t0, 8
	csrs	0x300, t0
	ret
	HcCsrrwMtvec::
	csrw	0x305, a0
	fencei
	ret
}
// SetTrap -- SetTrap("name")
// NAME
//   SetTrap - route traps to the HolyC function of that name (resolved live by C trapvec)
// SYNOPSIS
//   U0 SetTrap(U8 *name);
// DESCRIPTION
//   Writes the handler name for C trapvec. Path: mtvec → TrapVec → TrapCtxSave →
//   trapvec → SetTrap target → TrapCtxRestore → mret. Pair with TrapInit and, for the
//   machine timer, TimerArm. Full CLINT walkthrough: Man("CLINT").
// INPUTS
//   name - HolyC function name, e.g. "OnTick" (after Run("timer.hc")) or "OnTrap"
// OUTPUTS
//   none (side effect: trap name buffer at host slot)
// BUGS
//   Do not call at file-load during boot (mtvec swap mid-boot is unsafe). Name must
//   exist as HTT_FUN when the trap fires.
U0 SetTrap(U8 *name)
{
  I64 buf, i;
  buf = *(I64 *)0x87001058;
  if (!buf)
    buf = 0x87001090;
  /* TRAP_NAME_FIXED fallback */
  i = 0;
  if (name) {
    while (i < 31 && *(U8 *)(name + i)) {
      *(U8 *)(buf + i) = *(U8 *)(name + i);
      i++;
    }
  }
  *(U8 *)(buf + i) = 0;
}
// TrapInit -- TrapInit()
// NAME
//   TrapInit - publish C trapvec, point mtvec at TrapVec, enable mstatus.MIE
// SYNOPSIS
//   U0 TrapInit();
// DESCRIPTION
//   Installs the machine trap path and enables global MIE (Man("MIE")). Does not
//   enable mie.MTIE by itself — TimerArm does that after programming mtimecmp.
//   Typical timer setup: SetTrap("OnTick"); TrapInit(); TimerArm(n); See Man("CLINT").
// INPUTS
//   none
// OUTPUTS
//   none
// BUGS
//   Unsafe if called while another trap path is mid-flight. Empty trap name defaults
//   to OnTrap.
U0 TrapInit()
{
  I64 vec, disp, fb, slot, p;
  disp = *(I64 *)0x87001060;
  *(I64 *)0x87000010 = disp;
  /* C trapvec */
  fb = *(I64 *)0x87001068;
  vec = FnAddr("TrapVec");
  if (!vec || vec < 0x80000000 || vec >= 0x88000000)
    vec = fb;
  if (!vec)
    return;
  HcCsrrwMtvec(vec);
  HcCsrsMstatusMie();
  slot = 0x87001058;
  p = *(I64 *)slot;
  if (p && !*(U8 *)p)
    SetTrap("OnTrap");
}

U0 Ecall()
{
  HcEcall();
}
// TimerArm -- TimerArm(interval)
// NAME
//   TimerArm - program CLINT mtimecmp and enable mie.MTIE
// SYNOPSIS
//   U0 TimerArm(I64 interval);
// DESCRIPTION
//   CLINT mtime/mtimecmp via MEM_* (this board profile): reads MEM_MTIME,
//   writes MEM_MTIMECMP = mtime+interval, then
//   sets mie.MTIE (Man("MTIE")). Requires TrapInit (mstatus.MIE) and
//   SetTrap("handler") first. Handler should re-arm mtimecmp (see OnTick in
//   timer.hc). Walkthrough + example: Man("CLINT").
// INPUTS
//   interval - mtime ticks until next interrupt (~10 MHz on typical virt-style
//   map; 1000000 ≈ 0.1 s)
// OUTPUTS
//   none (programs MMIO + CSR)
// BUGS
//   Uses MEM_MTIME / MEM_MTIMECMP from csr.hc (default profile). Does not
//   enable mstatus.MIE — call TrapInit. Soft IRQ (msip) not covered.
U0 TimerArm(I64 interval)
{
  I64 *mtime, *mtimecmp;
  mtime = MEM_MTIME;
  mtimecmp = MEM_MTIMECMP;
  *mtimecmp = *mtime + interval;
  HcCsrsMieTimer();
}

U0 Reset()
{
  I64 boot;
  boot = FnAddr("Boot");
  if (!boot) {
    UartStr("Reset: no Boot()\n");
    return;
  }
  *(I64 *)0x87000000 = *(I64 *)0x87001080;
  Call(boot);
}
// Break -- Break()
// NAME
//   Break - raise a catchable Ctrl-C interrupt (throw('Break'))
// SYNOPSIS
//   U0 Break();
// DESCRIPTION
//   Same exception code the UART REPL uses when Ctrl-C (ASCII 3) aborts an
//   evaluation: throw('Break'). Catch with try/catch and inspect Fs->except_ch.
//   At the prompt, Ctrl-C clears the draft line and prints Interrupted. During
//   a busy loop, Ctrl-C arrives via UART RX IRQ (PLIC) and aborts back to `>`
//   (or into an active try/catch).
// INPUTS
//   none
// OUTPUTS
//   none (throws)
// BUGS
//   Bare `wfi` with interrupts disabled (no mstatus.MIE / mie.MEIE) will not
//   see Ctrl-C until something else wakes the CPU. TrapInit arms UART RX+MEIE
//   so a normal `wfi` wakes on the Ctrl-C byte. Editors still receive ^C as a
//   keystroke (break is only armed around REPL eval).
U0 Break()
{
  throw('Break');
}

I64 OnTrap(I64 cause, I64 epc, I64 tval)
{
  return 0;
}
