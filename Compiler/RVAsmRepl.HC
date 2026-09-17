// RVAsmRepl.HC — asm REPL: run one instruction at a time and watch the registers change.
//
// The guest Compiler already compiles and runs a string (ExePutS), asm{} included — that is
// the JIT. The debugger's fault-freeze array doubles as the REPL's REGISTER FILE, so the two
// are the same thing: what `_A0` reads is what the next instruction will run with, and what a
// trap freezes is what you then inspect.
//
// AsmStep("addi a0,a0,1") builds
//     asm { <prologue: ld the context from the array> <your line> <epilogue: sd it back> }
// and hands that to ExePutS. The register context is therefore implemented BY the existing
// JIT — no second execution path, no interpreter.
//
// Context: t0-t5, a0-a7, s1-s11 (21 registers). Excluded and why:
//   x0            hardwired
//   sp gp tp s0   the running REPL stands on them
//   ra            return address of the JIT'd fragment itself
//   t6            the prologue/epilogue's own base-address scratch (same exclusion
//                 host/rv32_lift.c makes, for the same reason)
// Addresses match bootstrap/seed/trap.hc and bootstrap/holy_rt.h.
#define ASM_CTX      0x87000400
// x0..x31 — the fault freeze
#define ASM_CTX_PREV 0x87000600
// shadow: what the registers held before the last step

I64 asm_ctx_ready;

// Context registers, in display order: x-numbers.
I64 AsmCtxReg(I64 i)
{
  if (i < 3)
    return 5 + i;
  // t0 t1 t2
  if (i < 6)
    return 28 + i - 3;
  // t3 t4 t5
  if (i < 14)
    return 10 + i - 6;
  // a0..a7
  if (i == 14)
    return 9;
  // s1
  if (i < 25)
    return 18 + i - 15;
  // s2..s11
  return -1;
}

U0 AsmRegName(I64 n, U8 *out)
{
  if (n == 0)
    StrPrint(out, "zero");
  else if (n == 1)
    StrPrint(out, "ra");
  else if (n == 2)
    StrPrint(out, "sp");
  else if (n == 3)
    StrPrint(out, "gp");
  else if (n == 4)
    StrPrint(out, "tp");
  else if (n >= 5 && n <= 7)
    StrPrint(out, "t%d", n - 5);
  else if (n >= 28 && n <= 31)
    StrPrint(out, "t%d", n - 25);
  else if (n >= 10 && n <= 17)
    StrPrint(out, "a%d", n - 10);
  else if (n == 8)
    StrPrint(out, "s0");
  else if (n == 9)
    StrPrint(out, "s1");
  else if (n >= 18 && n <= 27)
    StrPrint(out, "s%d", n - 16);
  else
    StrPrint(out, "x%d", n);
}

// Append the ld/sd block that moves the whole context between the array and the machine.
U0 AsmCtxIo(U8 *dst, Bool store)
{
  U8 line[64];
  I64 i, n;
  StrCat(dst, "lui t6,0x10E00\nslli t6,t6,3\naddi t6,t6,0x400\n");
  i = 0;
  while (TRUE) {
    n = AsmCtxReg(i);
    if (n < 0)
      break;
    if (store)
      StrPrint(line, "sd x%d,%d(t6)\n", n, n * 8);
    else
      StrPrint(line, "ld x%d,%d(t6)\n", n, n * 8);
    StrCat(dst, line);
    i++;
  }
}

U0 AsmCtxSnapPrev()
{
  I64 i, n;
  i = 0;
  while (TRUE) {
    n = AsmCtxReg(i);
    if (n < 0)
      break;
    *(I64 *)(ASM_CTX_PREV + n * 8) = *(I64 *)(ASM_CTX + n * 8);
    i++;
  }
}

// AsmRegs -- AsmRegs()
// NAME
//   AsmRegs - print the asm REPL's register context
// SYNOPSIS
//   AsmRegs;
// SEE ALSO
//   AsmStep  AsmClr  Dr
public U0 AsmRegs()
{
  U8 nm[8];
  I64 i, n, col = 0;
  i = 0;
  while (TRUE) {
    n = AsmCtxReg(i);
    if (n < 0)
      break;
    AsmRegName(n, nm);
    "%-4s=%016X  ", nm, *(I64 *)(ASM_CTX + n * 8);
    col++;
    if (col % 3 == 0)
      "\n";
    i++;
  }
  if (col % 3)
    "\n";
}

// AsmClr -- AsmClr()
// NAME
//   AsmClr - zero the asm REPL's register context
// SYNOPSIS
//   AsmClr;
// SEE ALSO
//   AsmStep  AsmRegs
public U0 AsmClr()
{
  I64 i, n;
  i = 0;
  while (TRUE) {
    n = AsmCtxReg(i);
    if (n < 0)
      break;
    *(I64 *)(ASM_CTX + n * 8) = 0;
    *(I64 *)(ASM_CTX_PREV + n * 8) = 0;
    i++;
  }
  asm_ctx_ready = 1;
}

// AsmStep -- AsmStep("addi a0,a0,1")
// NAME
//   AsmStep - assemble and run one line with the register context, then show what changed
// SYNOPSIS
//   AsmStep(U8 *text);
// DESCRIPTION
//   Wraps `text` in a load/store of the context array and ExePutS's it, so the line runs with
//   the registers the previous line left behind. Prints only the registers whose value moved
//   (and nothing if the line was pure control flow), so a session reads as a trace.
//   `_A0 = 5;` between steps works: the labels alias the same array.
// EXAMPLES
//   AsmClr;  AsmStep("addi a0,a0,7");  AsmStep("add a1,a0,a0");  AsmRegs;
// SEE ALSO
//   AsmRegs  AsmClr  Dr  U  Disasm
// BUGS
//   t6 is the wrapper's scratch and is not part of the context; sp/gp/tp/s0/ra belong to the
//   running REPL and are left alone.
public I64 AsmStep(U8 *text)
{
  U8 *src, nm[8];
  I64 i, n, now, was, changed = 0;
  if (!text)
    return 0;
  if (!asm_ctx_ready)
    AsmClr;
  AsmCtxSnapPrev;
  src = MAlloc(4096);
  StrCpy(src, "asm{\n");
  AsmCtxIo(src, FALSE);
  StrCat(src, text);
  StrCat(src, "\n");
  AsmCtxIo(src, TRUE);
  StrCat(src, "}\n");
  ExePutS(src);
  Free(src);
  i = 0;
  while (TRUE) {
    n = AsmCtxReg(i);
    if (n < 0)
      break;
    now = *(I64 *)(ASM_CTX + n * 8);
    was = *(I64 *)(ASM_CTX_PREV + n * 8);
    if (now != was) {
      AsmRegName(n, nm);
      "  %-4s %016X -> %016X\n", nm, was, now;
      changed++;
    }
    i++;
  }
  if (!changed)
    "  (no register changed)\n";
  return changed;
}
