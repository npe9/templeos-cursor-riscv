// debug.hc -- HolyC debugger: ebreak breakpoints, soft watch, stack walk, step-over.
// Dig-down: docs/DEBUGGER.md. Soft Regs snap+restore: csr.hc RegsSnapStub → MEM_REGS_SNAP
// (same pattern as legacy C stub; do not fork a second clobbering Regs). Hw*/Sdtrig
// (hwdbg.hc) stay additive — leave Watch/Step soft paths here unless Hw* wraps them.
// Trap freeze: MEM_TRAP_SNAP / DbgReg.
//
// The fault freeze has TWO views (published together by trap.hc TrapSnapPublish):
//
//  1. Legacy word indices (U64) at MEM_TRAP_SNAP — read with DbgReg(n):
//     DBG_I_RA=0  DBG_I_T0..T6=1..7  DBG_I_A0..A7=8..15  DBG_I_SP=16  DBG_I_FP=17
//     DBG_I_CAUSE=18  DBG_I_EPC=19  DBG_I_TVAL=20  DBG_I_MSTATUS=21
//     (mstatus is the POST-trap value: MIE is clear, MPP/MPIE hold the trapped state.)
//  2. Canonical x0..x31 at TRAP_SNAP_X (0x87000400, above MEM_REGS_SNAP) — DbgX(n). This is
//     every GPR including s1-s11/gp/tp, which view 1 has no slots for, and it matches
//     MEM_REGS_SNAP's layout so one formatter serves both freeze and live snap.
#define DBG_I_RA 0
#define DBG_I_T0 1
#define DBG_I_A0 8
#define DBG_I_SP 16
#define DBG_I_FP 17
#define DBG_I_CAUSE 18
#define DBG_I_EPC 19
#define DBG_I_TVAL 20
#define DBG_I_MSTATUS 21
#define DBG_I_NSLOT 22
I64 DbgAddr[16], DbgSaved[16], DbgActive[16];
I64 WatchAddr[8], WatchLen[8], WatchLast[8], WatchActive[8];
I64 DbgStopOnHit;
// 0=dump+continue (default); 1=dump+abort eval to prompt
I64 WatchDoBreak;
// 0=report only; 1=abort eval on soft watch hit from DbgTrap
I64 DbgWatchHit;
I64 DbgStepAddr;
// last Step-armed address (for Bps listing)
asm {
	FenceI::
	fencei
	ret
	DbgLiveS0::
	mv	a0, s0
	ret
	DbgLiveRa::
	mv	a0, ra
	ret
	DbgLiveSp::
	mv	a0, sp
	ret
}

I64 DbgInRam(I64 a)
{
  return a >= 0x80000000 && a < 0x88000000;
}
// Decode JIT prologue `addi sp,sp,-N` at entry → frame size N (0 if not the simple form).
I64 DbgFrameSize(I64 entry)
{
  U32 w;
  I64 imm;
  if (!DbgInRam(entry))
    return 0;
  w = *(U32 *)entry;
  if ((w & 0xFFFFF) != 0x10113)
    return 0;
  imm = (w >> 20) & 0xFFF;
  if (imm & 0x800)
    imm = imm - 0x1000;
  if (imm < 0)
    return -imm;
  return 0;
}

I64 DbgPeekWatch(I64 addr, I64 len)
{
  // Fold up to 8 bytes into one I64 for compare (soft watch limit).
  I64 v, i, n;
  v = 0;
  n = len;
  if (n > 8)
    n = 8;
  if (n <= 0)
    n = 8;
  for (i = 0; i < n; i++)
    v = v | ((*(U8 *)(addr + i) & 0xFF) << (i * 8));
  return v;
}
// DbgReg -- DbgReg(n)
// NAME
//   DbgReg - read trapped register n from MEM_TRAP_SNAP (last exception freeze)
// SYNOPSIS
//   I64 DbgReg(I64 n);
// DESCRIPTION
//   Peeks word n of the fixed trap publish block (not live GPRs — use Regs/Reg for stub-entry
//   snap+restore). Indices: 0=ra, 1..7=t0..t6, 8..15=a0..a7, 16=sp, 17=s0/fp,
//   18=mcause, 19=mepc, 20=mtval (when trapvec published them).
// EXAMPLES
//   DbgReg(DBG_I_A0);  DbgSp;  DbgFP;  TrapDump;
// SEE ALSO
//   DbgTrap  Bp  TrapDump  Regs  Bt  GetMepc
// BUGS
//   Stale until a trap has published.
I64 DbgReg(I64 n)
{
  return *(I64 *)(MEM_TRAP_SNAP + n * 8);
}

// TrapFrameProbe -- TrapFrameProbe()
// NAME
//   TrapFrameProbe - fault with known values in every callee-saved register (frame self-test)
// SYNOPSIS
//   U0 TrapFrameProbe();
// DESCRIPTION
//   Plants markers in s1/s2/s5/s11/gp/tp, faults on a load from address 4, then restores them.
//   The fault's CrashDump prints those registers, which only exist in the canonical x view —
//   so this is what proves TrapCtxSave/TrapSnapPublish really widened. `go` resumes after the
//   faulting load, so the restores run and the caller's registers survive.
// EXAMPLES
//   TrapFrameProbe;   // expect s1=0x51 s2=0x52 ... gp=0x63 tp=0x64 in the dump, then: go
// SEE ALSO
//   DbgX  TrapDump  CrashDump  Fault
U0 TrapFrameProbe()
{
  asm {
	addi	sp, sp, -64
	sd	s1, 0(sp)
	sd	s2, 8(sp)
	sd	s5, 16(sp)
	sd	s11, 24(sp)
	sd	gp, 32(sp)
	sd	tp, 40(sp)
	li	s1, 0x51
	li	s2, 0x52
	li	s5, 0x55
	li	s11, 0x5B
	li	gp, 0x63
	li	tp, 0x64
	li	t0, 4
	ld	t1, 0(t0)
	ld	s1, 0(sp)
	ld	s2, 8(sp)
	ld	s5, 16(sp)
	ld	s11, 24(sp)
	ld	gp, 32(sp)
	ld	tp, 40(sp)
	addi	sp, sp, 64
  }
}

// TrapFrameCheck -- TrapFrameCheck()
// NAME
//   TrapFrameCheck - verify the freeze survives a live Bt (scratch-collision regression)
// SYNOPSIS
//   U0 TrapFrameCheck();
// DESCRIPTION
//   Runs Bt (whose live path writes ra/s0 to the 0x87000200 scratch) and then prints whether
//   x0 is still 0 and x1 still equals the legacy ra slot. Both fail if the canonical array is
//   ever moved back on top of that scratch.
// SEE ALSO
//   TrapFrameProbe  DbgX  TrapDump
U0 TrapFrameCheck()
{
  Bt;
  "TFCHK x0z=%d x1ra=%d s1=0x%X gp=0x%X\n", DbgX(0) == 0, DbgX(1) == DbgRa(), DbgX(9), DbgX(3);
}

// DbgX -- DbgX(n)
// NAME
//   DbgX - read trapped x-register n (0..31) from the canonical freeze array
// SYNOPSIS
//   I64 DbgX(I64 n);
// DESCRIPTION
//   TRAP_SNAP_X + n*8. Covers every GPR — including s1-s11, gp and tp, which the legacy
//   DbgReg slots do not carry. x0 reads 0; x2 is the sp at the moment of the trap.
// EXAMPLES
//   DbgX(9);  // s1
//   DbgX(2);  // sp
// SEE ALSO
//   DbgReg  TrapDump  Regs  Reg
// BUGS
//   Stale until a trap has published.
// s-register numbering is split: s0=x8, s1=x9, s2..s11=x18..x27.
I64 DbgXSNum(I64 n)
{
  if (n == 8)
    return 0;
  if (n == 9)
    return 1;
  return n - 16;
}

I64 DbgXSNext(I64 n)
{
  if (n == 9)
    return 18;
  return n + 1;
}

I64 DbgX(I64 n)
{
  if (n < 0 || n > 31)
    return 0;
  return *(I64 *)(TRAP_SNAP_X + n * 8);
}

I64 DbgRa()
{
  return DbgReg(DBG_I_RA);
}

I64 DbgSp()
{
  return DbgReg(DBG_I_SP);
}

I64 DbgFP()
{
  return DbgReg(DBG_I_FP);
}

U0 DbgSymLine(I64 addr)
{
  U8 *nm;
  I64 base;
  nm = SymName(addr);
  if (nm) {
    base = SymBase(addr);
    "  %s+0x%X", nm, addr - base;
  }
}
// BtSnapFresh -- sync-exception epc in MEM_TRAP_SNAP, or 0.
// Not boot-seeded pc=U; not IRQ-only leftovers (cause < 0).
I64 BtSnapFresh()
{
  I64 cause, epc;
  cause = DbgReg(DBG_I_CAUSE);
  epc = DbgReg(DBG_I_EPC);
  if (cause < 0 || cause > 15)
    return 0;
  if (!epc || !DbgInRam(epc))
    return 0;
  return epc;
}
// BtWalk -- walk FP chain from (pc,s0), symbolize each frame.
// trap_entry: 1 when start_pc is a sync-trap PC at function entry (use snap ra).
U0 BtWalk(I64 start_pc, I64 s0, I64 trap_entry)
{
  I64 i, cur, ra, ps0, N, sz, entry, at_entry;
  U8 *nm;
  cur = start_pc;
  UartStr("  stack:\n");
  for (i = 0; i < 16; i++) {
    "    #%d 0x%X", i, cur;
    DbgSymLine(cur);
    "\n";
    entry = SymBase(cur);
    if (!entry || !DbgInRam(s0))
      break;
    nm = SymName(cur);
    sz = 0;
    at_entry = cur == entry;
    // ebreak/Bp at function entry: prologue has not run — s0 is still the caller's.
    // Using the callee's JIT frame size here reads ra/ps0 swapped (next "pc" == fp).
    if (nm && !at_entry)
      sz = FnSize(nm);
    if (i == 0 && at_entry && trap_entry) {
      // Next PC is trapped ra (MEM_TRAP_SNAP), not *(s0-8) (caller's saved ra).
      ra = DbgReg(DBG_I_RA);
      if (DbgInRam(s0 - 16))
        ps0 = *(I64 *)(s0 - 16);
      else
        ps0 = s0;
    } else if (sz > 0) {
      N = DbgFrameSize(entry);
      if (!N || !DbgInRam(s0 - N))
        break;
      ra = *(I64 *)(s0 - N);
      ps0 = *(I64 *)(s0 - N + 8);
    } else {
      if (!DbgInRam(s0 - 16))
        break;
      ra = *(I64 *)(s0 - 8);
      ps0 = *(I64 *)(s0 - 16);
    }
    if (!DbgInRam(ra) || ra == cur)
      break;
    cur = ra;
    s0 = ps0;
  }
}
// Bt -- Bt()
// NAME
//   Bt - symbolic backtrace (trap freeze or live s0/ra)
// SYNOPSIS
//   U0 Bt();
// DESCRIPTION
//   Walks the FP chain like StkRep: JIT frames via entry addi sp,-N; C frames via
//   gcc ra@s0-8 / s0@s0-16. Prefers MEM_TRAP_SNAP after a sync trap/Bp (cause+epc);
//   ignores boot-seeded `pc` (=U) and IRQ-only fp leftovers. Else live s0/ra.
// EXAMPLES
//   Bp(&Foo); Foo(1); Bt;
//   StkRep;
// SEE ALSO
//   StkRep  DbgFP  DbgSp  TrapDump  Callers
// BUGS
//   Stops on large/multi-insn prologues / omit-frame-pointer; max 16 frames.
U0 Bt()
{
  I64 fp, ra, epc, caller_s0;
  epc = BtSnapFresh();
  fp = DbgFP();
  if (epc && DbgInRam(fp)) {
    UartStr("Bt (trap freeze):\n");
    BtWalk(epc, fp, 1);
    return;
  }
  // Capture ra/s0 in-line — HolyC calls to DbgLiveRa/DbgLiveS0 asm labels hang on holyc.
  asm {
	lui	t6, 0x10E00
	slli	t6, t6, 3
	sd	ra, 0x200(t6)
	sd	s0, 0x208(t6)
  }
  ra = *(I64 *)0x87000200;
  fp = *(I64 *)0x87000208;
  UartStr("Bt (live):\n");
  // Match C StkRep: start at caller using saved s0 chain when present.
  if (DbgInRam(fp - 16))
    caller_s0 = *(I64 *)(fp - 16);
  else
    caller_s0 = fp;
  if (DbgInRam(ra) && DbgInRam(caller_s0))
    BtWalk(ra, caller_s0, 0);
  else {
    UartStr("  stack:\n");
    UartStr("    #0 live frame\n");
  }
}
// WatchChk -- compare soft watches; print hits; return hit count.
I64 WatchChk()
{
  I64 i, n, cur, hits;
  hits = 0;
  DbgWatchHit = 0;
  for (i = 0; i < 8; i++) {
    if (!WatchActive[i])
      continue;
    n = WatchLen[i];
    if (n <= 0)
      n = 8;
    cur = DbgPeekWatch(WatchAddr[i], n);
    if (cur != WatchLast[i]) {
      hits++;
      DbgWatchHit = 1;
      "\n*** watch hit @ 0x%X  old=0x%X new=0x%X len=%d\n", WatchAddr[i], WatchLast[i], cur, n;
      WatchLast[i] = cur;
      Bt;
    }
  }
  return hits;
}
// Watch -- Watch(addr, len)
// NAME
//   Watch - soft data watchpoint (compare stub; no Sdtrig)
// SYNOPSIS
//   U0 Watch(I64 addr, I64 len=8);
// DESCRIPTION
//   Arms a soft watch: snapshots up to 8 bytes at addr. DbgTrap (and WatchChk)
//   compare on each trap; on change prints *** watch hit and Bt. With WatchBreak;
//   a hit aborts the eval back to the prompt. No hardware triggers on default virt —
//   misses stores that never trap. Poll: WatchChk; after a region of code.
// EXAMPLES
//   I64 w; Watch(&w); w=7; WatchChk;
//   WatchBreak;  // next DbgTrap watch hit → abort
// SEE ALSO
//   WatchClr  Watchs  WatchChk  Bp  DbgTrap  docs/DEBUGGER.md
// BUGS
//   Soft only; len capped at 8 for the compare word; races between traps invisible.
U0 Watch(I64 addr, I64 len = 8)
{
  I64 i, slot;
  if (!addr) {
    UartStr("Watch: null address\n");
    return;
  }
  if (len <= 0)
    len = 8;
  if (len > 8)
    len = 8;
  slot = -1;
  for (i = 0; i < 8; i++)
    if (!WatchActive[i]) {
      slot = i;
      break;
    }
  if (slot < 0) {
    UartStr("Watch: table full\n");
    return;
  }
  WatchAddr[slot] = addr;
  WatchLen[slot] = len;
  WatchLast[slot] = DbgPeekWatch(addr, len);
  WatchActive[slot] = 1;
  SetTrap("DbgTrap");
  TrapInit();
  "Watch armed @ 0x%X len=%d (soft compare; WatchChk / DbgTrap)\n", addr, len;
}

U0 WatchClr(I64 addr)
{
  I64 i;
  for (i = 0; i < 8; i++)
    if (WatchActive[i] && WatchAddr[i] == addr) {
      WatchActive[i] = 0;
      "Watch cleared @ 0x%X\n", addr;
      return;
    }
  "WatchClr: none @ 0x%X\n", addr;
}

U0 Watchs()
{
  I64 i, n;
  n = 0;
  for (i = 0; i < 8; i++)
    if (WatchActive[i]) {
      "  watch @ 0x%X len=%d last=0x%X\n", WatchAddr[i], WatchLen[i], WatchLast[i];
      n++;
    }
  if (!n)
    UartStr("  (no watches)\n");
}

U0 WatchBreak()
{
  WatchDoBreak = 1;
  UartStr("WatchBreak: on — soft watch hit in DbgTrap aborts eval\n");
}

U0 WatchContinue()
{
  WatchDoBreak = 0;
  UartStr("WatchContinue: soft watch report-only\n");
}
// TrapDump -- TrapDump()
// NAME
//   TrapDump - print last trap CSRs + saved GPRs from MEM_TRAP_SNAP
// SYNOPSIS
//   U0 TrapDump();
// DESCRIPTION
//   Shows mcause/mepc/mtval (snap words 18..20 when published, else live GetM*)
//   and ra/sp/fp/a0..a3 from the trap freeze, then Bt.
// EXAMPLES
//   Fault; TrapDump;
//   Bp(&F); F(1); TrapDump;
// SEE ALSO
//   DbgReg  Bt  GetMcause  GetMepc  GetMtval  pc
U0 TrapDump()
{
  I64 cause, epc, tval, i;
  cause = DbgReg(DBG_I_CAUSE);
  epc = DbgReg(DBG_I_EPC);
  tval = DbgReg(DBG_I_TVAL);
  if (!epc && pc)
    epc = pc;
  if (!cause)
    cause = GetMcause();
  if (!tval)
    tval = GetMtval();
  UartStr("TrapDump (MEM_TRAP_SNAP / last freeze):\n");
  McausePrint(cause);
  "  mepc=0x%X  mtval=0x%X  pc=0x%X\n", epc, tval, pc;
  "  ra=0x%X", DbgRa();
  DbgSymLine(DbgRa());
  "\n";
  "  sp=0x%X  fp=0x%X  mstatus=0x%X\n", DbgSp(), DbgFP(), DbgReg(DBG_I_MSTATUS);
  "  a0=0x%X a1=0x%X a2=0x%X a3=0x%X\n", DbgReg(DBG_I_A0), DbgReg(DBG_I_A0 + 1), DbgReg(DBG_I_A0 + 2), DbgReg(DBG_I_A0 + 3);
  // s1-s11 / gp / tp exist only in the canonical x view (DbgX).
  "  gp=0x%X  tp=0x%X\n", DbgX(3), DbgX(4);
  i = 9;
  while (i <= 27) {
    "  s%d=0x%X", DbgXSNum(i), DbgX(i);
    if (DbgXSNum(i) % 4 == 3)
      "\n";
    i = DbgXSNext(i);
  }
  "\n";
  Bt;
}
// DbgTrap -- DbgTrap(cause,epc,tval)
// NAME
//   DbgTrap - breakpoint / watch trap handler
// SYNOPSIS
//   I64 DbgTrap(I64 cause, I64 epc, I64 tval);
// DESCRIPTION
//   On our ebreak (cause 3): restore insn, dump args, optional Bt, then continue
//   (return epc) or abort to prompt if BpStop. Always runs WatchChk. Step arms are
//   one-shot Bps like any other.
// SEE ALSO
//   Bp  Watch  Step  TrapDump  Bt
// BUGS
//   Resolve via SetTrap("DbgTrap") / FnAddr — do NOT take &DbgTrap from an earlier
//   unit (same forward-ref pitfall as &OnTrap before OnTrap's body).
I64 DbgTrap(I64 cause, I64 epc, I64 tval)
{
  I64 i, resume;
  pc = epc;
  *(I64 *)(MEM_TRAP_SNAP + DBG_I_CAUSE * 8) = cause;
  *(I64 *)(MEM_TRAP_SNAP + DBG_I_EPC * 8) = epc;
  *(I64 *)(MEM_TRAP_SNAP + DBG_I_TVAL * 8) = tval;
  WatchChk();
  resume = 0;
  if (cause == 3) {
    for (i = 0; i < 16; i++) {
      if (DbgActive[i] && DbgAddr[i] == epc) {
        if ((DbgSaved[i] & 3) != 3)
          *(U16 *)DbgAddr[i] = DbgSaved[i] & 0xFFFF;
        else
          *(U32 *)DbgAddr[i] = DbgSaved[i];
        FenceI();
        DbgActive[i] = 0;
        if (DbgStepAddr == epc) {
          "\n*** step @ 0x%08X\n", epc;
          DbgStepAddr = 0;
        } else
          "\n*** breakpoint @ 0x%08X  (args at entry)\n", epc;
        "  a0=0x%X  a1=0x%X  a2=0x%X  a3=0x%X\n", DbgReg(DBG_I_A0), DbgReg(DBG_I_A0 + 1), DbgReg(DBG_I_A0 + 2), DbgReg(DBG_I_A0 + 3);
        "  a4=0x%X  a5=0x%X  a6=0x%X  a7=0x%X\n", DbgReg(DBG_I_A0 + 4), DbgReg(DBG_I_A0 + 5), DbgReg(DBG_I_A0 + 6), DbgReg(DBG_I_A0 + 7);
        "  ra=0x%X  sp=0x%X  fp=0x%X\n", DbgRa(), DbgSp(), DbgFP();
        Bt;
        if (DbgStopOnHit) {
          UartStr("*** dbg stop (BpStop) — eval aborted\n");
          return 0;
        }
        resume = epc;
        break;
      }
    }
  }
  if (DbgWatchHit && WatchDoBreak) {
    UartStr("*** watch break — eval aborted\n");
    DbgWatchHit = 0;
    return 0;
  }
  if (resume)
    return resume;
  if (cause < 0)
    return epc;
  return 0;
}
// Bp -- Bp(&Func)
// NAME
//   Bp - one-shot software breakpoint (ebreak patch)
// SYNOPSIS
//   Bp(&Func)
// DESCRIPTION
//   Patches ebreak (32-bit) or c.ebreak when the entry is compressed. On hit: restore,
//   dump args + Bt, continue (re-exec) unless BpStop. Max 16.
// EXAMPLES
//   Bp(&Add); Add(11,22); Bps; BpClr(&Add);
// SEE ALSO
//   Bps  BpClr  BpStop  Cont  Step  DbgTrap
U0 Bp(I64 addr)
{
  I64 i, slot;
  if (!addr) {
    "Bp: null address\n";
    return;
  }
  slot = -1;
  for (i = 0; i < 16; i++)
    if (!DbgActive[i]) {
      slot = i;
      break;
    }
  if (slot < 0) {
    "Bp: table full\n";
    return;
  }
  DbgAddr[slot] = addr;
  if ((*(U32 *)addr & 3) != 3) {
    DbgSaved[slot] = *(U16 *)addr & 0xFFFF;
    *(U16 *)addr = 0x9002;
  } else {
    DbgSaved[slot] = *(U32 *)addr;
    *(U32 *)addr = 0x00100073;
  }
  FenceI();
  DbgActive[slot] = 1;
  SetTrap("DbgTrap");
  // hc_repl (TRAP_VEC_OFF≠0): ensure mtvec. Legacy: SetTrap name-only; C owns vector.
  if (TRAP_VEC_OFF)
    TrapInit();
  "Bp set @ 0x%08X\n", addr;
}

U0 Bps()
{
  I64 i, n;
  n = 0;
  for (i = 0; i < 16; i++)
    if (DbgActive[i]) {
      "  bp @ 0x%08X", DbgAddr[i];
      if (DbgAddr[i] == DbgStepAddr)
        UartStr("  (step)");
      "\n";
      n++;
    }
  if (!n)
    "  (no active breakpoints)\n";
}

U0 BpClr(I64 addr)
{
  I64 i;
  for (i = 0; i < 16; i++)
    if (DbgActive[i] && DbgAddr[i] == addr) {
      if ((DbgSaved[i] & 3) != 3)
        *(U16 *)DbgAddr[i] = DbgSaved[i] & 0xFFFF;
      else
        *(U32 *)DbgAddr[i] = DbgSaved[i];
      FenceI();
      DbgActive[i] = 0;
      if (DbgStepAddr == addr)
        DbgStepAddr = 0;
      "Bp cleared @ 0x%08X\n", addr;
      return;
    }
  "BpClr: no active breakpoint @ 0x%08X\n", addr;
}

U0 BpStop()
{
  DbgStopOnHit = 1;
  UartStr("BpStop: on — next Bp hit dumps then aborts eval (Cont = re-run)\n");
}

U0 BpGo()
{
  DbgStopOnHit = 0;
  UartStr("BpGo: on — Bp hits dump and continue (default)\n");
}
// Cont -- Cont()
// NAME
//   Cont - continue after debug stop
// SYNOPSIS
//   Cont;
// DESCRIPTION
//   Default Bp mode auto-continues after dump. After BpStop abort, Cont means
//   re-invoke the callee from the prompt (no trapped context to resume).
// SEE ALSO
//   Bp  BpStop  BpGo  Step
U0 Cont()
{
  if (DbgStopOnHit)
    UartStr("Cont: BpStop is on — re-call the function from `>` (no live resume)\n");
  else
    UartStr("Cont: Bp auto-continues on hit (BpGo). Use BpStop to abort instead.\n");
}
// Step -- Step(addr)
// NAME
//   Step - soft single-step: one-shot ebreak at next insn
// SYNOPSIS
//   Step;  Step(addr);
// DESCRIPTION
//   Arms Bp at the next sequential instruction after addr (default: last trap pc).
//   Insn length 4 if low 2 bits == 11, else 2 (RVC). Not true dcsr.step — branches
//   / jumps are not followed; use StepOver for return-address break.
// EXAMPLES
//   pc = FnAddr("Add"); Step; Add(1,2);
// SEE ALSO
//   StepOver  Bp  DbgTrap  docs/DEBUGGER.md
// BUGS
//   Sequential only; no debug-mode step; needs 32-bit patchable target.
U0 Step(I64 addr = 0)
{
  I64 next, w;
  if (!addr)
    addr = pc;
  if (!addr) {
    UartStr("Step: no pc — pass addr or trap/Bp first\n");
    return;
  }
  w = *(U16 *)addr;
  if ((w & 3) == 3)
    next = addr + 4;
  else
    next = addr + 2;
  if ((*(U32 *)next & 3) != 3) {
    "Step: next 0x%X is compressed — can't patch\n", next;
    return;
  }
  DbgStepAddr = next;
  Bp(next);
  "Step: armed @ 0x%X (next after 0x%X)\n", next, addr;
}
// StepOver -- StepOver()
// NAME
//   StepOver - soft step-over via breakpoint at return address
// SYNOPSIS
//   StepOver;
// DESCRIPTION
//   After a trap/Bp, sets a one-shot Bp at DbgRa (caller). Live: uses DbgLiveRa.
// SEE ALSO
//   Step  Bp  DbgRa
U0 StepOver()
{
  I64 ra;
  ra = DbgRa();
  if (!ra || !DbgInRam(ra))
    ra = DbgLiveRa();
  if (!ra || !DbgInRam(ra)) {
    UartStr("StepOver: no return address\n");
    return;
  }
  if ((*(U32 *)ra & 3) != 3) {
    "StepOver: ra 0x%X compressed — can't\n", ra;
    return;
  }
  DbgStepAddr = ra;
  Bp(ra);
  "StepOver: armed @ ra 0x%X\n", ra;
}
// DbgHelp -- DbgHelp()
// NAME
//   DbgHelp - short debugger cheat sheet
// SYNOPSIS
//   DbgHelp;
// DESCRIPTION
//   Lists Regs/Bt/Bp/Watch/Step/TrapDump entry points. Full matrix: docs/DEBUGGER.md.
U0 DbgHelp()
{
  UartStr("DbgHelp — UART debugger (docs/DEBUGGER.md)\n");
  UartStr("  Regs; Reg(\"a0\"); Reg(\"mstatus\"); CsrExplain(\"mcause\");  // soft snap+restore GPRs (csr.hc)\n");
  UartStr("  Bt; StkRep;                     // backtrace (trap freeze or live)\n");
  UartStr("  Bp(&F); Bps; BpClr(&F); Cont;   // ebreak; BpStop aborts eval\n");
  UartStr("  Watch(&x); WatchChk; Watchs;    // soft compare (WatchBreak aborts)\n");
  UartStr("  Step; StepOver;                 // soft next-insn / ra breakpoint\n");
  UartStr("  TrapDump; DbgReg(n); pc;        // last trap CSRs + GPRs\n");
  UartStr("  CsrExplain(\"mstatus\"); Bits(\"mie\");       // CSR bitfield decode\n");
  UartStr("  CrashDump; CrashMon; CrashHelp; // fault → crash> (CONSOLE #9)\n");
  UartStr("  Man(\"Debugger\"); Man(\"CrashMon\"); Man(\"Regs\"); U(pc-16);\n");
}
// StkRep -- StkRep()
// NAME
//   StkRep - symbolic stack report (TempleOS-style)
// SYNOPSIS
//   StkRep;
// DESCRIPTION
//   Prefer C host slot on legacy REPL; else call HolyC Bt (same FP walk).
U0 StkRep()
{
  I64 (*sr)();
  sr = *(I64 *)0x87001138;
  if (SoftDbgSlotFnOk(sr)) {
    sr();
    return;
  }
  Bt;
}
// ---- TempleOS-style inspection: Dr / Dm / D / Da ----
// Dr -- Dr()
// NAME
//   Dr - dump registers (Regs); dig-down with Reg/GetM*
// SYNOPSIS
//   U0 Dr();
// DESCRIPTION
//   Alias of Regs. Then Reg("sp"); Reg("mstatus"); GetMStatus; RegHelp; Man("Regs").
// BUGS
//   Same as Regs (snap+restore stub; values at stub entry — docs/DEBUGGER.md).
U0 Dr()
{
  Regs();
}

U0 Dm(I64 a, I64 n = 64)
{
  I64 r, c, b;
  for (r = 0; r < n; r += 16) {
    "%08X: ", a + r;
    for (c = 0; c < 16; c++) {
      if (r + c < n) {
        "%02X ", *(U8 *)(a + r + c);
      } else {
        "   ";
      }
    }
    "   ";
    for (c = 0; c < 16 && r + c < n; c++) {
      b = *(U8 *)(a + r + c);
      if (b >= 32 && b < 127)
        PutCh(b);
      else
        PutCh('.');
    }
    "\n";
  }
}

U0 D(I64 a, I64 n = 64)
{
  Dm(a, n);
}

U0 Da(I64 a, I64 n = 8)
{
  I64 i, v, base;
  U8 *nm;
  for (i = 0; i < n; i++) {
    v = *(I64 *)(a + i * 8);
    "%08X: %016X", a + i * 8, v;
    nm = SymName(v);
    if (nm) {
      base = SymBase(v);
      "  %s+0x%X", nm, v - base;
    }
    "\n";
  }
}
