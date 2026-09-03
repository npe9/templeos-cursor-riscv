// exepubs.hc — A2: TempleOS ExePutS owns this thin REPL's compile entry.
// Product guest Cmp path: make repl-cmp → build/repl-cmp.elf (Kernel+Compiler_RV).
// This image keeps a thin JitTry backend (size); do not grow jit.hc.
I64 g_exepubs_n;
// count of ExePutS compile entries this session
I64 ExePutS(U8 *buf, U8 *filename)
{
  I64 jr, armed;
  if (!buf)
    return 0;
  g_exepubs_n++;
  // filename reserved for Compiler_RV ExePutS(buf, filename) srcmap parity
  armed = 0;
  if (g_break_interactive) {
    BreakArm();
    HcUartTakeLeadingBreak();
    armed = 1;
    if (g_break_pending) {
      BreakDisarm();
      UartStr("\nInterrupted\n");
      return 1;
    }
  }
  jr = JitTry(buf);
  if (armed)
    BreakDisarm();
  if (jr < 0)
    return -1;
  if (jr > 0)
    return 1;
  return 0;
}

U0 HcCompile(U8 *src)
{
  if (!src)
    return;
  ExePutS(src, NULL);
}

U0 Exec(U8 *src)
{
  HcCompile(src);
}
