// RVDbgCore.HC — the stock TempleOS debugger surface, as ordinary HolyC functions.
//
// tos/Doc/DbgOverview.DD: TempleOS has no separate debugger UI. You call Dr() to dump regs,
// U()/Uf() to unassemble, D()/Dm() to dump memory, and read/assign registers as var-like
// labels (_RAX, _RIP). Everything below is that surface for RISC-V; the labels are planted by
// RVExePubsWireDbgRegs and the values live in the fault freeze (which is also the asm REPL's
// register file — see RVAsmRepl.HC), so Dr shows the same state whether you got there by
// faulting or by stepping.
#define DBG_SNAP   0x87000100
// legacy slots: 18 mcause, 19 mepc, 20 mtval, 21 mstatus
#define DBG_SNAP_X 0x87000400
// canonical x0..x31

// Dr -- Dr()
// NAME
//   Dr - dump the frozen registers (stock TempleOS name)
// SYNOPSIS
//   Dr;
// DESCRIPTION
//   All 32 GPRs from the fault freeze with their ABI names, then the trap CSRs. After a fault
//   this is the trapped context; after AsmStep it is the asm REPL's register file — the same
//   array either way. The _Xn / _A0 labels alias these exact slots, so `_A0 = 5;` then `Dr;`
//   shows the change, and it is live on resume.
// EXAMPLES
//   Dr;  U(_PC - 16);  _A0 = 5;
// SEE ALSO
//   AsmStep  AsmRegs  U  Uf  Bp
public U0 Dr()
{
  U8 nm[8];
  I64 n, col = 0;
  n = 0;
  while (n < 32) {
    AsmRegName(n, nm);
    "%-4s=%016X  ", nm, *(I64 *)(DBG_SNAP_X + n * 8);
    col++;
    if (col % 4 == 0)
      "\n";
    n++;
  }
  if (col % 4)
    "\n";
  "mcause=%016X  mepc=%016X\n", *(I64 *)(DBG_SNAP + 18 * 8), *(I64 *)(DBG_SNAP + 19 * 8);
  "mtval =%016X  mstatus=%016X\n", *(I64 *)(DBG_SNAP + 20 * 8), *(I64 *)(DBG_SNAP + 21 * 8);
}
