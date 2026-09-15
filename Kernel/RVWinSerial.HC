// RVWinSerial.HC — HolyC ExePutS REPL on UART + graphical Term (BOARD_FB).
// Serial: soft-RX line buffer → Dispatch → RVWinSerialEval (ExePutS when wired).
// Term: VirtioInput → RVWinTermPutChar → same Dispatch (Print mirrored into Term).
// Soft RX (RVUartSoftOn) + polled drain in RVWinMgrRun. Crash mon via
// RVCrashMonInit (host trap → UART crash>). Dig-down regs/bt/md/mw/fault remain
// as meta; prefer HolyC for everything else.
extern U0 RVBpSymPrint(I64 addr);
extern U0 RVBpRestoreAll();
extern U0 RVWinSerialEscKey();
extern U0 RVWinSerialTermScroll(I64 delta, Bool absolute_top, Bool absolute_bottom);
#define RV_WIN_SERIAL_LINE_MAX 1024   // was 160: longer REPL lines were silently cut mid-token
// Soft GPR snap (same window as seed/csr.hc / gdbstub — not trap snap).
#define MEM_REGS_SNAP 0x87000300
#define REG_ZERO 0
#define REG_RA   1
#define REG_SP   2
#define REG_GP   3
#define REG_TP   4
#define REG_T0   5
#define REG_S0   8
#define REG_FP   8
#define REG_S1   9
#define REG_A0   10
#define REG_S2   18
#define REG_T3   28
I64 rv_win_serial_ready;
I64 rv_win_serial_cmds;
I64 rv_win_serial_len;
U8 rv_win_serial_line[RV_WIN_SERIAL_LINE_MAX];
I64 (*RVWinSerialEval)(U8 *line);
// Graphical Term + Adam line buffers (virtio-kbd → same Dispatch as serial).
I64 rv_win_term_len;
I64 rv_win_term_cmds;
I64 rv_win_term_mirror;
U8 rv_win_term_line[RV_WIN_SERIAL_LINE_MAX];
I64 rv_win_adam_len;
I64 rv_win_adam_cmds;
I64 rv_win_adam_mirror;
U8 rv_win_adam_line[RV_WIN_SERIAL_LINE_MAX];
U8 rv_win_edit_path[192];   // file backing the active `ed` editor window
I64 rv_win_edit_dirty;      // unsaved edits since load/save
asm {
	RVWinCsrrMstatus::
	csrr	a0, 0x300
	ret
	RVWinCsrrMie::
	csrr	a0, 0x304
	ret
	RVWinCsrrMip::
	csrr	a0, 0x344
	ret
	RVWinCsrrMepc::
	csrr	a0, 0x341
	ret
	RVWinCsrrMcause::
	csrr	a0, 0x342
	ret
	RVWinCsrrMtval::
	csrr	a0, 0x343
	ret
	RVWinCsrrMtvec::
	csrr	a0, 0x305
	ret
	RVWinCsrrMscratch::
	csrr	a0, 0x340
	ret
	RVWinCsrrMisa::
	csrr	a0, 0x301
	ret
	RVWinCsrrMhartid::
	csrr	a0, 0xF14
	ret
	RVWinCsrrMedeleg::
	csrr	a0, 0x302
	ret
	RVWinCsrrMideleg::
	csrr	a0, 0x303
	ret
	RVWinCsrrMcounteren::
	csrr	a0, 0x306
	ret
	RVWinCsrrSstatus::
	csrr	a0, 0x100
	ret
	RVWinCsrrSie::
	csrr	a0, 0x104
	ret
	RVWinCsrrSip::
	csrr	a0, 0x144
	ret
	RVWinCsrrStvec::
	csrr	a0, 0x105
	ret
	RVWinCsrrSepc::
	csrr	a0, 0x141
	ret
	RVWinCsrrScause::
	csrr	a0, 0x142
	ret
	RVWinCsrrStval::
	csrr	a0, 0x143
	ret
	RVWinCsrrSatp::
	csrr	a0, 0x180
	ret
	RVWinCsrrCycle::
	csrr	a0, 0xC00
	ret
	RVWinCsrrTime::
	csrr	a0, 0xC01
	ret
	RVWinCsrrInstret::
	csrr	a0, 0xC02
	ret
	// Deliberate illegal insn for `fault` → UART crash>. Encodes as
	// csrrw x0,cycle,x0 (0xC0001073) — RO CSR write. Not GetTSC/IC_RDTSC.
	RVWinSerialFaultAsm::
	unimp
	ret
}

I64 RVWinSerialCmdEq(U8 *line, U8 *cmd)
{
  //Case-insensitive cmd match; line may end with ';' (smoke sends Regs;).
  I64 i;
  U8 a, b;
  if (!line || !cmd)
    return 0;
  i = 0;
  while (cmd[i]) {
    a = line[i];
    b = cmd[i];
    if (a >= 'A' && a <= 'Z')
      a += 32;
    if (b >= 'A' && b <= 'Z')
      b += 32;
    if (a != b)
      return 0;
    i++;
  }
  return !line[i] || line[i] == ' ' || line[i] == '\t' || line[i] == ';';
}

U8 *RVWinSerialSkip(U8 *p)
{
  if (!p)
    return p;
  while (*p == ' ' || *p == '\t')
    p++;
  return p;
}

U8 *RVWinSerialSkipTok(U8 *p)
{
  p = RVWinSerialSkip(p);
  while (*p && *p != ' ' && *p != '\t')
    p++;
  return RVWinSerialSkip(p);
}

I64 RVWinSerialInRam(I64 a)
{
  return a >= 0x80000000 && a < 0x88000000;
}
// Text / AOT blob below SYS_FIXED_AREA (0x87000000). Stack sits ~0x87E… —
// InRam alone cannot distinguish code from frame pointers.
I64 RVWinSerialInCode(I64 a)
{
  return a >= 0x80000000 && a < 0x87000000 && !(a & 1);
}

I64 RVWinSerialInStk(I64 a)
{
  return a >= 0x87000000 && a < 0x88000000 && !(a & 7);
}

U0 RVWinSerialHelp()
{
  if (RVWinSerialEval) {
    Print("RVWinSerial — HolyC ExePutS REPL (UART + graphical Term)\n");
    Print("  type HolyC at `>` (e.g. 1+1;  Print(\"hi\\n\");)\n");
    Print("  Term (cocoa/SDL): click window, focus Term, Enter runs\n");
    Print("  max / tileh / tilev  WinMax / WinTileHorz / WinTileVert\n");
    Print("  user        Spawn User → new Term-like win (P1)\n");
    Print("  Tasks;       list desktop windows + task bindings\n");
    Print("  Find(\"str\"); grep the doc tree → browsable results window\n");
    Print("  Ed(\"file\");  edit a file (arrows, Ctrl-W save, Esc leave)\n");
    Print("  q / quit     quit WinMgr (same as ESC on virtio-kbd)\n");
    Print("  fault/crash  UART crash> (md/mw/regs/bt/go/reboot)\n");
    Print("  dig-down:    help regs csrs bt md ADDR [N] mw ADDR VAL\n");
    return;
  }
  Print("RVWinSerial — UART TTY while WinMgr/FB runs (docs/CONSOLE.md, BOARD_FB.md)\n");
  Print("  help / ?     this sheet\n");
  Print("  regs         soft GPR snap + CSR dig-down\n");
  Print("  csrs / csr   machine + supervisor CSR dump (mstatus/mie/mtvec/…)\n");
  Print("  bt           FP/RA backtrace (live; code PCs; soft sym map)\n");
  Print("  md ADDR [N]  hex dump DRAM (default 64 bytes)\n");
  Print("  mw ADDR VAL  store I64 in DRAM\n");
  Print("  max          WinMax focused window\n");
  Print("  tileh/tilev  WinTileHorz / WinTileVert\n");
  Print("  user         Spawn User → new Term-like win\n");
  Print("  Tasks;       list desktop windows + task bindings\n");
  Print("  Find(\"str\"); grep the doc tree → browsable results window\n");
  Print("  Ed(\"file\");  edit a file (arrows move, Ctrl-W save, Esc leave)\n");
  Print("  fault        deliberate illegal insn → UART crash>\n");
  Print("  crash        enter UART crash> monitor now\n");
  Print("  q / quit     quit WinMgr (same as ESC on virtio-kbd)\n");
  Print("Wire RVWinSerialEval=&ExePutS (win interactive) for HolyC REPL.\n");
}
// Mirror of bootstrap/seed/csr.hc McauseCauseName — Kernel has no seed include.
U8 *RVWinMcauseName(I64 v)
{
  I64 intr, code;
  intr = (v >> 63) & 1;
  code = v & 0x7FFFFFFFFFFFFFFF;
  if (intr) {
    if (code == 3)
      return "machine soft interrupt";
    if (code == 7)
      return "machine timer interrupt";
    if (code == 11)
      return "machine external interrupt";
    if (code == 1)
      return "supervisor soft interrupt";
    if (code == 5)
      return "supervisor timer interrupt";
    if (code == 9)
      return "supervisor external interrupt";
    return "interrupt";
  }
  if (code == 0)
    return "insn address misaligned";
  if (code == 1)
    return "insn access fault";
  if (code == 2)
    return "illegal instruction";
  if (code == 3)
    return "breakpoint";
  if (code == 4)
    return "load address misaligned";
  if (code == 5)
    return "load access fault";
  if (code == 6)
    return "store address misaligned";
  if (code == 7)
    return "store access fault";
  if (code == 8)
    return "ecall from U-mode";
  if (code == 9)
    return "ecall from S-mode";
  if (code == 11)
    return "ecall from M-mode";
  if (code == 12)
    return "insn page fault";
  if (code == 13)
    return "load page fault";
  if (code == 15)
    return "store page fault";
  return "exception";
}

U0 RVWinMcausePrint(I64 v, I64 mepc)
{
  I64 intr, code;
  U8 *name;
  // Idle / no fault snap: mcause=0 is still "insn address misaligned" in the
  // ISA table, but printing that at Regs; is misleading — say none.
  if (!v && !mepc) {
    Print("     mcause=0x0  (none — no fault snap)\n");
    return;
  }
  if (v < 0) {
    // Bit 63 set: the last trap was an interrupt (UART RX / timer), not a fault.
    Print("     mcause=0x%X  (none — no fault snap) [last trap: interrupt %d]\n", v, v & 0xFF);
    return;
  }
  intr = (v >> 63) & 1;
  code = v & 0x7FFFFFFFFFFFFFFF;
  name = RVWinMcauseName(v);
  if (intr)
    Print("     mcause=0x%X  Interrupt code=%d (%s)\n", v, code, name);
  else
    Print("     mcause=0x%X  Exception code=%d (%s)\n", v, code, name);
}
// Inline snap — must match seed/csr.hc RegsSnapOnly / gdbstub GdbSnapRegs
// (lui/slli → 0x87000000; xN at MEM_REGS_SNAP+N*8). No Hc*/HashFind.
U0 RVWinRegsSnapOnly()
{
  asm {
	addi	sp, sp, -16
	sd	t6, 0(sp)
	sd	t5, 8(sp)
	lui	t6, 0x10E00
	slli	t6, t6, 3
	sd	x1, 0x308(t6)
	addi	t5, sp, 16
	sd	t5, 0x310(t6)
	sd	x3, 0x318(t6)
	sd	x4, 0x320(t6)
	sd	x5, 0x328(t6)
	sd	x6, 0x330(t6)
	sd	x7, 0x338(t6)
	sd	x8, 0x340(t6)
	sd	x9, 0x348(t6)
	sd	x10, 0x350(t6)
	sd	x11, 0x358(t6)
	sd	x12, 0x360(t6)
	sd	x13, 0x368(t6)
	sd	x14, 0x370(t6)
	sd	x15, 0x378(t6)
	sd	x16, 0x380(t6)
	sd	x17, 0x388(t6)
	sd	x18, 0x390(t6)
	sd	x19, 0x398(t6)
	sd	x20, 0x3A0(t6)
	sd	x21, 0x3A8(t6)
	sd	x22, 0x3B0(t6)
	sd	x23, 0x3B8(t6)
	sd	x24, 0x3C0(t6)
	sd	x25, 0x3C8(t6)
	sd	x26, 0x3D0(t6)
	sd	x27, 0x3D8(t6)
	sd	x28, 0x3E0(t6)
	sd	x29, 0x3E8(t6)
	ld	t5, 8(sp)
	sd	t5, 0x3F0(t6)
	ld	t5, 0(sp)
	sd	t5, 0x3F8(t6)
	ld	t5, 8(sp)
	ld	t6, 0(sp)
	addi	sp, sp, 16
  }
  *(I64 *)MEM_REGS_SNAP = 0;
}

U0 RVWinRegsRestoreOnly()
{
  // Do not reload ra/sp/fp/s* — HolyC frames use them. Temps/args only.
  asm {
	lui	t6, 0x10E00
	slli	t6, t6, 3
	ld	x5, 0x328(t6)
	ld	x6, 0x330(t6)
	ld	x7, 0x338(t6)
	ld	x10, 0x350(t6)
	ld	x11, 0x358(t6)
	ld	x12, 0x360(t6)
	ld	x13, 0x368(t6)
	ld	x14, 0x370(t6)
	ld	x15, 0x378(t6)
	ld	x16, 0x380(t6)
	ld	x17, 0x388(t6)
	ld	x28, 0x3E0(t6)
	ld	x29, 0x3E8(t6)
	ld	x30, 0x3F0(t6)
	ld	t6, 0x3F8(t6)
  }
}

I64 RVWinRegGprDigit(U8 *s)
{
  I64 n;
  if (!s || !*s)
    return -1;
  n = 0;
  while (*s >= '0' && *s <= '9') {
    n = n * 10 + (*s - '0');
    s++;
  }
  if (*s)
    return -1;
  return n;
}

I64 RVWinRegGprIndex(U8 *name)
{
  I64 n;
  U8 *p;
  U8 c0;
  if (!name || !*name)
    return -1;
  if ((name[0] == 'x' || name[0] == 'X') && name[1] >= '0' && name[1] <= '9') {
    n = 0;
    p = name + 1;
    while (*p >= '0' && *p <= '9') {
      n = n * 10 + (*p - '0');
      p++;
    }
    if (!*p && n >= 0 && n < 32)
      return n;
    return -1;
  }
  if ((name[0] == 'R' || name[0] == 'r') && (name[1] == 'E' || name[1] == 'e') && (name[2] == 'G' || name[2] == 'g')) {
    p = name + 3;
    if (*p == '_')
      p++;
    name = p;
    if (!*name)
      return -1;
  }
  if (!StrICmp(name, "zero"))
    return REG_ZERO;
  if (!StrICmp(name, "ra"))
    return REG_RA;
  if (!StrICmp(name, "sp"))
    return REG_SP;
  if (!StrICmp(name, "gp"))
    return REG_GP;
  if (!StrICmp(name, "tp"))
    return REG_TP;
  if (!StrICmp(name, "fp") || !StrICmp(name, "s0"))
    return REG_FP;
  if (!StrICmp(name, "s1"))
    return REG_S1;
  c0 = name[0];
  if (c0 >= 'A' && c0 <= 'Z')
    c0 += 32;
  if (c0 == 't' && name[1]) {
    n = RVWinRegGprDigit(name + 1);
    if (n >= 0 && n <= 2)
      return REG_T0 + n;
    if (n >= 3 && n <= 6)
      return REG_T3 + (n - 3);
  }
  if (c0 == 'a' && name[1]) {
    n = RVWinRegGprDigit(name + 1);
    if (n >= 0 && n <= 7)
      return REG_A0 + n;
  }
  if (c0 == 's' && name[1]) {
    n = RVWinRegGprDigit(name + 1);
    if (n == 0 || n == 1)
      return REG_S0 + n;
    if (n >= 2 && n <= 11)
      return REG_S2 + (n - 2);
  }
  return -1;
}

U0 RVWinRegGprLine(I64 i, I64 v)
{
  if (i == 1)
    Print("  x01/ra = 0x%X\n", v);
  else if (i == 2)
    Print("  x02/sp = 0x%X\n", v);
  else if (i == 3)
    Print("  x03/gp = 0x%X\n", v);
  else if (i == 4)
    Print("  x04/tp = 0x%X\n", v);
  else if (i == 5)
    Print("  x05/t0 = 0x%X\n", v);
  else if (i == 6)
    Print("  x06/t1 = 0x%X\n", v);
  else if (i == 7)
    Print("  x07/t2 = 0x%X\n", v);
  else if (i == 8)
    Print("  x08/s0 = 0x%X\n", v);
  else if (i == 9)
    Print("  x09/s1 = 0x%X\n", v);
  else if (i == 10)
    Print("  x10/a0 = 0x%X\n", v);
  else if (i == 11)
    Print("  x11/a1 = 0x%X\n", v);
  else if (i == 12)
    Print("  x12/a2 = 0x%X\n", v);
  else if (i == 13)
    Print("  x13/a3 = 0x%X\n", v);
  else if (i == 14)
    Print("  x14/a4 = 0x%X\n", v);
  else if (i == 15)
    Print("  x15/a5 = 0x%X\n", v);
  else if (i == 16)
    Print("  x16/a6 = 0x%X\n", v);
  else if (i == 17)
    Print("  x17/a7 = 0x%X\n", v);
  else if (i == 18)
    Print("  x18/s2 = 0x%X\n", v);
  else if (i == 19)
    Print("  x19/s3 = 0x%X\n", v);
  else if (i == 20)
    Print("  x20/s4 = 0x%X\n", v);
  else if (i == 21)
    Print("  x21/s5 = 0x%X\n", v);
  else if (i == 22)
    Print("  x22/s6 = 0x%X\n", v);
  else if (i == 23)
    Print("  x23/s7 = 0x%X\n", v);
  else if (i == 24)
    Print("  x24/s8 = 0x%X\n", v);
  else if (i == 25)
    Print("  x25/s9 = 0x%X\n", v);
  else if (i == 26)
    Print("  x26/s10 = 0x%X\n", v);
  else if (i == 27)
    Print("  x27/s11 = 0x%X\n", v);
  else if (i == 28)
    Print("  x28/t3 = 0x%X\n", v);
  else if (i == 29)
    Print("  x29/t4 = 0x%X\n", v);
  else if (i == 30)
    Print("  x30/t5 = 0x%X\n", v);
  else if (i == 31)
    Print("  x31/t6 = 0x%X\n", v);
  else
    Print("  x%d = 0x%X\n", i, v);
}

U0 RVWinSerialRegs()
{
  I64 cause, mepc, i, v;
  RVWinRegsSnapOnly;
  Print("GPRs (soft snap @ stub entry):\n");
  for (i = 1; i < 32; i++) {
    v = *(I64 *)(MEM_REGS_SNAP + i * 8);
    RVWinRegGprLine(i, v);
  }
  cause = RVWinCsrrMcause();
  mepc = RVWinCsrrMepc();
  Print("regs mstatus=0x%X mie=0x%X mip=0x%X\n", RVWinCsrrMstatus(), RVWinCsrrMie(), RVWinCsrrMip());
  Print("     mepc=0x%X mtval=0x%X sp=0x%X\n", mepc, RVWinCsrrMtval(), GetRSP());
  RVWinMcausePrint(cause, mepc);
  Print("(Fault snap: UART crash> after RVCrashMonInit + fault.)\n");
  RVWinRegsRestoreOnly;
}
// `csrs` — machine/supervisor CSR dump. Direct, like `regs`: no ExePutS JIT in the path, so it
// still works when the compiler is the thing being debugged. Reading a CSR the platform does not
// implement traps, and the REPL's fault recovery now catches that and returns to the prompt
// rather than wedging, so an unimplemented row costs one line instead of the session.
U0 RVWinSerialCsrs()
{
  I64 mc, me;
  Print("Machine:\n");
  Print("  mstatus  =0x%016X  misa   =0x%016X\n", RVWinCsrrMstatus(), RVWinCsrrMisa());
  Print("  mie      =0x%016X  mip    =0x%016X\n", RVWinCsrrMie(), RVWinCsrrMip());
  Print("  mtvec    =0x%016X  mscratch=0x%016X\n", RVWinCsrrMtvec(), RVWinCsrrMscratch());
  Print("  mepc     =0x%016X  mcause =0x%016X\n", RVWinCsrrMepc(), RVWinCsrrMcause());
  Print("  mtval    =0x%016X  mhartid=0x%016X\n", RVWinCsrrMtval(), RVWinCsrrMhartid());
  Print("  medeleg  =0x%016X  mideleg=0x%016X\n", RVWinCsrrMedeleg(), RVWinCsrrMideleg());
  Print("  mcounteren=0x%016X\n", RVWinCsrrMcounteren());
  Print("Supervisor:\n");
  Print("  sstatus  =0x%016X  satp   =0x%016X\n", RVWinCsrrSstatus(), RVWinCsrrSatp());
  Print("  sie      =0x%016X  sip    =0x%016X\n", RVWinCsrrSie(), RVWinCsrrSip());
  Print("  stvec    =0x%016X  sepc   =0x%016X\n", RVWinCsrrStvec(), RVWinCsrrSepc());
  Print("  scause   =0x%016X  stval  =0x%016X\n", RVWinCsrrScause(), RVWinCsrrStval());
  Print("Counters:\n");
  Print("  cycle    =0x%016X  time   =0x%016X\n", RVWinCsrrCycle(), RVWinCsrrTime());
  Print("  instret  =0x%016X\n", RVWinCsrrInstret());
  // Hoisted, not RVWinMcausePrint(RVWinCsrrMcause(), RVWinCsrrMepc()): nested calls in the
  // argument list of a NON-variadic callee wedged here (the same nesting inside the variadic
  // Print()s above is fine, so the two arg paths differ).
  mc = RVWinCsrrMcause();
  me = RVWinCsrrMepc();
  RVWinMcausePrint(mc, me);
}
// HolyC ExePutS symbols (seed/csr.hc not linked into Kernel+Compiler_RV images).
public U0 Regs()
{
  Print("Regs (kernel soft):\n");
  RVWinSerialRegs;
}
// Soft REPL entry points for ExePutS hash (unique names — no HolyC overload).
// RVExePubsWire registers them as Dir/Ls/Pwd/Cd/Help/Man.
// Text-only RedSea walk: Kernel Dir() emits DolDoc $$MA/PutFileLink (hangs on UART),
// and FilesFind (FileNameAbs/DirFilesSort/try) also hung on win serial ExePutS.
// Honest listing = BlkRead cur-dir entries, Print names — no $$ / no FilesFind.
public U0 RVWinSoftDir()
{
  U8 *st, *buf, *buf1;
  CDrv *dv;
  CDirEntry *ptr;
  I64 ch, clus, n, blks;
  st = DirCur;
  if (!st) {
    Print("Dir: Invalid Drive (soft — mount RAM disk first)\n");
    return;
  }
  Print("Dir (soft): %s\n", st);
  Free(st);
  dv = Fs->cur_dv;
  if (!dv || dv->fs_type != FSt_REDSEA) {
    Print("  (no RedSea cwd)\n");
    return;
  }
  clus = Name2DirClus(dv, Fs->cur_dir);
  if (!clus) {
    Print("  (bad dir clus)\n");
    return;
  }
  buf1 = MAlloc(BLK_SIZE);
  if (!buf1 || !BlkRead(dv, buf1, clus, 1)) {
    Free(buf1);
    Print("  (dir read fail)\n");
    return;
  }
  ptr = buf1(U8 *) - offset(CDirEntry.start);
  blks = ptr->size >> BLK_SIZE_BITS;
  if (blks < 1)
    blks = 1;
  buf = MAlloc(blks << BLK_SIZE_BITS);
  if (!buf || !BlkRead(dv, buf, clus, blks)) {
    Free(buf1);
    Free(buf);
    Print("  (dir read fail)\n");
    return;
  }
  Free(buf1);
  ptr = buf(U8 *) - offset(CDirEntry.start);
  n = 0;
  while (TRUE) {
    if (!(ch = *ptr->name))
      break;
    if (!(ptr->attr & RS_ATTR_DELETED)) {
      if (ptr->attr & RS_ATTR_DIR)
        Print("  %s/\n", ptr->name);
      else
        Print("  %s  %d\n", ptr->name, ptr->size);
      n++;
    }
    ptr(U8 *) += CDIR_SIZE;
  }
  Free(buf);
  if (!n)
    Print("  (empty)\n");
  else
    Print("  (%d entries)\n", n);
}

public U0 RVWinSoftLs()
{
  RVWinSoftDir;
}

public U0 RVWinSoftPwd()
{
  U8 *st;
  st = DirCur;
  if (!st) {
    Print("(no cwd)\n");
    return;
  }
  Print("%s\n", st);
  Free(st);
}

public I64 RVWinSoftCd(U8 *dirname)
{
  // ExePub Cd; passes dirname=0 (remat OK). Stock PopUp "Cd;" must stay-put —
  // map null/empty to Cd("") (early TRUE), never stock Cd(NULL)→"~".
  // Real Cd("~") needs RVHomeBringUp (HomeSet A:/Home) on mount.
  if (!dirname || !*dirname)
    return Cd("", FALSE);
  return Cd(dirname, FALSE);
}

public U0 RVWinSoftHelp()
{
  RVWinSerialHelp;
}

public U0 RVWinSoftCat(U8 *name)
{
  // Cat a file into the focused window. PutS rather than Print("%s",…): a .DD file is
  // full of $ commands and % sequences, and Print would try to format the latter.
  // While a Term line is evaluating, PutS is mirrored into the window's CDoc
  // (RVWinTermMirrorPutS -> RVDocPutS -> DocPutS), so DolDoc $-commands in the file
  // are INTERPRETED — which is the point of Cat'ing a .DD.
  U8 *buf;
  I64 sz = 0;
  if (!name || !*name) {
    Print("Cat: need a name — Cat(\"HOME.DD\");\n");
    return;
  }
  buf = FileRead(name, &sz);
  if (!buf) {
    Print("Cat: cannot read %s\n", name);
    return;
  }
  PutS(buf);
  if (sz > 0 && buf[sz - 1] != '\n')
    PutS("\n");
  Free(buf);
}

public U0 RVWinSoftFind(U8 *needle)
{
  // Grep the mounted doc tree (B:/Doc, else A:/Doc) for `needle` and open the results as
  // a browsable DolDoc: one $$LK$$ per matching file, written to A:/Doc/_Find.DD and
  // opened via RVDocOpenLink — so the hits are selectable by the cursor like any links.
  U8 *body, *dir, *buf, line[320], fpath[192];
  CDirEntry *head, *de;
  I64 sz = 0, cap = 16384, pos = 0, ln, matches = 0, scanned = 0;
  if (!needle || !*needle) {
    Print("Find: need a needle — e.g.  find MAlloc\n");
    return;
  }
  dir = "B:/Doc";
  head = FilesFind("B:/Doc/*", 0);
  if (!head) {
    dir = "A:/Doc";
    head = FilesFind("A:/Doc/*", 0);
  }
  body = MAlloc(cap);
  if (!body) {
    if (head)
      DirTreeDel(head);
    return;
  }
  StrPrint(line, "$$FG,LTBLUE$$$$TX,\"Find: %s\"$$$$FG$$\n", needle);
  ln = StrLen(line);
  MemCpy(body, line, ln);
  pos = ln;
  body[pos] = 0;
  de = head;
  while (de && matches < 40 && scanned < 200) {
    if (!(de->attr & RS_ATTR_DIR) && de->name[0]) {
      scanned++;
      StrPrint(fpath, "%s/%s", dir, de->name);
      buf = FileRead(fpath, &sz, NULL);
      if (buf) {
        if (sz > 0 && (StrFind(needle, buf) || StrFind(needle, de->name))) {
          StrPrint(line, "$$LK,\"%s\",A=\"FI:%s\"$$\n", de->name, fpath);
          ln = StrLen(line);
          if (pos + ln < cap - 1) {
            MemCpy(body + pos, line, ln);
            pos += ln;
            body[pos] = 0;
          }
          matches++;
        }
        Free(buf);
      }
    }
    de = de->next;
  }
  if (head)
    DirTreeDel(head);
  StrPrint(line, "\n%d match(es) in %s.  Arrows select, Enter opens.\n", matches, dir);
  ln = StrLen(line);
  if (pos + ln < cap - 1) {
    MemCpy(body + pos, line, ln);
    pos += ln;
    body[pos] = 0;
  }
  DirMk("A:/Doc");
  FileWrite("A:/Doc/_Find.DD", body, StrLen(body));
  Free(body);
  Print("Find: %d match(es) for \"%s\" in %s\n", matches, needle, dir);
  RVDocOpenLink("FI:A:/Doc/_Find.DD");
}

public U0 RVWinSoftEd(U8 *path)
{
  // Full-screen-lite text editor. Loads `path` into an RV_WIN_KIND_EDIT window's CDoc;
  // keys mutate it via DocEdInsChar/Backspace, arrows move the cursor, Ctrl-W saves,
  // Tab leaves. Plain files (HolyC source, notes) round-trip exactly; a $-markup .DD is
  // flattened on save, so edit A: scratch rather than stock docs.
  U8 *buf, tbuf[64], *bn;
  CDoc *doc;
  CRVWin *w;
  I64 sz = 0, i, idx, left, right, top, bottom;
  if (!path || !*path) {
    Print("Ed: need a file — e.g.  ed A:/Doc/scratch.DD\n");
    return;
  }
  bn = path;
  for (i = 0; path[i]; i++)
    if (path[i] == '/' || path[i] == ':')
      bn = path + i + 1;
  if (!*bn)
    bn = "edit";
  StrPrint(tbuf, "%s", bn);
  buf = NULL;
  if (Fs && Fs->cur_dv && !StrMatch("Adam", path))
    buf = FileRead(path, &sz, NULL);
  idx = RVDocFindByTitle(tbuf);
  if (idx < 0) {
    left = 3;
    right = rv_winmgr.cols - 4;
    top = 3;
    bottom = rv_winmgr.rows - 3;
    if (bottom - top < 6)
      bottom = top + 8;
    idx = RVWinNew(left, right, top, bottom, tbuf, "", FALSE);
  }
  if (idx < 0) {
    if (buf)
      Free(buf);
    Print("Ed: cannot open window\n");
    return;
  }
  w = &rv_winmgr.wins[idx];
  w->kind = RV_WIN_KIND_EDIT;
  w->border_attr = GREEN;
  w->show = TRUE;
  if (w->doc) {
    DocDel(w->doc);
    w->doc = NULL;
  }
  doc = DocNew(tbuf);
  if (doc) {
    if (buf && sz > 0)
      DocPutS(doc, buf);
    doc->cur_entry = doc;   // sentinel == insert at end of doc
    DocRecalc(doc);
    w->doc = doc;
  }
  if (buf)
    Free(buf);
  StrPrint(rv_win_edit_path, "%s", path);
  rv_win_edit_dirty = 0;
  RVWinFocus(idx);
  Print("Ed: %s (%d bytes) \x97 type to edit, arrows move, Ctrl-W save, Esc leave\n", path, sz);
}

public U0 RVWinSoftTasks()
{
  //List the desktop windows and their task bindings — the visible face of the
  // multitasking the WinMgr already runs (Term/HOME/User are live RVKSpawn GetMsg tasks).
  I64 i, n = 0;
  CRVWin *w;
  U8 *kn;
  Print("Windows / tasks:\n");
  for (i = 0; i < RV_WIN_MAX; i++) {
    w = &rv_winmgr.wins[i];
    if (!w->used)
      continue;
    if (w->kind == RV_WIN_KIND_ADAM)
      kn = "Adam";
    else if (w->kind == RV_WIN_KIND_TERM)
      kn = "Term";
    else if (w->kind == RV_WIN_KIND_HOME)
      kn = "HOME";
    else if (w->kind == RV_WIN_KIND_USER)
      kn = "User";
    else if (w->kind == RV_WIN_KIND_EDIT)
      kn = "Edit";
    else
      kn = "Doc ";
    Print("  [%d]%c %s  \"%s\"  task=%s show=%d\n", i,
      i == rv_winmgr.focus ? '*' : ' ', kn, w->title,
      TaskValidate(w->task) ? "live" : "-", w->show);
    n++;
  }
  Print("%d window(s), focus=%d.  Tab cycles, `user` spawns a Term, max/tileh/tilev layout.\n",
    n, rv_winmgr.focus);
}

U0 RVWinEdExit()
{
  //Leave the editor: focus the Term (else Adam) so you can run what you just saved.
  // The editor window stays open — Tab back to keep editing.
  I64 t = rv_winmgr.term_idx;
  if (t < 0 || t >= RV_WIN_MAX || !rv_winmgr.wins[t].used)
    t = rv_winmgr.adam_idx;
  if (t >= 0 && t < RV_WIN_MAX && rv_winmgr.wins[t].used) {
    RVWinFocus(t);
    Print("Ed: left editor (focus Term) — run it: #include \"%s\"\n", rv_win_edit_path);
  }
}

U0 RVWinEdSave()
{
  U8 *buf;
  I64 n, idx = rv_winmgr.focus;
  CRVWin *w;
  if (!RVWinDocFocusIsEdit())
    return;
  w = &rv_winmgr.wins[idx];
  buf = MAlloc(65536);
  if (!buf)
    return;
  n = RVDocEdExtractText(w->doc, buf, 65536);
  FileWrite(rv_win_edit_path, buf, n);
  Free(buf);
  rv_win_edit_dirty = 0;
  Print("Ed: wrote %s (%d bytes)\n", rv_win_edit_path, n);
}

public U0 RVWinSoftMan(U8 *name)
{
  if (!name || !*name) {
    Print("Man: need a name — Man(\"Print\"); (full pages on repl-holyc)\n");
    return;
  }
  Print("Man(\"%s\"): soft stub — symbol docs live on repl-holyc Man/seed\n", name);
}

public I64 Reg(U8 *name)
{
  I64 v, gi;
  if (!name)
    return -1;
  gi = RVWinRegGprIndex(name);
  if (gi >= 0) {
    RVWinRegsSnapOnly;
    v = *(I64 *)(MEM_REGS_SNAP + gi * 8);
    Print("Reg(\"%s\")=0x%X\n", name, v);
    return v;
  }
  if (!StrICmp(name, "mstatus")) {
    v = RVWinCsrrMstatus();
    Print("Reg(\"%s\")=0x%X\n", name, v);
    return v;
  }
  if (!StrICmp(name, "mie")) {
    v = RVWinCsrrMie();
    Print("Reg(\"%s\")=0x%X\n", name, v);
    return v;
  }
  if (!StrICmp(name, "mip")) {
    v = RVWinCsrrMip();
    Print("Reg(\"%s\")=0x%X\n", name, v);
    return v;
  }
  if (!StrICmp(name, "mepc")) {
    v = RVWinCsrrMepc();
    Print("Reg(\"%s\")=0x%X\n", name, v);
    return v;
  }
  if (!StrICmp(name, "mcause")) {
    v = RVWinCsrrMcause();
    Print("Reg(\"%s\")=0x%X\n", name, v);
    return v;
  }
  if (!StrICmp(name, "mtval")) {
    v = RVWinCsrrMtval();
    Print("Reg(\"%s\")=0x%X\n", name, v);
    return v;
  }
  Print("Reg(\"%s\"): unknown (try a0/sp/ra/xN or mstatus/mie/mip/mepc/mcause/mtval)\n", name);
  return -1;
}
// Next frame from s0: prefer gcc/expr (ra@s0-8, s0@s0-16), else HolyC ENTER
// (ra@s0-N, s0@s0-N+8 for N=16..512). Returns 1 and fills *ra_out/*s0_out.
I64 RVWinSerialBtFrameNext(I64 s0, I64 *ra_out, I64 *s0_out)
{
  I64 ra, ps0, N;
  *ra_out = 0;
  *s0_out = 0;
  if (!RVWinSerialInRam(s0) || (s0 & 7))
    return 0;
  if (RVWinSerialInRam(s0 - 16)) {
    ra = *(I64 *)(s0 - 8);
    ps0 = *(I64 *)(s0 - 16);
    if (RVWinSerialInCode(ra) && (RVWinSerialInStk(ps0) || RVWinSerialInRam(ps0))) {
      *ra_out = ra;
      *s0_out = ps0;
      return 1;
    }
  }
  // HolyC IC_ENTER: sd ra,0(sp); sd s0,8(sp); addi s0,sp,N
  for (N = 16; N <= 512; N += 8) {
    if (!RVWinSerialInRam(s0 - N))
      continue;
    ra = *(I64 *)(s0 - N);
    ps0 = *(I64 *)(s0 - N + 8);
    if (!RVWinSerialInCode(ra))
      continue;
    if (ps0 && !RVWinSerialInRam(ps0))
      continue;
    *ra_out = ra;
    *s0_out = ps0;
    return 1;
  }
  return 0;
}
// Static nearest-below map — FunSegFind is a Kernel stub; HashFind can hang.
// Addresses filled by RVWinSerialSymWire (after all & targets exist).
#define RV_WIN_SYM_MAX 16
I64 rv_win_sym_addr[RV_WIN_SYM_MAX];
U8 *rv_win_sym_nm[RV_WIN_SYM_MAX];
I64 rv_win_sym_n;
U0 RVWinSerialSymCand(I64 addr, I64 cand, U8 *nm, I64 *best_d, U8 **best_nm)
{
  I64 d;
  if (!cand || !nm || cand > addr)
    return;
  d = addr - cand;
  if (d > 0x8000)
    return;
  if (*best_d < 0 || d < *best_d) {
    *best_d = d;
    *best_nm = nm;
  }
}

U8 *RVWinSerialSymName(I64 addr)
{
  I64 best, i;
  U8 *nm;
  if (!RVWinSerialInCode(addr) || rv_win_sym_n <= 0)
    return NULL;
  best = -1;
  nm = NULL;
  for (i = 0; i < rv_win_sym_n; i++)
    RVWinSerialSymCand(addr, rv_win_sym_addr[i], rv_win_sym_nm[i], &best, &nm);
  if (best < 0)
    return NULL;
  return nm;
}

U0 RVWinSerialBtPrint(I64 n, I64 pc)
{
  U8 *sym;
  sym = RVWinSerialSymName(pc);
  if (sym)
    Print("  #%d 0x%X %s\n", n, pc, sym);
  else
    Print("  #%d 0x%X\n", n, pc);
}

U0 RVWinSerialBt(I64 max = 16)
{
  I64 sp, fp, ra, ps0, cur, i, n, seen[16];
  if (max <= 0)
    max = 16;
  if (max > 16)
    max = 16;
  sp = GetRSP();
  // Capture live ra/s0 before further HolyC calls smash them (same idea as seed Bt).
  // Scratch under SYS_FIXED_AREA — not a trap snap; dig-down has no GPR freeze.
  asm {
	lui	t6, 0x10E00
	slli	t6, t6, 3
	sd	ra, 0x200(t6)
	sd	s0, 0x208(t6)
  }
  ra = *(I64 *)0x87000200;
  fp = *(I64 *)0x87000208;
  Print("bt live fp=0x%X sp=0x%X (code PCs only; no trap snap)\n", fp, sp);
  n = 0;
  cur = ra;
  if (!RVWinSerialInCode(cur)) {
    Print("  (no live code PC — try fault → crash> bt for mepc)\n");
    return;
  }
  RVWinSerialBtPrint(n, cur);
  seen[n++] = cur;
  // Advance from our frame to the caller's saved s0 (cur should match saved ra).
  if (!RVWinSerialBtFrameNext(fp, &ra, &ps0)) {
    Print("  (stopped — no FP chain)\n");
    return;
  }
  if (ra != cur && RVWinSerialInCode(ra)) {
    // Unusual layout: print the frame-next ra too if distinct.
    for (i = 0; i < n; i++)
      if (seen[i] == ra)
        break;
    if (i >= n && n < max) {
      RVWinSerialBtPrint(n, ra);
      seen[n++] = ra;
    }
  }
  fp = ps0;
  while (n < max) {
    if (!RVWinSerialBtFrameNext(fp, &ra, &ps0))
      break;
    if (!RVWinSerialInCode(ra))
      break;
    for (i = 0; i < n; i++)
      if (seen[i] == ra || seen[i] == fp)
        break;
    if (i < n)
      break;
    // cycle / repeat
    if (ps0 == fp)
      break;
    RVWinSerialBtPrint(n, ra);
    seen[n++] = ra;
    if (!ps0 || !RVWinSerialInRam(ps0))
      break;
    fp = ps0;
  }
  if (n >= max)
    Print("  (cap %d)\n", max);
}
// Do not add public Bt() — TempleOS Bt(bitmap,bit) is the bit-test intrinsic.
U0 RVWinSerialMd(I64 addr, I64 n = 64)
{
  I64 i, b;
  if (!RVWinSerialInRam(addr) || n <= 0) {
    Print("md: bad addr/len (DRAM 0x80000000..0x88000000)\n");
    return;
  }
  if (n > 0x1000)
    n = 0x1000;
  for (i = 0; i < n; i++) {
    if ((i & 15) == 0)
      Print("%08X:", addr + i);
    b = *(U8 *)(addr + i);
    Print(" %02X", b);
    if ((i & 15) == 15)
      Print("\n");
  }
  if (n & 15)
    Print("\n");
}

U0 RVWinSerialMw(I64 addr, I64 val)
{
  if (!RVWinSerialInRam(addr)) {
    Print("mw: bad addr (DRAM only)\n");
    return;
  }
  *(I64 *)addr = val;
  Print("mw *0x%X = 0x%X\n", addr, val);
}

U0 RVWinSerialFault()
{
  // Soft RX must not drain HW FIFO during fault Print — host CrashMon reads
  // LSR/RBR directly (go/q would land in the soft ring and be invisible).
  RVUartSoftOn(0);
  Print("RVWinSerial: deliberate fault → UART crash>\n");
  RVWinSerialFaultAsm();
  RVUartSoftOn(1);
}

U0 RVWinSerialPrompt()
{
  Print("> ");
}
// Soft-parse Reg("name"); without mid-block locals (host AOT corrupts those).
U0 RVWinSerialSoftReg(U8 *p)
{
  U8 name[32];
  I64 ni, j;
  ni = 0;
  j = 3;
  while (p[j] == ' ' || p[j] == '\t')
    j++;
  if (p[j] == '(')
    j++;
  while (p[j] == ' ' || p[j] == '\t' || p[j] == '"')
    j++;
  while (p[j] && p[j] != '"' && p[j] != ')' && p[j] != ';' && ni < 31)
    name[ni++] = p[j++];
  name[ni] = 0;
  if (ni)
    Reg(name);
  else
    Print("Reg: need a name — Reg(\"a0\");\n");
}

Bool RVWinSerialDispatch2(U8 *line)
{
  U8 *p, *q;
  I64 addr, n, val, r;
  if (!line)
    return FALSE;
  p = RVWinSerialSkip(line);
  if (!*p)
    return FALSE;
  rv_win_serial_cmds++;
  if (RVWinSerialCmdEq(p, "help") || RVWinSerialCmdEq(p, "?")) {
    RVWinSerialHelp;
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "csrs") || RVWinSerialCmdEq(p, "csr")) {
    RVWinSerialCsrs();
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "regs")) {
    // Direct — avoid ExePutS JIT for Regs; (null export / CALL_IMPORT risk).
    Print("Regs (kernel soft):\n");
    RVWinSerialRegs();
    return FALSE;
  }
  // Reg("a0"); / Reg("mstatus"); — parse without JIT (same reliability as regs).
  if ((p[0] == 'R' || p[0] == 'r') && p[1] == 'e' && p[2] == 'g' && (p[3] == '(' || p[3] == ' ')) {
    RVWinSerialSoftReg(p);
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "dir") || RVWinSerialCmdEq(p, "ls")) {
    RVWinSoftDir;
    return FALSE;
  }
  // Find/Ed/Tasks are planted as real HolyC functions (RVExePubs.HC) so they run through
  // the compiler like Cat/Dir: type `Find("Queue"); Ed("A:/x"); Tasks;` at the prompt.
  // No dispatch bareword — the crash-shell sidecar stays for md/mw/regs/crash only.
  if (RVWinSerialCmdEq(p, "bt")) {
    RVWinSerialBt;
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "md")) {
    q = RVWinSerialSkipTok(p);
    addr = Str2I64(q);
    q = RVWinSerialSkipTok(q);
    n = 64;
    if (*q)
      n = Str2I64(q);
    RVWinSerialMd(addr, n);
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "mw")) {
    q = RVWinSerialSkipTok(p);
    addr = Str2I64(q);
    q = RVWinSerialSkipTok(q);
    val = Str2I64(q);
    RVWinSerialMw(addr, val);
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "fault")) {
    RVWinSerialFault;
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "crash")) {
    Print("RVWinSerial: entering crash> (host mon; 'go' returns)\n");
    RVUartIrqOff();       // crash mon polls the UART itself; RX IRQ would eat its input
    RVCrashMon();
    RVUartIrqInit();
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "q") || RVWinSerialCmdEq(p, "quit")) {
    rv_winmgr.want_quit = TRUE;
    Print("RVWinSerial: quit WinMgr\n");
    return TRUE;
  }
  if (RVWinSerialCmdEq(p, "max")) {
    RVWinMax(-1);
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "tileh")) {
    RVWinTileHorz;
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "tilev")) {
    RVWinTileVert;
    return FALSE;
  }
  if (RVWinSerialCmdEq(p, "user")) {
    RVWinSpawnUser(NULL);
    return FALSE;
  }
  if (RVWinSerialEval) {
    r = RVWinSerialEval(p);
    // A U0 statement (Cat("x"); Dir; …) leaves nothing meaningful in a0, so the old
    // unconditional print showed whatever happened to be there — `ans=2196234160`
    // after a Cat. ExePutS records the real type per statement in Fs->answer_type.
    if (Fs && Fs->answer_type == RT_U0)
      Print("\n");
    else
      Print("ans=%d\n", r);
    return FALSE;
  }
  Print("?\n");
  return FALSE;
}


// Arm the fault/^C recovery point around the WHOLE dispatch, not just the evaluated statement:
// a wedge inside a built-in (`regs`, `csrs`) is exactly as worth escaping as one inside HolyC.
// One-shot and disarmed on every exit — the trampoline restores ra/sp/fp captured here, so
// leaving it armed after this frame returns would jump into a dead frame.
Bool RVWinSerialDispatch(U8 *line)
{
  Bool res;
  I64 cause;
  if (RVTrapRecoverArm()) {
    cause = RVTrapRecoverCause();
    RVTrapRecoverDisarm();
    if (cause < 0) {
      Print("\n^C — interrupted, back at the prompt\n");
      return FALSE;
    }
    if (cause == 3) {
      // Bp(): report the hit and restore every planted EBREAK; the line is abandoned.
      Print("\n*** breakpoint at %08X", RVTrapRecoverEpc());
      RVBpSymPrint(RVTrapRecoverEpc());
      Print(" — Bp cleared, back at the prompt\n    ra=%08X\n", RVTrapRecoverRa());
      RVBpRestoreAll();
      return FALSE;
    }
    Print("\n*** fault in that line — back at the prompt (`crash` for the monitor)\n");
    Print("    mcause=%d (%s) mepc=%08X mtval=%08X\n    ra=%08X\n",
	  cause, RVWinMcauseName(cause),
	  RVTrapRecoverEpc(), RVTrapRecoverTval(), RVTrapRecoverRa());
    return FALSE;
  }
  // RX interrupt ON only while the command runs. The input pump is not polling during this
  // window, so the ISR cannot race it; that race made keystrokes vanish after any large dump.
  // Anything typed meanwhile lands in the runtime ring and is drained below, in normal context.
  RVUartIrqInit();
  res = RVWinSerialDispatch2(line);
  RVUartIrqOff();
  while ((cause = RVUartGetBuffered()) >= 0)
    RVUartSoftEnqueue(cause & 0xFF);
  RVTrapRecoverDisarm();
  return res;
}

U0 RVWinSerialPutEcho(I64 ch)
{
  U8 e[2];
  e[0] = ch;
  e[1] = 0;
  RVUartPutS(e);
}

Bool RVWinTermMirrorPutS(U8 *st)
{
  //KeyDev mirror while Term/User/Adam line is evaluating — UART Print fills the app body.
  if (!st)
    return FALSE;
  if (rv_win_term_mirror) {
    RVDocPutS(st);
    return TRUE;
  }
  if (rv_win_adam_mirror) {
    RVWinBodyAppend(rv_winmgr.adam_idx, st);
    return TRUE;
  }
  return FALSE;
}

U0 RVWinTermPrompt()
{
  RVDocPutS("> ");
}

U0 RVWinAdamPrompt()
{
  RVWinBodyAppend(rv_winmgr.adam_idx, "> ");
}

U0 RVWinTermPutChar(I64 ch)
{
  //Virtio Term/User REPL: echo into focus body; Enter → RVWinSerialDispatch (ExePutS).
  U8 e[2];
  I64 len, idx, kind;
  CRVWin *w;
  if (ch == '\t') {
    RVWinFocusNext;
    return;
  }
  // Text editor window focused (ed <file>): keys mutate the CDoc. Ctrl-W saves, arrows
  // move the cursor (via the escape decoder), Tab (above) leaves. This is checked before
  // the nav branch since an EDIT window is not a link browser.
  if (RVWinDocFocusIsEdit()) {
    CRVWin *ew = &rv_winmgr.wins[rv_winmgr.focus];
    if (ch == 27)
      RVWinSerialEscKey;                    // arrows -> RVDocEdMove
    else if (ch == 23)                      // Ctrl-W: write
      RVWinEdSave;
    else if (ch == 8 || ch == 127) {
      DocEdBackspace(ew->doc);
      rv_win_edit_dirty = 1;
    } else if (ch == '\n' || ch == '\r') {
      DocEdInsChar(ew->doc, '\n');
      rv_win_edit_dirty = 1;
    } else if (ch >= 32 && ch < 127) {
      DocEdInsChar(ew->doc, ch);
      rv_win_edit_dirty = 1;
    }
    return;
  }
  // Browsable DolDoc window focused (Tab cycles here): arrows move the link cursor
  // (via the escape decoder), Enter follows the selected link, everything else is
  // swallowed. Tab (above) returns to the Term. REPL semantics resume when the Term
  // or a User window is focused.
  if (RVWinDocFocusIsNav()) {
    if (ch == 27)
      RVWinSerialEscKey;
    else if (ch == '\n' || ch == '\r')
      RVWinDocFocusActivate;
    return;
  }
  idx = rv_winmgr.focus;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    idx = rv_winmgr.term_idx;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    return;
  w = &rv_winmgr.wins[idx];
  kind = w->kind;
  // 127 (DEL) as well as 8 (^H): a VT100/xterm Backspace key sends DEL, and without
  // it the key fell through to the printable test below — which excludes 127 — so it
  // was silently dropped and backspace did nothing. RVWinSerialPoll already accepted
  // both; these two entry points did not.
  if (ch == 8 || ch == 127) {
    if (rv_win_term_len > 0) {
      rv_win_term_len--;
      rv_win_term_line[rv_win_term_len] = 0;
      len = RVWinBodyLen(w->body);
      if (len > 0)
        w->body[len - 1] = 0;
      // A doc-backed window renders from the CDoc, not from body, so truncating body
      // alone leaves the erased character on screen (same pairing RVWinBodyPutChar
      // uses in RVWinMgr.HC).
      if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL)
        DocEdBackspace(w->doc);
    }
    return;
  }
  if (ch == 27) {
    // VT cursor keys (PgUp/PgDn/arrows/Home/End) page the console history; the escape
    // sequence is consumed here so it never lands in the line.
    RVWinSerialEscKey;
    return;
  }
  if (ch == '\n' || ch == '\r') {
    RVWinBodyAppend(idx, "\n");
    rv_win_term_line[rv_win_term_len] = 0;
    rv_win_term_mirror = 1;
    RVWinSerialTermScroll(0, FALSE, TRUE);   // new output: leave scrollback
    RVWinSerialDispatch(rv_win_term_line);
    rv_win_term_mirror = 0;
    rv_win_term_len = 0;
    if (kind == RV_WIN_KIND_USER)
      rv_winmgr.user_cmds++;
    else
      rv_win_term_cmds++;
    if (!rv_winmgr.want_quit) {
      if (kind == RV_WIN_KIND_USER)
        RVWinBodyAppend(idx, "> ");
      else
        RVWinTermPrompt;
    }
    return;
  }
  if (ch >= 32 && ch < 127 && rv_win_term_len < RV_WIN_SERIAL_LINE_MAX - 1) {
    rv_win_term_line[rv_win_term_len++] = ch;
    e[0] = ch;
    e[1] = 0;
    RVWinBodyAppend(idx, e);
  }
}

U0 RVWinAdamPutChar(I64 ch)
{
  //Virtio Adam REPL (TempleOS Adam task DocPutKey → ExePutS shape).
  U8 e[2];
  I64 len, idx;
  CRVWin *w;
  idx = rv_winmgr.adam_idx;
  if (ch == '\t') {
    RVWinFocusNext;
    return;
  }
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    return;
  w = &rv_winmgr.wins[idx];
  if (ch == 8 || ch == 127) {
    if (rv_win_adam_len > 0) {
      rv_win_adam_len--;
      rv_win_adam_line[rv_win_adam_len] = 0;
      len = RVWinBodyLen(w->body);
      if (len > 0)
        w->body[len - 1] = 0;
      if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL)
        DocEdBackspace(w->doc);
    }
    return;
  }
  if (ch == '\n' || ch == '\r') {
    RVWinBodyAppend(idx, "\n");
    rv_win_adam_line[rv_win_adam_len] = 0;
    rv_win_adam_mirror = 1;
    RVWinSerialDispatch(rv_win_adam_line);
    rv_win_adam_mirror = 0;
    rv_win_adam_len = 0;
    rv_win_adam_cmds++;
    if (!rv_winmgr.want_quit)
      RVWinAdamPrompt;
    return;
  }
  if (ch >= 32 && ch < 127 && rv_win_adam_len < RV_WIN_SERIAL_LINE_MAX - 1) {
    rv_win_adam_line[rv_win_adam_len++] = ch;
    e[0] = ch;
    e[1] = 0;
    RVWinBodyAppend(idx, e);
  }
}

I64 RVWinSerialEscGet()
{
  // The rest of an escape sequence arrives within a few bytes; bounded spin so a bare
  // ESC (or a slow terminal) cannot wedge the pump.
  I64 ch, spins = 0;
  while (spins++ < 200000) {
    ch = RVUartTryGet;
    if (ch >= 0)
      return ch;
  }
  return -1;
}

U0 RVWinSerialTermScroll(I64 delta, Bool absolute_top, Bool absolute_bottom)
{
  I64 idx = rv_winmgr.term_idx, h;
  CRVWin *w;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return;
  w = &rv_winmgr.wins[idx];
  if (!w->used)
    return;
  h = w->bottom - w->top + 1;
  if (absolute_bottom)
    w->scroll_y = 0;
  else if (absolute_top)
    w->scroll_y = -1000000;
  else
    w->scroll_y += delta;
  RVWinClampScroll(idx);
}

U0 RVWinSerialEscKey()
{
  I64 ch, param = 0, h = 20, idx = rv_winmgr.term_idx;
  if (idx >= 0 && idx < RV_WIN_MAX && rv_winmgr.wins[idx].used)
    h = rv_winmgr.wins[idx].bottom - rv_winmgr.wins[idx].top + 1;
  ch = RVWinSerialEscGet;
  if (ch != '[' && ch != 'O') {
    // Bare ESC (no CSI): in the editor it means "leave" → focus the Term to run the file.
    if (RVWinDocFocusIsEdit())
      RVWinEdExit;
    return;
  }
  ch = RVWinSerialEscGet;
  while (ch >= '0' && ch <= '9') {
    param = param * 10 + ch - '0';
    ch = RVWinSerialEscGet;
  }
  while (ch == ';') {          // drop modifier params
    ch = RVWinSerialEscGet;
    while (ch >= '0' && ch <= '9')
      ch = RVWinSerialEscGet;
  }
  // Editor window focused: arrows move the text cursor (RVDocEdMove).
  if (RVWinDocFocusIsEdit()) {
    CRVWin *ew = &rv_winmgr.wins[rv_winmgr.focus];
    if (ch == 'A')
      RVDocEdMove(ew->doc, -2);   // up
    else if (ch == 'B')
      RVDocEdMove(ew->doc, 2);    // down
    else if (ch == 'C')
      RVDocEdMove(ew->doc, 1);    // right
    else if (ch == 'D')
      RVDocEdMove(ew->doc, -1);   // left
    return;
  }
  // When a browsable DolDoc window is focused, the arrows move the link cursor instead
  // of scrolling the Term (Up/Left = previous link, Down/Right = next; Enter follows).
  if (RVWinDocFocusIsNav()) {
    if (ch == 'A' || ch == 'D')
      RVWinDocFocusSelMove(-1);
    else if (ch == 'B' || ch == 'C')
      RVWinDocFocusSelMove(1);
    return;
  }
  if (ch == 'A')
    RVWinSerialTermScroll(-1, FALSE, FALSE);
  else if (ch == 'B')
    RVWinSerialTermScroll(1, FALSE, FALSE);
  else if (ch == 'H' || (ch == '~' && param == 1))
    RVWinSerialTermScroll(0, TRUE, FALSE);
  else if (ch == 'F' || (ch == '~' && param == 4))
    RVWinSerialTermScroll(0, FALSE, TRUE);
  else if (ch == '~' && param == 5)
    RVWinSerialTermScroll(-(h - 1), FALSE, FALSE);
  else if (ch == '~' && param == 6)
    RVWinSerialTermScroll(h - 1, FALSE, FALSE);
}

U0 RVWinSerialPoll()
{
  //Non-blocking soft-RX drain. At most one full line (or a small char budget)
  //per WinMgr tick so ExePutS / PutS cannot starve VirtioInput for the FB loop.
  I64 ch, budget = 256;
  if (!rv_win_serial_ready)
    return;
  while (budget-- > 0) {
    ch = RVUartTryGet;
    if (ch < 0)
      break;
    if (ch == '\r' || ch == '\n') {
      RVUartPutS("\n");
      rv_win_serial_line[rv_win_serial_len] = 0;
      RVWinSerialTermScroll(0, FALSE, TRUE);   // new output: leave scrollback
      RVWinSerialDispatch(rv_win_serial_line);
      rv_win_serial_len = 0;
      if (!rv_winmgr.want_quit)
        RVWinSerialPrompt;
      // One statement per tick — return so RVWinMgrRun can pump virtio-kbd/tablet.
      break;
    }
    if (ch == 3) {
      rv_win_serial_len = 0;
      RVUartPutS("^C\n");
      RVWinSerialPrompt;
      continue;
    }
    if (ch == 27) {
      // VT cursor keys: ESC [ params final. PgUp/PgDn page the Term doc, arrows step a
      // line, Home/End jump. Anything else is swallowed (no escape garbage in the line).
      RVWinSerialEscKey;
      continue;
    }
    if (ch == 8 || ch == 127) {
      if (rv_win_serial_len > 0) {
        rv_win_serial_len--;
        RVUartPutS("\b \b");
      }
      continue;
    }
    if (ch >= 32 && ch < 127 && rv_win_serial_len < RV_WIN_SERIAL_LINE_MAX - 1) {
      rv_win_serial_line[rv_win_serial_len++] = ch;
      RVWinSerialPutEcho(ch);
    }
  }
}

U0 RVWinSerialSymAdd(I64 addr, U8 *nm)
{
  if (rv_win_sym_n >= RV_WIN_SYM_MAX || !addr || !nm)
    return;
  rv_win_sym_addr[rv_win_sym_n] = addr;
  rv_win_sym_nm[rv_win_sym_n] = nm;
  rv_win_sym_n++;
}
// Called from Init once all dig-down targets exist (no forward & at parse time).
U0 RVWinSerialSymWire()
{
  if (rv_win_sym_n)
    return;
  RVWinSerialSymAdd(&RVWinSerialBt, "RVWinSerialBt");
  RVWinSerialSymAdd(&RVWinSerialDispatch, "RVWinSerialDispatch");
  RVWinSerialSymAdd(&RVWinSerialPoll, "RVWinSerialPoll");
  RVWinSerialSymAdd(&RVWinSerialRegs, "RVWinSerialRegs");
  RVWinSerialSymAdd(&Regs, "Regs");
  RVWinSerialSymAdd(&Reg, "Reg");
  RVWinSerialSymAdd(&RVWinMgrRun, "RVWinMgrRun");
}

Bool RVWinSerialInit()
{
  if (rv_win_serial_ready)
    return TRUE;
  RVUartSoftOn(1);
  RVTrapInit();
  RVCrashMonInit();

  RVWinSerialSymWire;
  rv_win_serial_ready = TRUE;
  rv_win_serial_len = 0;
  rv_win_serial_cmds = 0;
  rv_win_term_len = 0;
  rv_win_term_cmds = 0;
  rv_win_term_mirror = 0;
  rv_win_adam_len = 0;
  rv_win_adam_cmds = 0;
  rv_win_adam_mirror = 0;
  // Mirror Print into Term/Adam only while that app's Dispatch is active.
  RVConsoleMirrorPutS = &RVWinTermMirrorPutS;
  if (RVWinSerialEval)
    Print("RVWinSerial ready soft=%d crash_mon=1 ExePutS REPL (HolyC UART+Term; fault; q)\n", RVUartSoftGet);
  else
    Print("RVWinSerial ready soft=%d crash_mon=1 (help; regs; bt; fault; q)\n", RVUartSoftGet);
  RVWinSerialPrompt;
  return TRUE;
}

Bool RVWinSerialVtQuerySize(I64 *cols, I64 *rows)
{
  //Ask the terminal for its size (CSI 18 t -> CSI 8 ; rows ; cols t). Bounded spin; FALSE
  //when nothing answers (piped stdin, dumb terminal) so callers keep their defaults.
  I64 ch, spins = 0, st = 0, r = 0, c = 0;
  U8 q[8];
  q[0] = 27;   // the host lexer has no \x escapes: build CSI 18 t by hand
  q[1] = '[';
  q[2] = '1';
  q[3] = '8';
  q[4] = 't';
  q[5] = 0;
  RVUartPutS(q);
  while (spins < 4000000) {
    ch = RVUartTryGet;
    if (ch < 0) {
      spins++;
      continue;
    }
    if (st == 0) {
      if (ch == 27)
        st = 1;
    } else if (st == 1) {
      st = 0;
      if (ch == '[')
        st = 2;
    } else if (st == 2) {
      st = 0;
      if (ch == '8')
        st = 3;
    } else if (st == 3) {
      st = 0;
      if (ch == ';')
        st = 4;
    } else if (st == 4) {
      if (ch >= '0' && ch <= '9')
        r = r * 10 + ch - '0';
      else if (ch == ';')
        st = 5;
      else
        st = 0;
    } else if (st == 5) {
      if (ch >= '0' && ch <= '9')
        c = c * 10 + ch - '0';
      else if (ch == 't') {
        if (r >= 10 && r <= 120 && c >= 40 && c <= 300) {
          *rows = r;
          *cols = c;
          return TRUE;
        }
        return FALSE;
      } else
        st = 0;
    }
  }
  return FALSE;
}
