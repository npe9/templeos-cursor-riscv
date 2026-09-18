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
#define ASM_FCTX 0x87000800
// f0..f31, the float half of the stepper's register file
#define ASM_FCTX_PREV 0x87000900
#define ASM_FCTX_OFF 0x400
// ASM_FCTX - ASM_CTX: 1024, which fits a 12-bit offset, so the float block is reached from the
// same base register as the integer one and costs no extra setup
#define ASM_FREGS 32
// shadow: what the registers held before the last step

I64 asm_ctx_ready;
I64 asm_watch_fn;
// optional pane painter (Kernel/RVRegPane.HC), installed at runtime

// AsmWatchInstall -- AsmWatchInstall(&RegPaneUpdate)
// NAME
//   AsmWatchInstall - have AsmStep repaint a live register pane after each line
// DESCRIPTION
//   Takes a U0(*)() and calls it after every step. Kept as a pointer so the asm REPL (compiler
//   image) does not have to link the pane (kernel image) — whoever builds an image with both
//   installs it. Pass 0 to stop.
// SEE ALSO
//   AsmStep  RegPaneUpdate
public U0 AsmWatchInstall(I64 fn)
{
  asm_watch_fn = fn;
}

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
  if (i == 25)
    return 31;
  // t6 — the wrapper's own base register, which is why it needs the care below
  return -1;
}

#define ASM_CTX_BASE_REG 31
// t6: the wrapper needs SOME register to address the context array with, and whichever one it
// picks it cannot also carry that register's value across the step. The answer is to handle it
// last on the way in and first on the way out:
//   in   load everything else with t6 as the base, then load t6 itself from it — the base is
//        consumed at the moment it is no longer needed
//   out  park t6 on the stack (a store needs no base register beyond sp, which is not part of
//        the context), rebuild the base in t6, store everything else, then bring the parked
//        value back through t5 — already stored by then, so it is free to borrow
// Without this, `li t6,3` ran and then vanished: the wrapper overwrote t6 before it was saved.
U0 AsmCtxBase(U8 *dst)
{
  StrCat(dst, "lui t6,0x10E00\nslli t6,t6,3\naddi t6,t6,0x400\n");
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
  if (store) {
    StrPrint(line, "addi sp,sp,-16\nsd x%d,8(sp)\n", ASM_CTX_BASE_REG);
    StrCat(dst, line);
  }
  AsmCtxBase(dst);
  i = 0;
  while (TRUE) {
    n = AsmCtxReg(i);
    if (n < 0)
      break;
    if (n == ASM_CTX_BASE_REG) {
      i++;
      continue;
      // handled either side of this loop
    }
    if (store)
      StrPrint(line, "sd x%d,%d(t6)\n", n, n * 8);
    else
      StrPrint(line, "ld x%d,%d(t6)\n", n, n * 8);
    StrCat(dst, line);
    i++;
  }
  // The float registers ride along: same base, offset by 1024. Without them `fadd.d fa0,fa1,fa2`
  // stepped and left nothing to look at — the value was in f10 and f10 was not saved anywhere.
  n = 0;
  while (n < ASM_FREGS) {
    if (store)
      StrPrint(line, "fsd f%d,%d(t6)\n", n, ASM_FCTX_OFF + n * 8);
    else
      StrPrint(line, "fld f%d,%d(t6)\n", n, ASM_FCTX_OFF + n * 8);
    StrCat(dst, line);
    n++;
  }
  if (store) {
    // t5 has been stored, so it can carry the parked t6 into its slot
    StrPrint(line, "ld x30,8(sp)\nsd x30,%d(t6)\naddi sp,sp,16\n", ASM_CTX_BASE_REG * 8);
    StrCat(dst, line);
  } else {
    StrPrint(line, "ld x%d,%d(t6)\n", ASM_CTX_BASE_REG, ASM_CTX_BASE_REG * 8);
    StrCat(dst, line);
  }
}

// The float register's ABI name, which is what anyone typing at a stepper uses.
U0 AsmFRegName(I64 n, U8 *out)
{
  if (n <= 7)
    StrPrint(out, "ft%d", n);
  else if (n <= 9)
    StrPrint(out, "fs%d", n - 8);
  else if (n <= 17)
    StrPrint(out, "fa%d", n - 10);
  else if (n <= 27)
    StrPrint(out, "fs%d", n - 16);
  else
    StrPrint(out, "ft%d", n - 20);
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
  i = 0;
  while (i < ASM_FREGS) {
    *(I64 *)(ASM_FCTX_PREV + i * 8) = *(I64 *)(ASM_FCTX + i * 8);
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
  i = 0;
  while (i < ASM_FREGS) {
    *(I64 *)(ASM_FCTX + i * 8) = 0;
    *(I64 *)(ASM_FCTX_PREV + i * 8) = 0;
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
//   sp/gp/tp/s0/ra belong to the running REPL and are left alone, so a line that writes them
//   is not carried to the next step. t6 IS carried, though it is also the wrapper's base
//   register — see AsmCtxBase for how.
public I64 AsmStep(U8 *text)
{
  U8 *src, nm[8];
  I64 i, n, now, was, changed = 0;
  U0 (*watch)();
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
  i = 0;
  while (i < ASM_FREGS) {
    now = *(I64 *)(ASM_FCTX + i * 8);
    was = *(I64 *)(ASM_FCTX_PREV + i * 8);
    if (now != was) {
      AsmFRegName(i, nm);
      // raw bits: a float's hex is what you check an encoding against, and printing it as a
      // number would round away the thing you are looking at
      "  %-4s %016X -> %016X\n", nm, was, now;
      changed++;
    }
    i++;
  }
  if (!changed)
    "  (no register changed)\n";
  if (asm_watch_fn) {
    watch = asm_watch_fn;
    watch();
  }
  return changed;
}
