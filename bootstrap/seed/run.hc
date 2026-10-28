// run.hc -- Run / Exec: A2 prefers guest ExePutS when Compiler_RV is live;
// fall back to host compile slot MEM_HOST_SLOTS+0x0 for the Mac-AOT REPL bridge.
// Destination remains Compiler_RV + ExePutS. Do not grow jit.hc.
Bool g_exepubs_prefer;
// set TRUE after CInit / when ExePutS is the live JIT
U0 HcCompile(U8 *src)
{
  I64 (*host)(U8 *src);
  if (!src)
    return;
  // A2: guest ExePutS first when Compiler_RV owns the loop
  if (g_exepubs_prefer) {
    ExePutS(src);
    return;
  }
  host = *(I64 *)MEM_HOST_SLOTS + 0x0;
  if (host)
    host(src);
  // REPL bridge (C JIT behind the slot)
  else ExePutS(src);
  // Kernel+Compiler_RV image (no host slot)
}

U0 RunSetFile(U8 *name)
{
  U8 *p;
  I64 i;
  p = *(I64 *)MEM_HOST_SLOTS + 0x8;
  if (!p)
    return;
  i = 0;
  if (name) {
    while (*name && i < 63) {
      p[i] = *name;
      name++;
      i++;
    }
  }
  p[i] = 0;
}
// Run -- Run("file")
// NAME
//   Run - compile and execute a memfs HolyC file
// SYNOPSIS
//   U0 Run(U8 *name);
// DESCRIPTION
//   Loads a .hc file from the memfs, compiles it, and runs the definitions /
//   top-level statements. Use after editing with Vi/Ed, or to load a demo
//   (e.g. timer.hc). On compile failure, ErrGo jumps to the error site.
// EXAMPLES
//   Run("timer.hc");
//   Dir;
//   Cat("boot.hc");
// SEE ALSO
//   Exec  Src  ErrGo  Fmt  Ed  Vi
// BUGS
//   Missing file prints an error and returns.
U0 Run(U8 *name)
{
  U8 *src;
  I64 n;
  I64 (*host)(U8 *src);
  src = FileRead(name);
  n = FileLen(name);
  if (!src || n < 0) {
    UartStr("Run: no such file: ");
    if (name)
      UartStr(name);
    UartStr("\n");
    return;
  }
  RunSetFile(name);
  if (g_exepubs_prefer) {
    ExePutS(src, name);
    RunSetFile("");
    return;
  }
  host = *(I64 *)MEM_HOST_SLOTS + 0x0;
  if (host)
    host(src);
  else
    ExePutS(src, name);
  RunSetFile("");
}
// Exec -- Exec(src)
U0 Exec(U8 *src)
{
  if (!src)
    return;
  RunSetFile("");
  HcCompile(src);
}
