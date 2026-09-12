// Guest Cmp source: lands on RedSea as A:/Compiler/SoftGlbl.HC.
// Kernel.BIN SoftCall reads these bytes off the disk at runtime and hands them
// to the in-BIN lite Prs (KernelPrsGlblFunDefSoft), which Cmps and Calls them.
// Nothing here is an in-BIN literal; the Mac phase3.elf is not in the loop.
// Shape mirrors Compiler/Asm_RV.HC: file-scope glbls that a three-deep chain of
// funs writes and reads back through memory across each jal ra. Sum is
// 0 + 40 + 2 + 0 = 42.
I64 g_rv_asm_exports;
I64 g_rv_asm_pass;
I64 g_rv_asm_errs;
I64 RvAsmExportsInit()
{
  g_rv_asm_exports = 40;
  g_rv_asm_pass = 0;
  g_rv_asm_errs = 0;
  return 0;
}

I64 RvAsmExportsAdd()
{
  g_rv_asm_pass = RvAsmExportsInit() + 2;
  return 0;
}

I64 RvAsmExportsSum()
{
  return RvAsmExportsAdd() + g_rv_asm_exports + g_rv_asm_pass + g_rv_asm_errs;
}
RvAsmExportsSum();
