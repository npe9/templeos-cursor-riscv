// csr_decode.hc — what a CSR VALUE means, for both images.
//
// These were written twice: once here in the seed image and once, smaller, in
// Kernel/RVExplore.HC. Two forks of the same bit tests drift — the kernel's mstatus never
// learned UIE/UPIE/UXL/SXL/SD, and satp was decoded in neither. So they live in one file now,
// concatenated into the seed blob (bootstrap/gen_boot_blob.py BOOT_ORDER) and #included by the
// kernel image, which is the only arrangement that keeps them the same thing.
//
// Everything here is PURE: a value in, text out, no CSR read. That is what makes it shareable —
// the two images read CSRs by different means (GetMStatus here, RVWinCsrrMstatus there) and a
// decoder that read its own input could not be shared. It is also what makes it right for a
// debugger: after a fault you want the value you STOPPED at decoded, not whatever the CSR says
// now. See docs/MACHINE_STATE_SURVEY.md.
#ifndef CSR_DECODE_HC
#define CSR_DECODE_HC

// ---- CSR bitfield decode (explicit bit tests; no table walks — repl-holyc AOT) ----
U0 CsrDecodeMstatus(I64 v)
{
  I64 mpp, fs, xs, vs, uxl, sxl;
  if (v & 1)
    Print("   UIE=1 (user interrupts enabled)\n");
  if (v & 2)
    Print("   SIE=1 (supervisor interrupts enabled)\n");
  if (v & 8)
    Print("   MIE=1 (machine interrupts enabled)\n");
  else
    Print("   MIE=0 (machine interrupts disabled)\n");
  if (v & 16)
    Print("   UPIE=1 (user prior IE)\n");
  if (v & 32)
    Print("   SPIE=1 (supervisor prior IE)\n");
  if (v & 128)
    Print("   MPIE=1 (machine prior IE)\n");
  if (v & 256)
    Print("   SPP=1 (prior privilege S-mode)\n");
  vs = (v >> 9) & 3;
  if (vs)
    Print("   VS=%d (%s)\n", vs, vs == 1 ? "Initial" : vs == 2 ? "Clean" : vs == 3 ? "Dirty" : "?");
  mpp = (v >> 11) & 3;
  if (mpp == 1)
    Print("   MPP=01 (S-mode)\n");
  else if (mpp == 3)
    Print("   MPP=11 (M-mode)\n");
  else if (mpp == 2)
    Print("   MPP=10 (reserved)\n");
  else
    Print("   MPP=00 (U-mode)\n");
  fs = (v >> 13) & 3;
  if (fs)
    Print("   FS=%d (%s)\n", fs, fs == 1 ? "Initial" : fs == 2 ? "Clean" : fs == 3 ? "Dirty" : "?");
  xs = (v >> 15) & 3;
  if (xs)
    Print("   XS=%d (%s)\n", xs, xs == 1 ? "Initial" : xs == 2 ? "Clean" : xs == 3 ? "Dirty" : "?");
  if (v & 0x20000)
    Print("   MPRV=1 (loads/stores at MPP privilege)\n");
  if (v & 0x40000)
    Print("   SUM=1 (supervisor may access user pages)\n");
  if (v & 0x80000)
    Print("   MXR=1 (executable pages readable)\n");
  if (v & 0x100000)
    Print("   TVM=1 (trap satp/tlb ops from S-mode)\n");
  if (v & 0x200000)
    Print("   TW=1 (trap WFI from S-mode)\n");
  if (v & 0x400000)
    Print("   TSR=1 (trap sret from S-mode)\n");
  uxl = (v >> 32) & 3;
  if (uxl == 1)
    Print("   UXL=01 (32-bit U-mode)\n");
  else if (uxl == 2)
    Print("   UXL=10 (64-bit U-mode)\n");
  sxl = (v >> 34) & 3;
  if (sxl == 1)
    Print("   SXL=01 (32-bit S-mode)\n");
  else if (sxl == 2)
    Print("   SXL=10 (64-bit S-mode)\n");
  if (v & 0x8000000000000000)
    Print("   SD=1 (some state dirty)\n");
}

U0 CsrDecodeMisa(I64 v)
{
  I64 mxl, any;
  mxl = (v >> 62) & 3;
  if (mxl == 1)
    Print("   MXL=01 (RV32)\n");
  else if (mxl == 2)
    Print("   MXL=10 (RV64)\n");
  else if (mxl)
    Print("   MXL=%d (?)\n", mxl);
  any = 0;
  if (v & 1) {
    Print("   A");
    any = 1;
  }
  if (v & 4) {
    if (any)
      Print(" C");
    else
      Print("   C");
    any = 1;
  }
  if (v & 8) {
    if (any)
      Print(" D");
    else
      Print("   D");
    any = 1;
  }
  if (v & 32) {
    if (any)
      Print(" F");
    else
      Print("   F");
    any = 1;
  }
  if (v & 256) {
    if (any)
      Print(" I");
    else
      Print("   I");
    any = 1;
  }
  if (v & 4096) {
    if (any)
      Print(" M");
    else
      Print("   M");
    any = 1;
  }
  if (v & 262144) {
    if (any)
      Print(" S");
    else
      Print("   S");
    any = 1;
  }
  if (v & 1048576) {
    if (any)
      Print(" U");
    else
      Print("   U");
    any = 1;
  }
  if (any)
    Print(" (ISA extensions set)\n");
}

U0 CsrDecodeIrqBits(I64 v, U8 *kind)
{
  if (v & 2)
    Print("   SSIE=1 (supervisor soft %s)\n", kind);
  if (v & 8)
    Print("   MSIE=1 (machine soft %s)\n", kind);
  if (v & 32)
    Print("   STIE=1 (supervisor timer %s)\n", kind);
  if (v & 128)
    Print("   MTIE=1 (machine timer %s)\n", kind);
  if (v & 512)
    Print("   SEIE=1 (supervisor external %s)\n", kind);
  if (v & 2048)
    Print("   MEIE=1 (machine external %s)\n", kind);
}

U0 CsrDecodeMie(I64 v)
{
  CsrDecodeIrqBits(v, "enable");
}

U0 CsrDecodeMip(I64 v)
{
  if (v & 2)
    Print("   SSIP=1 (supervisor soft pending)\n");
  if (v & 8)
    Print("   MSIP=1 (machine soft pending)\n");
  if (v & 32)
    Print("   STIP=1 (supervisor timer pending)\n");
  if (v & 128)
    Print("   MTIP=1 (machine timer pending)\n");
  if (v & 512)
    Print("   SEIP=1 (supervisor external pending)\n");
  if (v & 2048)
    Print("   MEIP=1 (machine external pending)\n");
}

U0 CsrDecodeMtvec(I64 v)
{
  I64 mode;
  mode = v & 3;
  if (mode == 0)
    Print("   MODE=0 (Direct)\n");
  else if (mode == 1)
    Print("   MODE=1 (Vectored)\n");
  else
    Print("   MODE=%d (?)\n", mode);
  Print("   BASE=%p (trap entry)\n", v & ~3);
}

U0 CsrDecodeMepc(I64 v)
{
  Print("   PC=%p", v);
  if (v & 1)
    Print(" (bit0 set — compressed or misaligned)");
  Print("\n");
  Print("   mret target\n");
}
// McauseCauseName -- symbolic interrupt/exception name for mcause (CSR 0x342).
U8 *McauseCauseName(I64 v)
{
  I64 intr, code;
  intr = (v >> 63) & 1;
  code = v & 0x7FFFFFFFFFFFFFFF;
  if (intr) {
    if (code == 0)
      return "user soft interrupt";
    if (code == 1)
      return "supervisor soft interrupt";
    if (code == 3)
      return "machine soft interrupt";
    if (code == 4)
      return "user timer interrupt";
    if (code == 5)
      return "supervisor timer interrupt";
    if (code == 7)
      return "machine timer interrupt";
    if (code == 8)
      return "user external interrupt";
    if (code == 9)
      return "supervisor external interrupt";
    if (code == 11)
      return "machine external interrupt";
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
// McausePrint -- compact crash-line decode: mcause=0xN  Exception/Interrupt code=N (name)
U0 McausePrint(I64 v)
{
  I64 intr, code;
  U8 *name;
  intr = (v >> 63) & 1;
  code = v & 0x7FFFFFFFFFFFFFFF;
  name = McauseCauseName(v);
  if (intr)
    "  mcause=0x%X  Interrupt code=%d (%s)\n", v, code, name;
  else
    "  mcause=0x%X  Exception code=%d (%s)\n", v, code, name;
}

U0 CsrDecodeMcause(I64 v)
{
  I64 intr, code;
  U8 *name;
  intr = (v >> 63) & 1;
  code = v & 0x7FFFFFFFFFFFFFFF;
  name = McauseCauseName(v);
  if (intr)
    Print("   Interrupt=1 (%s)\n", name);
  else
    Print("   Exception (Interrupt=0)\n   code=%d (%s)\n", code, name);
  if (intr) {
    Print("   code=%d (", code);
    if (code == 11)
      Print("MEI");
    else if (code == 7)
      Print("MTI");
    else if (code == 3)
      Print("MSI");
    else if (code == 9)
      Print("SEI");
    else if (code == 5)
      Print("STI");
    else if (code == 1)
      Print("SSI");
    else
      Print("?");
    Print(")\n");
  }
}

U0 CsrDecodeMtval(I64 v, I64 mcause_hint)
{
  I64 intr, code;
  if (!v) {
    Print("   (zero)\n");
    return;
  }
  code = mcause_hint;
  if (code < 0) {
    code = GetMcause();
  }
  intr = (code >> 63) & 1;
  code = code & 0x7FFFFFFFFFFFFFFF;
  if (!intr && (code == 0 || code == 2))
    Print("   faulting instruction bits (misaligned/illegal insn)\n");
  else if (!intr && code >= 4 && code <= 7)
    Print("   bad address for load/store\n");
  else if (!intr && code >= 12 && code <= 15)
    Print("   faulting virtual address\n");
  Print("   value=%p\n", v);
}

U0 CsrDecodeMscratch(I64 v)
{
  if (v)
    Print("   scratch=%p (trap/OS private)\n", v);
  else
    Print("   (zero — unused)\n");
}

U0 CsrDecodeMhartid(I64 v)
{
  Print("   hart %d (read-only)\n", v);
}

U0 CsrDecodeMtime(I64 v)
{
  Print("   CLINT MMIO @ MEM_MTIME (not CSR; CSR_TIME=0xC01 is read-only shadow)\n");
  Print("   ticks=%d\n", v);
}

// ---- decoders the forks never had -----------------------------------------------------------

// satp: the whole of the MMU's configuration in one register. Decoded until now only by the
// seed's datasheet sheet (datasheet/ds_csr.hc), which the kernel image does not link.
U0 CsrDecodeSatp(I64 v)
{
  I64 mode;
  mode = (v >> 60) & 15;
  if (!mode)
    Print("   MODE=0 (Bare - no translation, physical addresses)\n");
  else if (mode == 8)
    Print("   MODE=8 (Sv39 - 3-level, 39-bit virtual)\n");
  else if (mode == 9)
    Print("   MODE=9 (Sv48 - 4-level, 48-bit virtual)\n");
  else if (mode == 10)
    Print("   MODE=10 (Sv57)\n");
  else
    Print("   MODE=%d (reserved)\n", mode);
  Print("   ASID=0x%X\n", (v >> 44) & 0xFFFF);
  Print("   PPN=0x%X (root page table @ 0x%X)\n", v & 0xFFFFFFFFFFF,
        (v & 0xFFFFFFFFFFF) << 12);
}

// fcsr: the only float state with no reader anywhere in the tree until now. fflags are sticky —
// they accumulate until something clears them, so a flag here is "this happened at some point",
// not "this happened last instruction".
U8 *CsrRmName(I64 rm)
{
  if (!rm)
    return "RNE (nearest, ties to even)";
  if (rm == 1)
    return "RTZ (toward zero)";
  if (rm == 2)
    return "RDN (down, toward -inf)";
  if (rm == 3)
    return "RUP (up, toward +inf)";
  if (rm == 4)
    return "RMM (nearest, ties away)";
  if (rm == 7)
    return "DYN (from the instruction)";
  return "reserved";
}

U0 CsrDecodeFcsr(I64 v)
{
  Print("   frm=%d %s\n", (v >> 5) & 7, CsrRmName((v >> 5) & 7));
  Print("   fflags=0x%X (sticky)\n", v & 31);
  if (v & 1)
    Print("     NX inexact\n");
  if (v & 2)
    Print("     UF underflow\n");
  if (v & 4)
    Print("     OF overflow\n");
  if (v & 8)
    Print("     DZ divide by zero\n");
  if (v & 16)
    Print("     NV invalid operation\n");
  if (!(v & 31))
    Print("     (no exception raised since the flags were last cleared)\n");
}

// mcounteren / scounteren: which counters the next privilege level may read.
U0 CsrDecodeCounteren(I64 v)
{
  if (v & 1)
    Print("   CY=1 (cycle readable)\n");
  if (v & 2)
    Print("   TM=1 (time readable)\n");
  if (v & 4)
    Print("   IR=1 (instret readable)\n");
  if (!(v & 7))
    Print("   none of cycle/time/instret readable below M\n");
}

// medeleg / mideleg: which traps are handled in S-mode instead of M-mode. A bit per cause, so
// the cause names are the decode.
U0 CsrDecodeDeleg(I64 v, I64 interrupts)
{
  I64 i = 0;
  if (!v) {
    Print("   nothing delegated (all traps taken in M-mode)\n");
    return;
  }
  while (i < 64) {
    if (v & (1 << i))
      Print("   bit %d: %s\n", i, McauseCauseName(i + (interrupts << 63)));
    i++;
  }
}

// The privilege a trap came FROM, which mstatus.MPP holds and nothing in the tree materialises.
U8 *CsrPrivName(I64 mpp)
{
  if (!mpp)
    return "U (user)";
  if (mpp == 1)
    return "S (supervisor)";
  if (mpp == 3)
    return "M (machine)";
  return "?";
}

#endif
