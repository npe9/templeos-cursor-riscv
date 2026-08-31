// debug.hc -- the HolyC debugger. One-shot breakpoints via ebreak (0x00100073), written entirely
// in HolyC: it patches code with plain pokes, syncs the I-cache with an asm{} fence.i, and reads
// the trapped registers the trampoline publishes at 0x87000100. Break with Bp(&Func); on a hit
// DbgTrap (installed via SetTrap) dumps the args and continues. Edit it: Src("Bp") / Src("DbgTrap").
I64 DbgAddr[16], DbgSaved[16], DbgActive[16];
// fence.i, assembled natively -- sync the instruction cache after patching code.
asm {
	FenceI::
	fencei
	ret
}
// Trapped register n from the published block: 0=ra, 1..7=t0..t6, 8..15=a0..a7, 16=sp.
// DbgReg -- DbgReg(n)
// NAME
//   DbgReg - read trapped register n from 0x87000100.
// SYNOPSIS
//   DbgReg(n)
// DESCRIPTION
//   read trapped register n from 0x87000100.
// INPUTS
//   n - argument
// OUTPUTS
//   read trapped register n from 0x87000100.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 DbgReg(I64 n)
{
  return *(I64 *)(0x87000100 + n * 8);
}
// Trap handler. On a breakpoint (cause 3) at one of ours: restore the original instruction
// (one-shot), dump the arguments, and re-execute. Returns the resume PC, or 0 for default handling.
// DbgTrap -- DbgTrap(cause,epc,tval)
// NAME
//   DbgTrap - breakpoint trap handler: restore insn, dump args, continue.
// SYNOPSIS
//   DbgTrap(cause,epc,tval)
// DESCRIPTION
//   breakpoint trap handler: restore insn, dump args, continue.
// INPUTS
//   cause - argument
//   epc - argument
//   tval - argument
// OUTPUTS
//   breakpoint trap handler: restore insn, dump args, continue.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 DbgTrap(I64 cause, I64 epc, I64 tval)
{
  I64 i;
  if (cause == 3) {
    for (i = 0; i < 16; i++) {
      if (DbgActive[i] && DbgAddr[i] == epc) {
        *(U32 *)DbgAddr[i] = DbgSaved[i];
        // restore original instruction
        FenceI();
        DbgActive[i] = 0;
        // one-shot: it fires once
        "\n*** breakpoint @ 0x%08X  (args at entry)\n", epc;
        "  a0=0x%X  a1=0x%X  a2=0x%X  a3=0x%X\n", DbgReg(8), DbgReg(9), DbgReg(10), DbgReg(11);
        "  a4=0x%X  a5=0x%X  a6=0x%X  a7=0x%X\n", DbgReg(12), DbgReg(13), DbgReg(14), DbgReg(15);
        "  ra=0x%X  sp=0x%X\n", DbgReg(0), DbgReg(16);
        return epc;
        // re-run the restored instruction
      }
    }
  }
  return 0;
}
// Bp -- Bp(&Func)
// NAME
//   Bp - one-shot breakpoint at a function entry (refuses compressed C builtins).
// SYNOPSIS
//   Bp(&Func)
// DESCRIPTION
//   one-shot breakpoint at a function entry (refuses compressed C builtins).
// INPUTS
//   &Func - out-parameter pointer
// OUTPUTS
//   one-shot breakpoint at a function entry (refuses compressed C builtins).
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 Bp(I64 addr)
{
  I64 i, slot;
  if (!addr) {
    "Bp: null address\n";
    return;
  }
  if ((*(U32 *)addr & 3) != 3) {
    "Bp: entry is a compressed instruction (a C built-in) -- can't\n";
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
  DbgSaved[slot] = *(U32 *)addr;
  *(U32 *)addr = 0x00100073;
  // ebreak
  FenceI();
  DbgActive[slot] = 1;
  SetTrap("DbgTrap");
  // route traps to us
  TrapInit();
  // install the vector (mtvec)
  "Bp set @ 0x%08X\n", addr;
}
// Bps -- Bps()
// NAME
//   Bps - list active breakpoints.
// SYNOPSIS
//   Bps()
// DESCRIPTION
//   list active breakpoints.
// INPUTS
//   none
// OUTPUTS
//   list active breakpoints.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 Bps()
{
  I64 i, n = 0;
  for (i = 0; i < 16; i++)
    if (DbgActive[i]) {
      "  bp @ 0x%08X\n", DbgAddr[i];
      n++;
    }
  if (!n)
    "  (no active breakpoints)\n";
}
// BpClr -- BpClr(addr)
// NAME
//   BpClr - clear breakpoint at addr.
// SYNOPSIS
//   BpClr(addr)
// DESCRIPTION
//   clear breakpoint at addr.
// INPUTS
//   addr - argument
// OUTPUTS
//   clear breakpoint at addr.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 BpClr(I64 addr)
{
  I64 i;
  for (i = 0; i < 16; i++)
    if (DbgActive[i] && DbgAddr[i] == addr) {
      *(U32 *)DbgAddr[i] = DbgSaved[i];
      FenceI();
      DbgActive[i] = 0;
      "Bp cleared @ 0x%08X\n", addr;
      return;
    }
  "BpClr: no active breakpoint @ 0x%08X\n", addr;
}
// ---- TempleOS-style inspection: Dr (registers), Dm/D (hex dump), Da (symbolic slot dump) ----
// Dr -- Dr()
// NAME
//   Dr - dump registers (Regs); dig-down with Reg/GetM*
// SYNOPSIS
//   U0 Dr();
// DESCRIPTION
//   Alias of Regs. Then Reg("sp"); Reg("mstatus"); GetMStatus; RegHelp; Man("Regs").
// INPUTS
//   none
// OUTPUTS
//   Full GPR+CSR dump
// BUGS
//   Same as Regs (C snap + HolyC CSR Get/Set in csr.hc).
U0 Dr()
{
  Regs;
}
// Dm -- Dm(a,n)
// NAME
//   Dm - hex+ASCII dump.
// SYNOPSIS
//   Dm(a,n)
// DESCRIPTION
//   hex+ASCII dump.
// INPUTS
//   a - argument
//   n - argument
// OUTPUTS
//   hex+ASCII dump.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 Dm(I64 a, I64 n = 64)
{
  // hex + ASCII, 16 bytes a row
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
// D -- D(a,n)
// NAME
//   D - alias of Dm (also shadows holy_rt D after boot).
// SYNOPSIS
//   D(a,n)
// DESCRIPTION
//   alias of Dm (also shadows holy_rt D after boot).
// INPUTS
//   a - argument
//   n - argument
// OUTPUTS
//   alias of Dm (also shadows holy_rt D after boot).
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 D(I64 a, I64 n = 64)
{
  Dm(a, n);
}
// Da -- Da(a,n)
// NAME
//   Da - symbolic I64 slot dump.
// SYNOPSIS
//   Da(a,n)
// DESCRIPTION
//   symbolic I64 slot dump.
// INPUTS
//   a - argument
//   n - argument
// OUTPUTS
//   symbolic I64 slot dump.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 Da(I64 a, I64 n = 8)
{
  // n I64 slots; each value symbolized if it lands in a function
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
