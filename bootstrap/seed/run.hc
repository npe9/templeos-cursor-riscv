// run.hc -- Run / Exec: prefer guest ExePutS when Compiler_RV is linked;
// fall back to host compile slot 0x87001000 for the Mac-AOT REPL bridge.
// Destination remains Compiler_RV + ExePutS. Do not grow jit.hc.
U0 HcCompile(U8 *src)
{
  I64 (*host)(U8 *src);
  if (!src)
    return;
  host = *(I64 *)0x87001000;
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
  p = *(I64 *)0x87001008;
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
//   FileRead the unit; Compiler_RV ExePutS when linked, else host slot.
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
  host = *(I64 *)0x87001000;
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
