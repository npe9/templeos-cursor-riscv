// debug.hc -- the HolyC debugger. One-shot breakpoints via ebreak (0x00100073), written entirely
// in HolyC: it patches code with plain pokes, syncs the I-cache with an asm{} fence.i, and reads
// the trapped registers the trampoline publishes at 0x87000100. Break with Bp(&Func); on a hit
// DbgTrap (installed as the trap ISR) dumps the args and continues. Edit it: Src("Bp") / Src("DbgTrap").
I64 DbgAddr[16], DbgSaved[16], DbgActive[16];

// fence.i, assembled natively -- sync the instruction cache after patching code.
asm {
FenceI::
	fencei
	ret
}
// Trapped register n from the published block: 0=ra, 1..7=t0..t6, 8..15=a0..a7, 16=sp.
I64 DbgReg(I64 n) { return *(I64 *)(0x87000100 + n * 8); }

// The trap ISR. On a breakpoint (cause 3) at one of ours: restore the original instruction
// (one-shot), dump the arguments, and re-execute. Returns the resume PC, or 0 for default handling.
I64 DbgTrap(I64 cause, I64 epc, I64 tval) {
  I64 i;
  if (cause == 3) {
    for (i = 0; i < 16; i++) {
      if (DbgActive[i] && DbgAddr[i] == epc) {
        *(U32 *)DbgAddr[i] = DbgSaved[i];    // restore original instruction
        FenceI();
        DbgActive[i] = 0;                    // one-shot: it fires once
        "\n*** breakpoint @ 0x%08X  (args at entry)\n", epc;
        "  a0=0x%X  a1=0x%X  a2=0x%X  a3=0x%X\n", DbgReg(8),  DbgReg(9),  DbgReg(10), DbgReg(11);
        "  a4=0x%X  a5=0x%X  a6=0x%X  a7=0x%X\n", DbgReg(12), DbgReg(13), DbgReg(14), DbgReg(15);
        "  ra=0x%X  sp=0x%X\n", DbgReg(0), DbgReg(16);
        return epc;                          // re-run the restored instruction
      }
    }
  }
  return 0;
}
// Bp(&Func) -- break at a function entry. Refuses a compressed entry (a C built-in).
U0 Bp(I64 addr) {
  I64 i, slot;
  if (!addr) { "Bp: null address\n"; return; }
  if ((*(U32 *)addr & 3) != 3) { "Bp: entry is a compressed instruction (a C built-in) -- can't\n"; return; }
  slot = -1;
  for (i = 0; i < 16; i++) if (!DbgActive[i]) { slot = i; break; }
  if (slot < 0) { "Bp: table full\n"; return; }
  DbgAddr[slot] = addr;
  DbgSaved[slot] = *(U32 *)addr;
  *(U32 *)addr = 0x00100073;                 // ebreak
  FenceI();
  DbgActive[slot] = 1;
  SetIsr("DbgTrap");                          // route traps to us
  TrapInit();                                 // install the vector
  "Bp set @ 0x%08X\n", addr;
}
U0 Bps() {
  I64 i, n = 0;
  for (i = 0; i < 16; i++) if (DbgActive[i]) { "  bp @ 0x%08X\n", DbgAddr[i]; n++; }
  if (!n) "  (no active breakpoints)\n";
}
U0 BpClr(I64 addr) {
  I64 i;
  for (i = 0; i < 16; i++) if (DbgActive[i] && DbgAddr[i] == addr) {
    *(U32 *)DbgAddr[i] = DbgSaved[i]; FenceI(); DbgActive[i] = 0;
    "Bp cleared @ 0x%08X\n", addr; return;
  }
  "BpClr: no active breakpoint @ 0x%08X\n", addr;
}

// ---- TempleOS-style inspection: Dr (registers), Dm/D (hex dump), Da (symbolic slot dump) ----
U0 Dr() { Regs; }
U0 Dm(I64 a, I64 n=64) {   // hex + ASCII, 16 bytes a row
  I64 r, c, b;
  for (r = 0; r < n; r += 16) {
    "%08X: ", a + r;
    for (c = 0; c < 16; c++) { if (r + c < n) { "%02X ", *(U8 *)(a + r + c); } else { "   "; } }
    " ";
    for (c = 0; c < 16 && r + c < n; c++) { b = *(U8 *)(a + r + c); if (b >= 32 && b < 127) PutCh(b); else PutCh('.'); }
    "\n";
  }
}
U0 D(I64 a, I64 n=64) { Dm(a, n); }
U0 Da(I64 a, I64 n=8) {    // n I64 slots; each value symbolized if it lands in a function
  I64 i, v, base; U8 *nm;
  for (i = 0; i < n; i++) {
    v = *(I64 *)(a + i * 8);
    "%08X: %016X", a + i * 8, v;
    nm = SymName(v);
    if (nm) { base = SymBase(v); "  %s+0x%X", nm, v - base; }
    "\n";
  }
}
