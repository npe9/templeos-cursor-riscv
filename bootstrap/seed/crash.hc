// crash.hc -- CONSOLE #9 crash monitor (product repl-holyc / UART path).
// On sync fault: dump cause/PC/SP/regs/bt, then interactive md/mw/regs/bt/reboot.
// Prefer this over editing trap.hc (G2/G7 lane). Default SetTrap("CrashOnTrap").
// Breakpoints forward to DbgTrap; ecall/IRQ pass through.
// Dig-down: docs/CONSOLE.md #9, docs/DEBUGGER.md.
I64 g_crash_in_mon;
U8 g_crash_line[128];
// CrashInRam -- DRAM window for md/mw (same as DbgInRam).
I64 CrashInRam(I64 a)
{
  return a >= 0x80000000 && a < 0x88000000;
}
// CrashCmdEq -- case-sensitive cmd token match (exact or prefix before space).
I64 CrashCmdEq(U8 *line, U8 *cmd)
{
  I64 i;
  if (!line || !cmd)
    return 0;
  i = 0;
  while (cmd[i] && line[i] == cmd[i])
    i++;
  if (cmd[i])
    return 0;
  return !line[i] || line[i] == ' ' || line[i] == '\t';
}

U8 *CrashSkip(U8 *p)
{
  if (!p)
    return p;
  while (*p == ' ' || *p == '\t')
    p++;
  return p;
}

U8 *CrashSkipTok(U8 *p)
{
  p = CrashSkip(p);
  while (*p && *p != ' ' && *p != '\t')
    p++;
  return CrashSkip(p);
}
// CrashGetLine -- blocking UART line (poll; safe with IRQs off in trap).
U0 CrashGetLine(U8 *buf, I64 max)
{
  I64 i, ch;
  i = 0;
  while (i < max - 1) {
    ch = UartGet();
    if (ch == '\r' || ch == '\n') {
      PutCh('\n');
      break;
    }
    if (ch == 8 || ch == 127) {
      if (i > 0) {
        i--;
        UartStr("\b \b");
      }
      continue;
    }
    if (ch == 3) {
      buf[0] = 0;
      UartStr("^C\n");
      return;
    }
    if (ch >= 32 && ch < 127) {
      buf[i++] = ch;
      PutCh(ch);
    }
  }
  buf[i] = 0;
}
// Md -- Md(addr, n=64)
// NAME
//   Md - hex memory dump (Dm alias; crash-monitor / dig-down)
// SYNOPSIS
//   Md(addr);  Md(addr, n);
// DESCRIPTION
//   Dumps n bytes at addr (default 64). Same as Dm. Crash monitor: md ADDR [LEN].
// EXAMPLES
//   Md(MEM_TRAP_SNAP, 0x90);
//   Md(pc, 32);
// SEE ALSO
//   Mw  Dm  Da  CrashMon  TrapDump
U0 Md(I64 a, I64 n = 64)
{
  if (!CrashInRam(a) || n <= 0) {
    UartStr("Md: bad addr/len (DRAM 0x80000000..0x88000000)\n");
    return;
  }
  if (n > 0x1000)
    n = 0x1000;
  "Md @ 0x%X  len=%d\n", a, n;
  Dm(a, n);
}
// Mw -- Mw(addr, val)
// NAME
//   Mw - write I64 to DRAM
// SYNOPSIS
//   Mw(addr, val);
// DESCRIPTION
//   Stores one I64 at addr (DRAM only, 8-byte aligned). Crash monitor: mw ADDR VAL.
// EXAMPLES
//   Mw(0x80001000, 0xDEAD);
// SEE ALSO
//   Md  Dm  CrashMon
U0 Mw(I64 a, I64 v)
{
  if (!CrashInRam(a)) {
    UartStr("Mw: bad addr (DRAM only)\n");
    return;
  }
  if (a & 7) {
    UartStr("Mw: addr must be 8-byte aligned\n");
    return;
  }
  *(I64 *)a = v;
  "Mw: [0x%X] = 0x%X\n", a, v;
}
// CrashParseAddr -- "pc" / "sp" / "fp" / "snap" / hex → DRAM addr (0 = fail).
I64 CrashParseAddr(U8 *p)
{
  I64 a;
  if (!p || !*p)
    return 0;
  if (CrashCmdEq(p, "pc") || CrashCmdEq(p, "mepc")) {
    a = DbgReg(DBG_I_EPC);
    if (!a)
      a = pc;
    return a;
  }
  if (CrashCmdEq(p, "sp"))
    return DbgSp();
  if (CrashCmdEq(p, "fp") || CrashCmdEq(p, "s0"))
    return DbgFP();
  if (CrashCmdEq(p, "ra"))
    return DbgRa();
  if (CrashCmdEq(p, "snap") || CrashCmdEq(p, "trap"))
    return MEM_TRAP_SNAP;
  a = Atoi(p);
  if (!CrashInRam(a))
    return 0;
  return a;
}
// CrashHelp -- CrashHelp()
// NAME
//   CrashHelp - crash-monitor cheat sheet
// SYNOPSIS
//   CrashHelp;
// DESCRIPTION
//   Lists crash> commands and HolyC entry points for CONSOLE #9. Full page:
//   Man("CrashMon"). FB WinMgr serial twin: RVWinSerial / BOARD_FB.md.
// EXAMPLES
//   CrashHelp;
//   Fault;  // then: regs / md ADDR / go
// SEE ALSO
//   CrashMon  CrashDump  CrashOnTrap  Md  Mw  Man  Debugger
U0 CrashHelp()
{
  UartStr("CrashHelp — post-fault monitor (docs/CONSOLE.md #9)\n");
  UartStr("  On fault: dump → crash>  then dig-down, or go to abort eval\n");
  UartStr("  crash> cmds: help | ? | h\n");
  UartStr("    regs|dr          soft GPR snap+restore (Regs)\n");
  UartStr("    bt|stk           HolyC backtrace (trap freeze or live)\n");
  UartStr("    dump|snap        CrashDump / TrapDump (MEM_TRAP_SNAP)\n");
  UartStr("    pc               print last mepc / pc + symbol\n");
  UartStr("    md [ADDR|pc|sp|fp|snap] [N]   hex+ASCII (default: snap 0xA8)\n");
  UartStr("    da ADDR [N]      symbolic I64 slots (Da)\n");
  UartStr("    mw ADDR VAL      store I64 (8-byte aligned DRAM)\n");
  UartStr("    go|cont|q        leave monitor → abort eval to >\n");
  UartStr("    reboot|reset     soft Boot;  hard|hardreset  test finisher\n");
  UartStr("  HolyC: CrashDump; CrashMon; Md(a); Mw(a,v); Man(\"CrashMon\");\n");
  UartStr("  Soft:  SafeMode; Recover; Reset; HardReset;  Man(\"Debugger\");\n");
  UartStr("  FB:    RVWinSerial + RVCrashMon (help/regs/bt/md/mw/fault/crash)\n");
  UartStr("         while WinMgr — BOARD_FB.md / docs/CONSOLE.md\n");
}
// CrashDump -- CrashDump()
// NAME
//   CrashDump - print fault cause/PC/SP/regs + Bt from MEM_TRAP_SNAP
// SYNOPSIS
//   CrashDump;
// DESCRIPTION
//   Full post-fault dump for the UART crash monitor. Uses trap freeze
//   (mcause/mepc/mtval + saved GPRs). Called automatically from CrashOnTrap.
// EXAMPLES
//   Fault;          // auto dump + crash>
//   CrashDump;      // re-print last freeze
// SEE ALSO
//   CrashMon  TrapDump  Bt  Regs  Md  Mw
U0 CrashDump()
{
  I64 cause, epc, tval;
  cause = DbgReg(DBG_I_CAUSE);
  epc = DbgReg(DBG_I_EPC);
  tval = DbgReg(DBG_I_TVAL);
  if (!epc && pc)
    epc = pc;
  if (!cause)
    cause = GetMcause();
  if (!tval)
    tval = GetMtval();
  UartStr("\n*** FAULT: ");
  UartStr(TrapCauseName(cause));
  UartStr("\n");
  "  cause=0x%X  tval=0x%X\n", cause, tval;
  "  pc  = 0x%X", epc;
  if (epc)
    DbgSymLine(epc);
  "\n";
  "  ra  = 0x%X", DbgRa();
  DbgSymLine(DbgRa());
  "\n";
  "  sp  = 0x%X  fp = 0x%X\n", DbgSp(), DbgFP();
  "  a0=0x%X a1=0x%X a2=0x%X a3=0x%X\n", DbgReg(DBG_I_A0), DbgReg(DBG_I_A0 + 1), DbgReg(DBG_I_A0 + 2), DbgReg(DBG_I_A0 + 3);
  "  a4=0x%X a5=0x%X a6=0x%X a7=0x%X\n", DbgReg(DBG_I_A0 + 4), DbgReg(DBG_I_A0 + 5), DbgReg(DBG_I_A0 + 6), DbgReg(DBG_I_A0 + 7);
  Bt;
  if (CrashInRam(epc)) {
    UartStr("  --- bytes @ pc ---\n");
    Md(epc, 32);
  }
  if (CrashInRam(MEM_TRAP_SNAP)) {
    UartStr("  --- MEM_TRAP_SNAP (0xA8) ---\n");
    Md(MEM_TRAP_SNAP, 0xA8);
  }
  UartStr("  (CrashMon; md/mw/regs/bt/go — Man(\"CrashMon\"))\n");
}
// CrashMon -- CrashMon()
// NAME
//   CrashMon - interactive post-fault dig-down (md/mw/regs/bt/reboot)
// SYNOPSIS
//   CrashMon;
// DESCRIPTION
//   UART mini-shell after a fault dump. Commands are plain lines (not HolyC eval)
//   so they work inside the trap path with IRQs off. go/cont/q returns to the
//   caller (CrashOnTrap then aborts eval to `>`). reboot/reset soft-Boot;
//   hard/hardreset hits the test finisher.
// EXAMPLES
//   Fault;                 // auto: dump → crash> …
//   // crash> regs
//   // crash> md 0x87000100 64
//   // crash> go
//   CrashMon;              // re-enter on last freeze
// SEE ALSO
//   CrashDump  CrashOnTrap  Md  Mw  Regs  Bt  Reset  HardReset  TrapDump
// BUGS
//   Nested faults from bad md/mw are possible — DRAM window only. No HolyC JIT
//   eval inside the monitor (by design).
U0 CrashMon()
{
  I64 addr, n, val;
  U8 *p;
  if (g_crash_in_mon) {
    UartStr("CrashMon: already active\n");
    return;
  }
  g_crash_in_mon = 1;
  UartStr("crash> ");
  while (TRUE) {
    CrashGetLine(g_crash_line, 128);
    p = CrashSkip(g_crash_line);
    if (!*p) {
      UartStr("crash> ");
      continue;
    }
    if (CrashCmdEq(p, "help") || CrashCmdEq(p, "?") || CrashCmdEq(p, "h")) {
      CrashHelp();
      UartStr("crash> ");
      continue;
    }
    if (CrashCmdEq(p, "go") || CrashCmdEq(p, "cont") || CrashCmdEq(p, "c") || CrashCmdEq(p, "q") || CrashCmdEq(p, "quit")) {
      UartStr("crash: leave monitor → abort eval\n");
      g_crash_in_mon = 0;
      return;
    }
    if (CrashCmdEq(p, "reboot") || CrashCmdEq(p, "reset")) {
      g_crash_in_mon = 0;
      UartStr("crash: Reset;\n");
      Reset();
      return;
    }
    if (CrashCmdEq(p, "hard") || CrashCmdEq(p, "hardreset")) {
      g_crash_in_mon = 0;
      UartStr("crash: HardReset;\n");
      HardReset();
      return;
    }
    if (CrashCmdEq(p, "regs") || CrashCmdEq(p, "dr")) {
      Regs();
      UartStr("crash> ");
      continue;
    }
    if (CrashCmdEq(p, "bt") || CrashCmdEq(p, "stk") || CrashCmdEq(p, "stkrep")) {
      Bt;
      UartStr("crash> ");
      continue;
    }
    if (CrashCmdEq(p, "pc") || CrashCmdEq(p, "mepc")) {
      addr = DbgReg(DBG_I_EPC);
      if (!addr)
        addr = pc;
      "  pc=0x%X", addr;
      if (addr)
        DbgSymLine(addr);
      "\n";
      UartStr("crash> ");
      continue;
    }
    if (CrashCmdEq(p, "dump") || CrashCmdEq(p, "trapdump") || CrashCmdEq(p, "snap") || CrashCmdEq(p, "crashdump")) {
      if (CrashCmdEq(p, "trapdump"))
        TrapDump();
      else
        CrashDump();
      UartStr("crash> ");
      continue;
    }
    if (CrashCmdEq(p, "md") || CrashCmdEq(p, "dm") || CrashCmdEq(p, "d")) {
      p = CrashSkipTok(p);
      if (!*p) {
        Md(MEM_TRAP_SNAP, 0xA8);
        UartStr("crash> ");
        continue;
      }
      addr = CrashParseAddr(p);
      if (!addr) {
        UartStr("usage: md [ADDR|pc|sp|fp|ra|snap] [LEN]\n");
        UartStr("crash> ");
        continue;
      }
      p = CrashSkipTok(p);
      n = 64;
      if (*p)
        n = Atoi(p);
      Md(addr, n);
      UartStr("crash> ");
      continue;
    }
    if (CrashCmdEq(p, "da")) {
      p = CrashSkipTok(p);
      if (!*p) {
        UartStr("usage: da ADDR [N]\n");
        UartStr("crash> ");
        continue;
      }
      addr = CrashParseAddr(p);
      if (!addr) {
        UartStr("usage: da ADDR [N]  (ADDR in DRAM)\n");
        UartStr("crash> ");
        continue;
      }
      p = CrashSkipTok(p);
      n = 8;
      if (*p)
        n = Atoi(p);
      if (n <= 0)
        n = 8;
      if (n > 64)
        n = 64;
      Da(addr, n);
      UartStr("crash> ");
      continue;
    }
    if (CrashCmdEq(p, "mw")) {
      p = CrashSkipTok(p);
      if (!*p) {
        UartStr("usage: mw ADDR VAL\n");
        UartStr("crash> ");
        continue;
      }
      addr = CrashParseAddr(p);
      if (!addr) {
        UartStr("usage: mw ADDR VAL  (ADDR in DRAM)\n");
        UartStr("crash> ");
        continue;
      }
      p = CrashSkipTok(p);
      if (!*p) {
        UartStr("usage: mw ADDR VAL\n");
        UartStr("crash> ");
        continue;
      }
      val = Atoi(p);
      Mw(addr, val);
      UartStr("crash> ");
      continue;
    }
    UartStr("crash: unknown — help | regs | bt | pc | md | da | mw | dump | go | reboot\n");
    UartStr("crash> ");
  }
}
// ZapTrap -- SetTrap("ZapTrap"); Ecall;  (G2 smoke — AOT, not thin-JIT "str";)
I64 ZapTrap(I64 cause, I64 epc, I64 tval)
{
  UartStr("ZAP-HIT ");
  return epc + 4;
}
// CrashOnTrap -- CrashOnTrap(cause, epc, tval)
// NAME
//   CrashOnTrap - default product fault handler (dump + CrashMon)
// SYNOPSIS
//   SetTrap("CrashOnTrap"); TrapInit;
// DESCRIPTION
//   Product UART path default after TrapInit. IRQ → resume; ecall → epc+4;
//   breakpoint → DbgTrap; other sync faults → CrashDump + CrashMon, then
//   TrapFaultRecover (abort eval to `>`). Does not edit trap.hc policy.
// EXAMPLES
//   // boot already: SetTrap("CrashOnTrap");
//   Fault;   // dump → crash> go → back to >
// SEE ALSO
//   CrashDump  CrashMon  DbgTrap  OnTrap  TrapInit  Fault
I64 CrashOnTrap(I64 cause, I64 epc, I64 tval)
{
  I64 r;
  pc = epc;
  if (cause < 0)
    return epc;
  if (cause == 8 || cause == 9 || cause == 11)
    return epc + 4;
  if (cause == 3) {
    r = DbgTrap(cause, epc, tval);
    if (r)
      return r;
    return &TrapFaultRecover;
  }
  CrashDump();
  CrashMon();
  return &TrapFaultRecover;
}
