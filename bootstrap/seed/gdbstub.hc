// gdbstub.hc -- GDB Remote Serial Protocol (RSP) over UART (G23 slice).
// Prefer early-boot load (BootHolyCRuntime after hwdbg) so GdbStub; works without
// post-seal Run (JIT Run of this file has hung on tip). Memfs copy still allows
// Run("Boot/gdbstub.hc"); when heap allows.
// Soft Regs/Bp/Watch stay in debug.hc; host qemu-gdbstub stays hwdbg-smoke.
//
// g/G: inline asm snap into MEM_REGS_SNAP (csr.hc RegsSnapOnly pattern — no Hc*).
// Z0/z0: silent ebreak patch via DbgActive/DbgAddr/DbgSaved (same table as Bp/BpClr).
// c: S05 remain stopped (cooperative stub — no guest resume while attached).
// s: soft-step arm (Step semantics: one-shot ebreak at next insn) then S05.
// Transport: raw UART + $HC_GDB$ / $HC_GDB_END$ (make gdb-uart-smoke).
// Mux ch2: GdbUseMux(1) flag + Run("Lib/frame.hc"); UartMuxOn; stub TX stays raw.
//
// Packets: ?, g, G, m, M, p, Z0, z0, qSupported, qAttached, qC, H,
// qf/qsThreadInfo, vMustReplyEmpty, D/k. Dig-down: docs/DEBUGGER.md § UART GDB RSP.
#define GDB_PKT_MAX 600
#define GDB_MEM_MAX 128
#define GDB_MUX_CH 2
I64 g_gdb_mux_ch;
I64 g_gdb_pc;
I64 g_gdb_fc_saved;
U8 g_gdb_pkt[GDB_PKT_MAX];
U8 g_gdb_out[GDB_PKT_MAX];
// GdbUseMux -- reserved flag (ch2 TX round-trip still host-side WIP)
U0 GdbUseMux(I64 on)
{
  if (on)
    g_gdb_mux_ch = GDB_MUX_CH;
  else
    g_gdb_mux_ch = 0;
  // TX stays raw UartPut; flag documents intent for uart_mux.py dbg lane.
}
// ---- always raw UartPut (bypasses PutCh / framed ch0) ----
U0 GdbPut(I64 ch)
{
  UartPut(ch & 255);
}

I64 GdbGet()
{
  return HcUartGet();
}

U0 GdbPutStr(U8 *s)
{
  if (!s)
    return;
  while (*s)
    GdbPut (*s++);
}

I64 GdbHexN(I64 c)
{
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}

U0 GdbPutHexByte(I64 n)
{
  I64 d;
  n &= 255;
  d = n >> 4;
  if (d < 10)
    GdbPut('0' + d);
  else
    GdbPut('a' + d - 10);
  d = n & 15;
  if (d < 10)
    GdbPut('0' + d);
  else
    GdbPut('a' + d - 10);
}

I64 GdbEmitHexByteCs(I64 b, I64 cs)
{
  I64 d, ch;
  b &= 255;
  d = b >> 4;
  if (d < 10)
    ch = '0' + d;
  else
    ch = 'a' + d - 10;
  GdbPut(ch);
  cs = (cs + ch) & 0xFF;
  d = b & 15;
  if (d < 10)
    ch = '0' + d;
  else
    ch = 'a' + d - 10;
  GdbPut(ch);
  cs = (cs + ch) & 0xFF;
  return cs;
}

I64 GdbParseHex(U8 *p, I64 *out)
{
  I64 v, n, d;
  v = 0;
  n = 0;
  while (1) {
    d = GdbHexN (*p);
    if (d < 0)
      break;
    v = (v << 4) | d;
    p++;
    n++;
  }
  *out = v;
  return n;
}

I64 GdbChecksum(U8 *p)
{
  I64 s;
  s = 0;
  while (*p) {
    s = (s + (*p & 255)) & 0xFF;
    p++;
  }
  return s;
}

U0 GdbSendPacket(U8 *body)
{
  I64 cs;
  if (!body)
    body = "";
  cs = GdbChecksum(body);
  GdbPut('$');
  GdbPutStr(body);
  GdbPut('#');
  GdbPutHexByte(cs);
}

I64 GdbRecvPacket()
{
  I64 c, n, cs, d0, d1, sum;
  while (1) {
    c = GdbGet() & 255;
    if (c == 3) {
      g_gdb_pkt[0] = '?';
      g_gdb_pkt[1] = 0;
      return 1;
    }
    if (c != '$')
      continue;
    n = 0;
    sum = 0;
    while (1) {
      c = GdbGet() & 255;
      if (c == '#')
        break;
      if (n + 1 >= GDB_PKT_MAX) {
        GdbPut('-');
        n = -1;
        break;
      }
      g_gdb_pkt[n++] = c;
      sum = (sum + c) & 0xFF;
    }
    if (n < 0)
      continue;
    g_gdb_pkt[n] = 0;
    d0 = GdbHexN(GdbGet() & 255);
    d1 = GdbHexN(GdbGet() & 255);
    if (d0 < 0 || d1 < 0) {
      GdbPut('-');
      continue;
    }
    cs = (d0 << 4) | d1;
    if (cs != sum) {
      GdbPut('-');
      continue;
    }
    GdbPut('+');
    return n;
  }
  return -1;
}

I64 GdbInRam(I64 a)
{
  return a >= 0x80000000 && a < 0x88000000;
}
// Inline snap (same pattern as csr.hc RegsSnapOnly — no Hc* call; hung on repl-holyc).
U0 GdbSnapRegs()
{
  I64 epc;
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
  // x0
  // Trap mepc word index 19 (DBG_I_EPC) — numeric so post-seal Run needs no debug.hc defines.
  epc = *(I64 *)(MEM_TRAP_SNAP + 19 * 8);
  if (GdbInRam(epc))
    g_gdb_pc = epc;
  else
    g_gdb_pc = *(I64 *)(MEM_REGS_SNAP + 1 * 8);
  // ra
}

U0 GdbReplyG()
{
  I64 i, j, v, b, cs;
  cs = 0;
  GdbPut('$');
  for (i = 0; i < 32; i++) {
    v = *(I64 *)(MEM_REGS_SNAP + i * 8);
    for (j = 0; j < 8; j++) {
      b = (v >> (j * 8)) & 0xFF;
      cs = GdbEmitHexByteCs(b, cs);
    }
  }
  v = g_gdb_pc;
  for (j = 0; j < 8; j++) {
    b = (v >> (j * 8)) & 0xFF;
    cs = GdbEmitHexByteCs(b, cs);
  }
  GdbPut('#');
  GdbPutHexByte(cs);
}
// G packet: write x0..x31 + pc into MEM_REGS_SNAP / g_gdb_pc (no live restore —
// cooperative stub; next g re-snaps). Same LE hex as g.
I64 GdbHandleWriteG(U8 *p)
{
  I64 i, j, v, hi, lo, b;
  if (!p)
    return 0;
  for (i = 0; i < 33; i++) {
    v = 0;
    for (j = 0; j < 8; j++) {
      hi = GdbHexN (*p++);
      lo = GdbHexN (*p++);
      if (hi < 0 || lo < 0)
        return 0;
      b = (hi << 4) | lo;
      v = v | (b << (j * 8));
    }
    if (i < 32)
      *(I64 *)(MEM_REGS_SNAP + i * 8) = v;
    else
      g_gdb_pc = v;
  }
  *(I64 *)MEM_REGS_SNAP = 0;
  GdbSendPacket("OK");
  return 1;
}

U0 GdbReplyM(I64 addr, I64 len)
{
  I64 i, b, cs;
  if (len < 0)
    len = 0;
  if (len > GDB_MEM_MAX)
    len = GDB_MEM_MAX;
  if (!GdbInRam(addr) || (len && !GdbInRam(addr + len - 1))) {
    GdbSendPacket("E01");
    return;
  }
  cs = 0;
  GdbPut('$');
  for (i = 0; i < len; i++) {
    b = *(U8 *)(addr + i) & 255;
    cs = GdbEmitHexByteCs(b, cs);
  }
  GdbPut('#');
  GdbPutHexByte(cs);
}

U0 GdbReplyP(I64 regn)
{
  I64 v, j, b, cs;
  if (regn == 32)
    v = g_gdb_pc;
  else if (regn == 0)
    v = 0;
  else
    v = *(I64 *)(MEM_REGS_SNAP + regn * 8);
  cs = 0;
  GdbPut('$');
  for (j = 0; j < 8; j++) {
    b = (v >> (j * 8)) & 0xFF;
    cs = GdbEmitHexByteCs(b, cs);
  }
  GdbPut('#');
  GdbPutHexByte(cs);
}

I64 GdbHandleWriteM(U8 *p)
{
  I64 addr, len, n, i, hi, lo, b;
  U8 *q;
  n = GdbParseHex(p, &addr);
  if (n <= 0)
    return 0;
  p += n;
  if (*p != ',')
    return 0;
  p++;
  n = GdbParseHex(p, &len);
  if (n <= 0)
    return 0;
  p += n;
  if (*p != ':')
    return 0;
  p++;
  if (len < 0 || len > GDB_MEM_MAX)
    return 0;
  if (!GdbInRam(addr) || (len && !GdbInRam(addr + len - 1))) {
    GdbSendPacket("E01");
    return 1;
  }
  q = p;
  for (i = 0; i < len; i++) {
    hi = GdbHexN (*q++);
    lo = GdbHexN (*q++);
    if (hi < 0 || lo < 0) {
      GdbSendPacket("E01");
      return 1;
    }
    b = (hi << 4) | lo;
    *(U8 *)(addr + i) = b;
  }
  GdbSendPacket("OK");
  return 1;
}
// Silent soft-Bp install (same slots as Bp) — no UartStr (would corrupt RSP).
I64 GdbBpSet(I64 addr)
{
  I64 i, slot;
  if (!GdbInRam(addr))
    return 0;
  if ((*(U32 *)addr & 3) != 3)
    return 0;
  for (i = 0; i < 16; i++)
    if (DbgActive[i] && DbgAddr[i] == addr)
      return 1;
  slot = -1;
  for (i = 0; i < 16; i++)
    if (!DbgActive[i]) {
      slot = i;
      break;
    }
  if (slot < 0)
    return 0;
  DbgAddr[slot] = addr;
  DbgSaved[slot] = *(U32 *)addr;
  *(U32 *)addr = 0x00100073;
  FenceI();
  DbgActive[slot] = 1;
  SetTrap("DbgTrap");
  return 1;
}

I64 GdbBpClr(I64 addr)
{
  I64 i;
  for (i = 0; i < 16; i++)
    if (DbgActive[i] && DbgAddr[i] == addr) {
      *(U32 *)DbgAddr[i] = DbgSaved[i];
      FenceI();
      DbgActive[i] = 0;
      if (DbgStepAddr == addr)
        DbgStepAddr = 0;
      return 1;
    }
  return 1;
}

I64 GdbBpAny()
{
  I64 i;
  for (i = 0; i < 16; i++)
    if (DbgActive[i])
      return 1;
  return 0;
}
// Z0,addr[,kind] / z0,addr[,kind] — software breakpoint (type 0 only).
// Single-arg: pkt[0] is Z (set) or z (clear) — avoids 2-arg ptr/int mixups.
U0 GdbHandleZ(U8 *pkt)
{
  I64 addr, n, set, kind;
  U8 *p;
  if (!pkt) {
    GdbSendPacket("");
    return;
  }
  set = 0;
  if (*pkt == 'Z')
    set = 1;
  else if (*pkt != 'z') {
    GdbSendPacket("");
    return;
  }
  p = pkt + 1;
  if (*p != '0') {
    GdbSendPacket("");
    return;
  }
  p++;
  if (*p != ',') {
    GdbSendPacket("E01");
    return;
  }
  p++;
  n = GdbParseHex(p, &addr);
  if (n <= 0) {
    GdbSendPacket("E01");
    return;
  }
  p += n;
  if (*p == ',') {
    p++;
    kind = 0;
    GdbParseHex(p, &kind);
  }
  if (set) {
    if (GdbBpSet(addr))
      GdbSendPacket("OK");
    else
      GdbSendPacket("E01");
  } else {
    GdbBpClr(addr);
    GdbSendPacket("OK");
  }
}
// Soft-step: arm one-shot ebreak at next insn after g_gdb_pc (Step semantics).
// Guest does not run while stub is attached — S05 = remain stopped / armed.
U0 GdbSoftStep()
{
  I64 addr, next, w;
  addr = g_gdb_pc;
  if (!addr || !GdbInRam(addr)) {
    GdbSendPacket("E01");
    return;
  }
  w = *(U16 *)addr;
  if ((w & 3) == 3)
    next = addr + 4;
  else
    next = addr + 2;
  if (!GdbInRam(next) || ((*(U32 *)next & 3) != 3)) {
    GdbSendPacket("E01");
    return;
  }
  DbgStepAddr = next;
  if (!GdbBpSet(next)) {
    DbgStepAddr = 0;
    GdbSendPacket("E01");
    return;
  }
  GdbSendPacket("S05");
}

I64 GdbHandle()
{
  U8 *p;
  I64 addr, len, n, regn;
  p = g_gdb_pkt;
  if (!*p)
    return 0;
  if (*p == '?') {
    GdbSendPacket("S05");
    return 0;
  }
  if (*p == 'g') {
    GdbReplyG();
    return 0;
  }
  if (*p == 'G') {
    if (!GdbHandleWriteG(p + 1))
      GdbSendPacket("E01");
    return 0;
  }
  if (*p == 'm') {
    n = GdbParseHex(p + 1, &addr);
    if (n <= 0) {
      GdbSendPacket("E01");
      return 0;
    }
    p = p + 1 + n;
    if (*p != ',') {
      GdbSendPacket("E01");
      return 0;
    }
    GdbParseHex(p + 1, &len);
    GdbReplyM(addr, len);
    return 0;
  }
  if (*p == 'M') {
    if (!GdbHandleWriteM(p + 1))
      GdbSendPacket("E01");
    return 0;
  }
  if (*p == 'p') {
    n = GdbParseHex(p + 1, &regn);
    if (n <= 0 || regn < 0 || regn > 32) {
      GdbSendPacket("E01");
      return 0;
    }
    GdbReplyP(regn);
    return 0;
  }
  if (*p == 'Z' || *p == 'z') {
    GdbHandleZ(p);
    return 0;
  }
  if (*p == 's' || *p == 'S') {
    GdbSoftStep();
    return 0;
  }
  if (*p == 'c' || *p == 'C') {
    // Honest: cooperative stub cannot resume guest while attached.
    GdbSendPacket("S05");
    return 0;
  }
  if (*p == 'D' || *p == 'k') {
    if (*p == 'D')
      GdbSendPacket("OK");
    return 1;
  }
  if (*p == 'H') {
    GdbSendPacket("OK");
    return 0;
  }
  if (*p == 'q') {
    if (!StrNCmp(p, "qSupported", 10)) {
      GdbSendPacket("PacketSize=600;swbreak+;hwbreak-");
      return 0;
    }
    if (!StrNCmp(p, "qAttached", 9)) {
      GdbSendPacket("1");
      return 0;
    }
    if (*(p + 1) == 'C' && *(p + 2) == 0) {
      GdbSendPacket("QC01");
      return 0;
    }
    if (!StrNCmp(p, "qfThreadInfo", 12)) {
      GdbSendPacket("m01");
      return 0;
    }
    if (!StrNCmp(p, "qsThreadInfo", 12)) {
      GdbSendPacket("l");
      return 0;
    }
    GdbSendPacket("");
    return 0;
  }
  if (!StrNCmp(p, "vMustReplyEmpty", 15)) {
    GdbSendPacket("");
    return 0;
  }
  GdbSendPacket("");
  return 0;
}
// GdbStub -- GdbStub()
// NAME
//   GdbStub - enter GDB RSP over UART (blocks until detach)
// SYNOPSIS
//   U0 GdbStub();
// DESCRIPTION
//   Post-seal: Run("Boot/gdbstub.hc"); GdbStub;
//   Host: python3 tools/uart_gdb_proxy.py --qemu bootstrap/repl.elf
//   Mux: GdbUseMux(1); Run("Lib/frame.hc"); UartMuxOn; stub TX stays raw.
//   Z0/z0 share soft Bp tables; s arms soft Step; c remains stopped.
// EXAMPLES
//   Run("Boot/gdbstub.hc"); GdbHelp; GdbStub;
// SEE ALSO
//   GdbHelp  GdbUseMux  Bp  Step  Regs  DbgHelp  HwDbg  FrameDbgSend
// BUGS
//   No guest resume while attached (c→S05); soft-step is arm-only; PC is
//   trap mepc or ra; mux ch2 round-trip still host-side WIP.
U0 GdbStub()
{
  I64 done;
  g_gdb_fc_saved = UartFcGet();
  UartXonXoff(0);
  GdbSnapRegs();
  GdbPutStr("$HC_GDB$\n");
  // Unique smoke needle (help text must NOT contain the $ markers).
  UartStr("GDB_STUB_ENTER\n");
  done = 0;
  while (!done) {
    if (GdbRecvPacket() < 0)
      break;
    done = GdbHandle();
  }
  UartStr("GDB_STUB_LEAVE\n");
  GdbPutStr("$HC_GDB_END$\n");
  // After detach: arm trap path if Z0/s left soft Bps (TrapInit prints — OK post-RSP).
  if (GdbBpAny())
    TrapInit();
  if (g_gdb_fc_saved)
    UartXonXoff(1);
}
// GdbHelp -- GdbHelp()
U0 GdbHelp()
{
  UartStr("GdbStub — GDB RSP over UART (regs/mem/Z0; soft-step)\n");
  UartStr("  GdbStub;   // early-boot seed; or Run(\"Boot/gdbstub.hc\");\n");
  UartStr("  enter/leave markers: HC_GDB / HC_GDB_END (raw UART)\n");
  UartStr("  host: python3 tools/uart_gdb_proxy.py --qemu bootstrap/repl.elf\n");
  UartStr("  make gdb-uart-smoke\n");
  UartStr("  g/G: MEM_REGS_SNAP via inline asm (RegsSnapOnly pattern)\n");
  UartStr("  Z0/z0: soft Bp table; s=soft Step arm; c=remain stopped\n");
  UartStr("  GdbUseMux(1); // ch2 intent flag (TX still raw)\n");
  UartStr("GDB_HELP_OK\n");
}
