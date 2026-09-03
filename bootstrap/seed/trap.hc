// trap.hc -- HolyC TrapVec + TrapDispatch (G2). Asm = GPR frame + mret only.
// Policy: HolyC TrapDispatch publishes MEM_TRAP_SNAP, runs SetTrap handler,
// fault-dumps, Ctrl-C Break. Legacy: if slot 0x87000010 holds C trapvec, defer.
// Do NOT call SetTrap/TrapInit at file load time (mtvec swap mid-boot is unsafe).
//
// Remaining asm:
//   TrapVec / TrapCtxSave / TrapCtxRestore — frame + call TrapDispatch + mret
//   ReplSetJmp / ReplLongJmp — soft abort to prompt
//   CSR helpers — mtvec / mie / mstatus / mepc / mcause / mtval
// hc_repl: include trap_vec_off.hc before this file. Legacy boot blob: 0 + C fallback vec.
#ifndef TRAP_VEC_OFF
#define TRAP_VEC_OFF 0
#endif
#define TRAP_DISPATCH_SLOT 0x87000010
#define TRAP_NAME_BUF_SLOT 0x87001058
#define TRAP_DISP_FN_SLOT 0x87001060
#define TRAP_FALLBACK_VEC_SLOT 0x87001068
#define TRAP_NAME_FIXED 0x87001090
#define REPL_JB_FIXED 0x87002000
#define TRAP_UART_IRQ 10
#define TRAP_EXCEPT_BREAK 0x6B61657242
#define TRAP_CH_CTRLC 3
U8 g_trap_name[32];
I64 g_trap_fn;
I64 g_break_armed;
I64 g_break_pending;
I64 g_break_interactive;
I64 g_repl_jb[16];
I64 g_repl_jb_ok;
I64 g_repl_setjmp_rc;
I64 g_trap_installed;
I64 g_trap_vec;
I64 pc;
#define _RIP pc
// Optional: hc_repl sets this to resolve JIT names (JitFind). Legacy C path uses HashFind.
I64 (*TrapResolveHook)(U8 *name);
// Optional: product path (no host RX slots) — soft-ring drain + Ctrl-C take.
U0 (*TrapUartSoftDrain)();
I64 FnAddr(U8 *name);
// OnTrap must be defined before TrapResolve's `&OnTrap` (same-unit forward
// decls have no exe_addr/entry_label yet → "Function declared but not defined").
I64 OnTrap(I64 cause, I64 epc, I64 tval)
{
  pc = epc;
  return 0;
}

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
	// Do NOT use asm `call` — host expands it to IC_CALL + eval-stack push
	// (addi sp,-8; sd a0) which corrupts this frame and wedges TrapInit.
	// Do NOT use lifp for 0x87001060 — values <2^55 mis-materialize (jalr 0).
	// Build TRAP_DISP_FN_SLOT (0x87001060) like start.hc stack (lui+slli+addi).
	lui	t6, 0x10E00
	slli	t6, t6, 3
	lui	t5, 0x1
	addi	t5, t5, 0x60
	add	t6, t6, t5
	ld	t6, 0(t6)
	jalr	ra, 0(t6)
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
	HcCsrsMieExt::
	li	t0, 2048
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
	HcCsrrMcause::
	csrr	a0, 0x342
	ret
	HcCsrrMepc::
	csrr	a0, 0x341
	ret
	HcCsrrMtval::
	csrr	a0, 0x343
	ret
	HcCsrwMepc::
	csrw	0x341, a0
	ret
	TrapBareMtvec::
	li	t0, 8
	csrc	0x300, t0
	csrw	0x304, zero
	csrw	0x305, a0
	fencei
	ret
	ReplSetJmp::
	sd	ra, 0(a0)
	sd	sp, 8(a0)
	sd	s0, 16(a0)
	sd	s1, 24(a0)
	sd	s2, 32(a0)
	sd	s3, 40(a0)
	sd	s4, 48(a0)
	sd	s5, 56(a0)
	sd	s6, 64(a0)
	sd	s7, 72(a0)
	sd	s8, 80(a0)
	sd	s9, 88(a0)
	sd	s10, 96(a0)
	sd	s11, 104(a0)
	li	a0, 0
	ret
	ReplLongJmp::
	ld	ra, 0(a0)
	ld	sp, 8(a0)
	ld	s0, 16(a0)
	ld	s1, 24(a0)
	ld	s2, 32(a0)
	ld	s3, 40(a0)
	ld	s4, 48(a0)
	ld	s5, 56(a0)
	ld	s6, 64(a0)
	ld	s7, 72(a0)
	ld	s8, 80(a0)
	ld	s9, 88(a0)
	ld	s10, 96(a0)
	ld	s11, 104(a0)
	li	a0, 1
	ret
	FaultDo::
	unimp
	ret
}
// Soft abort: asm-only so longjmp returns straight to ReplLoop (no HolyC frame).
// JB at REPL_JB_FIXED (outside SoftDbg 4KiB wipe @ 0x87001000).
asm {
	ReplDoSetJmpHc::
	lui	t6, 0x10E00
	slli	t6, t6, 3
	lui	t5, 0x2
	add	a0, t6, t5
	sd	ra, 0(a0)
	sd	sp, 8(a0)
	sd	s0, 16(a0)
	sd	s1, 24(a0)
	sd	s2, 32(a0)
	sd	s3, 40(a0)
	sd	s4, 48(a0)
	sd	s5, 56(a0)
	sd	s6, 64(a0)
	sd	s7, 72(a0)
	sd	s8, 80(a0)
	sd	s9, 88(a0)
	sd	s10, 96(a0)
	sd	s11, 104(a0)
	li	a0, 0
	ret
	ReplDoLongJmpHc::
	lui	t6, 0x10E00
	slli	t6, t6, 3
	lui	t5, 0x2
	add	a0, t6, t5
	ld	ra, 0(a0)
	ld	sp, 8(a0)
	ld	s0, 16(a0)
	ld	s1, 24(a0)
	ld	s2, 32(a0)
	ld	s3, 40(a0)
	ld	s4, 48(a0)
	ld	s5, 56(a0)
	ld	s6, 64(a0)
	ld	s7, 72(a0)
	ld	s8, 80(a0)
	ld	s9, 88(a0)
	ld	s10, 96(a0)
	ld	s11, 104(a0)
	li	a0, 1
	ret
}

I64 TrapNameEq(U8 *a, U8 *b)
{
  if (!a || !b)
    return 0;
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return !*a && !*b;
}

I64 TrapCall0(I64 fn)
{
  I64 (*f)();
  if (!fn)
    return 0;
  f = fn;
  return f();
}

I64 TrapCall3(I64 fn, I64 a, I64 b, I64 c)
{
  I64 (*f)(I64, I64, I64);
  if (!fn)
    return 0;
  f = fn;
  return f(a, b, c);
}

U0 TrapPutHex(I64 v)
{
  I64 i, d;
  U8 c;
  UartStr("0x");
  i = 60;
  while (i >= 0) {
    d = (v >> i) & 15;
    if (d < 10)
      c = '0' + d;
    else
      c = 'a' + d - 10;
    PutCh(c);
    i = i - 4;
  }
}

U8 *TrapCauseName(I64 cause)
{
  if (cause < 0) {
    cause = cause & 0xFF;
    if (cause == 3)
      return "software interrupt";
    if (cause == 7)
      return "timer interrupt";
    if (cause == 11)
      return "external interrupt";
    return "interrupt";
  }
  if (cause == 0)
    return "instruction misaligned";
  if (cause == 1)
    return "instruction access fault";
  if (cause == 2)
    return "illegal instruction";
  if (cause == 3)
    return "breakpoint";
  if (cause == 4)
    return "load misaligned";
  if (cause == 5)
    return "load access fault (bad address)";
  if (cause == 6)
    return "store misaligned";
  if (cause == 7)
    return "store access fault (bad address)";
  if (cause == 8 || cause == 9 || cause == 11)
    return "ecall";
  return "trap";
}

I64 TrapResolve(U8 *name)
{
  I64 a;
  if (!name || !*name)
    return 0;
  if (TrapResolveHook) {
    a = TrapResolveHook(name);
    if (a)
      return a;
  }
  a = FnAddr(name);
  if (a)
    return a;
  if (TrapNameEq(name, "OnTrap"))
    return &OnTrap;
  return 0;
}

U0 TrapNameStore(U8 *name)
{
  I64 i, buf;
  i = 0;
  if (name) {
    while (i < 31 && *(U8 *)(name + i)) {
      g_trap_name[i] = *(U8 *)(name + i);
      i++;
    }
  }
  g_trap_name[i] = 0;
  buf = *(I64 *)TRAP_NAME_BUF_SLOT;
  if (!buf || buf < 0x80000000 || buf >= 0x88000000)
    buf = TRAP_NAME_FIXED;
  i = 0;
  while (i < 32) {
    *(U8 *)(buf + i) = g_trap_name[i];
    i++;
  }
}

U0 TrapSnapPublish(I64 *frame, I64 cause, I64 epc, I64 tval)
{
  I64 k;
  for (k = 0; k < 16; k++)
    *(I64 *)(MEM_TRAP_SNAP + k * 8) = frame[k];
  *(I64 *)(MEM_TRAP_SNAP + 16 * 8) = (I64)frame + 144;
  *(I64 *)(MEM_TRAP_SNAP + 17 * 8) = frame[16];
  *(I64 *)(MEM_TRAP_SNAP + 18 * 8) = cause;
  *(I64 *)(MEM_TRAP_SNAP + 19 * 8) = epc;
  *(I64 *)(MEM_TRAP_SNAP + 20 * 8) = tval;
  pc = epc;
}

U0 TrapUartHwDrain()
{
  I64 ch, n, rx, rhp, rtp, cap, rh, rt, skip;
  PUSHFD;
  CLI;
  rx = *(I64 *)0x87001020;
  rhp = *(I64 *)0x87001028;
  rtp = *(I64 *)0x87001030;
  cap = *(I64 *)0x87001038;
  if (rx && rhp && rtp && cap >= 2) {
    while (*(U8 *)(MEM_UART + 5) & 1) {
      ch = *(U8 *)MEM_UART;
      if (UartFcIsCtrl(ch)) {
        UartFcNote(ch);
      } else {
        skip = 0;
        if (ch == TRAP_CH_CTRLC) {
          g_break_pending = 1;
          if (g_break_armed)
            skip = 1;
        }
        if (!skip) {
          rh = *(I64 *)rhp;
          rt = *(I64 *)rtp;
          n = (rh + 1) & (cap - 1);
          if (n == rt)
            break;
          *(U8 *)(rx + rh) = ch;
          *(I64 *)rhp = n;
        }
      }
    }
  } else if (TrapUartSoftDrain) {
    TrapUartSoftDrain();
  } else {
    while (*(U8 *)(MEM_UART + 5) & 1) {
      ch = *(U8 *)MEM_UART;
      if (UartFcIsCtrl(ch))
        UartFcNote(ch);
      else if (ch == TRAP_CH_CTRLC)
        g_break_pending = 1;
    }
  }
  POPFD;
}

I64 TrapPlicServiceUart()
{
  I64 claim, irq;
  claim = MEM_PLIC + MEM_PLIC_CLAIM_OFF;
  irq = *(U32 *)claim;
  if (irq == TRAP_UART_IRQ)
    TrapUartHwDrain();
  if (irq)
    *(U32 *)claim = irq;
  return irq;
}

U0 UartBreakIrqInit()
{
  *(U8 *)(MEM_UART + 1) = 1;
  *(U32 *)(MEM_PLIC + TRAP_UART_IRQ * 4) = 1;
  *(U32 *)(MEM_PLIC + MEM_PLIC_ENABLE_OFF) = *(U32 *)(MEM_PLIC + MEM_PLIC_ENABLE_OFF) | (1 << TRAP_UART_IRQ);
  *(U32 *)(MEM_PLIC + MEM_PLIC_THRESHOLD_OFF) = 0;
  HcCsrsMieExt();
}

U0 BreakArm()
{
  TrapInitOnce();
  g_break_pending = 0;
  TrapUartHwDrain();
  g_break_armed = 1;
  UartBreakIrqInit();
  HcCsrsMstatusMie();
  *(I64 *)MEM_MTIMECMP = *(I64 *)MEM_MTIME + 100000;
  HcCsrsMieTimer();
}

U0 BreakDisarm()
{
  g_break_armed = 0;
  g_break_pending = 0;
  *(I64 *)MEM_MTIMECMP = -1;
}

U0 TrapFaultRecover()
{
  BreakDisarm();
  UartStr("-- eval aborted, back to the REPL --\n");
  if (g_repl_jb_ok)
    ReplDoLongJmpHc();
  while (TRUE)
    HLT;
}

U0 TrapBreakRaise()
{
  BreakDisarm();
  UartStr("\nInterrupted\n");
  if (g_repl_jb_ok)
    ReplDoLongJmpHc();
  while (TRUE)
    HLT;
}

U0 TrapFaultDump(I64 *frame, I64 cause, I64 epc, I64 tval)
{
  UartStr("\n*** FAULT: ");
  UartStr(TrapCauseName(cause));
  UartStr("\n  cause=");
  TrapPutHex(cause);
  UartStr("  tval=");
  TrapPutHex(tval);
  UartStr("\n  pc  = ");
  TrapPutHex(epc);
  UartStr("\n  ra  = ");
  TrapPutHex(frame[0]);
  UartStr("\n  (TrapDump; U(pc-16); for dig-down)\n");
}

U0 TrapDispatch(I64 *frame)
{
  I64 cause, epc, tval, resume, slot, ext_irq, skip_hc, fn;
  I64 (*cpol)(I64 *);
  cause = HcCsrrMcause();
  epc = HcCsrrMepc();
  tval = HcCsrrMtval();
  if (!g_break_interactive && cause < 0) {
    if ((cause & 0xFF) == 7)
      *(I64 *)MEM_MTIMECMP = -1;
    else if ((cause & 0xFF) == 11)
      TrapPlicServiceUart();
    HcCsrwMepc(epc);
    return;
  }
  slot = *(I64 *)TRAP_DISPATCH_SLOT;
  if (slot && slot != &TrapDispatch && slot >= 0x80000000 && slot < 0x88000000) {
    cpol = slot;
    cpol(frame);
    return;
  }
  TrapSnapPublish(frame, cause, epc, tval);
  ext_irq = -1;
  if (cause < 0 && (cause & 0xFF) == 11)
    ext_irq = TrapPlicServiceUart();
  if (!g_break_armed && cause < 0 && (cause & 0xFF) == 7) {
    *(I64 *)MEM_MTIMECMP = -1;
    HcCsrwMepc(epc);
    return;
  }
  if (g_break_armed && cause < 0 && (cause & 0xFF) == 7) {
    TrapUartHwDrain();
    *(I64 *)MEM_MTIMECMP = *(I64 *)MEM_MTIME + 100000;
    if (g_break_pending) {
      HcCsrwMepc(&TrapBreakRaise);
      return;
    }
    HcCsrwMepc(epc);
    return;
  }
  if (g_break_armed)
    TrapUartHwDrain();
  resume = 0;
  skip_hc = ext_irq == TRAP_UART_IRQ;
  fn = 0;
  if (!skip_hc) {
    fn = g_trap_fn;
    if (!fn && g_trap_name[0])
      fn = TrapResolve(g_trap_name);
  }
  if (fn)
    resume = TrapCall3(fn, cause, epc, tval);
  if (g_break_armed && g_break_pending) {
    HcCsrwMepc(&TrapBreakRaise);
    return;
  }
  if (!resume) {
    if (cause < 0)
      resume = epc;
    else if (cause == 8 || cause == 9 || cause == 11)
      resume = epc + 4;
    else {
      TrapFaultDump(frame, cause, epc, tval);
      if (g_repl_jb_ok)
        resume = &TrapFaultRecover;
      else
        resume = epc + 4;
    }
  }
  HcCsrwMepc(resume);
}

U0 SetTrap(U8 *name)
{
  // Legacy boot blob (TRAP_VEC_OFF 0): C already owns mtvec + TRAP_DISP_FN_SLOT.
  // TrapInitOnce→TrapInit rewrites slots / can instruction-access-fault; name-only is enough.
  if (!TRAP_VEC_OFF) {
    TrapNameStore(name);
    g_trap_fn = 0;
    g_break_interactive = 1;
    return;
  }
  TrapInitOnce();
  TrapNameStore(name);
  g_trap_fn = 0;
}

U0 SetTrapFn(I64 fn)
{
  g_trap_fn = fn;
  g_trap_name[0] = 0;
}

U0 TrapInitOnce()
{
  if (g_trap_installed)
    return;
  g_trap_installed = 1;
  TrapInit();
}

U0 TrapVecAddrFix()
{
  I64 off;
  off = TRAP_VEC_OFF;
  if (off)
    g_trap_vec = 0x80000000 + off;
}

U0 TrapInit()
{
  I64 vec, disp;
  *(I64 *)TRAP_NAME_BUF_SLOT = TRAP_NAME_FIXED;
  *(I64 *)MEM_MTIMECMP = -1;
  disp = *(I64 *)TRAP_DISP_FN_SLOT;
  if (disp && disp != &TrapDispatch && disp >= 0x80000000 && disp < 0x88000000)
    *(I64 *)TRAP_DISPATCH_SLOT = disp;
  else {
    *(I64 *)TRAP_DISPATCH_SLOT = 0;
    *(I64 *)TRAP_DISP_FN_SLOT = &TrapDispatch;
  }
  if (!g_trap_vec)
    TrapVecAddrFix();
  vec = g_trap_vec;
  if (!vec || vec < 0x80000000 || vec >= 0x88000000)
    vec = *(I64 *)TRAP_FALLBACK_VEC_SLOT;
  if (!vec)
    return;
  // Rewrite mtvec only when AOT published a real TrapVec offset (hc_repl).
  // Legacy boot blob keeps TRAP_VEC_OFF 0; C already installed mtvec.
  // Do NOT gate on FnAddr("TrapBareMtvec") — asm labels are not in the JIT
  // table, so that check skipped the install and Fault hung on default mtvec=0.
  if (TRAP_VEC_OFF) {
    CLI;
    TrapBareMtvec(vec);
  }
  if (!g_trap_name[0] && !g_trap_fn)
    SetTrap("CrashOnTrap");
  g_break_interactive = 1;
}

U0 Ecall()
{
  TrapInitOnce();
  HcEcall();
}

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
  boot = TrapResolve("Boot");
  if (!boot)
    boot = FnAddr("Boot");
  if (!boot) {
    UartStr("Reset: no Boot()\n");
    return;
  }
  *(I64 *)0x87000000 = *(I64 *)0x87001080;
  TrapCall0(boot);
}

U0 HardReset()
{
  U32 *t;
  t = MEM_TEST;
  *t = 0x7777;
  while (TRUE)
    HLT;
}

U0 Halt()
{
  while (TRUE)
    HLT;
}

U0 Fault()
{
  TrapInitOnce();
  FaultDo();
}

U0 Break()
{
  TrapInitOnce();
  if (__try_top)
    throw(TRAP_EXCEPT_BREAK);
  BreakDisarm();
  UartStr("\nInterrupted\n");
  if (g_repl_jb_ok)
    ReplDoLongJmpHc();
  throw(TRAP_EXCEPT_BREAK);
}
