// callers.hc -- reverse call xref. Callers("Foo") lists JIT functions that call Foo (scans
// compiled bodies for the exe_addr-slot call sequence, plus PC-rel recursion). Numbered list;
// [src] means you can Src it. CallersGo prompts 1..n then Src. WhoCalls is an alias.
// Limits: only sized HolyC/JIT funs appear as callers (C builtins never do); function-pointer
// and asm calls are invisible; redefine+old code can leave stale hits until reboot.
// Callers -- Callers("Name")
// NAME
//   Callers - list HolyC functions that call Name.
// SYNOPSIS
//   Callers("Name")
// DESCRIPTION
//   list HolyC functions that call Name.
// INPUTS
//   "Name" - string argument
// OUTPUTS
//   list HolyC functions that call Name.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 Callers(U8 *name)
{
  CallersScan(name);
}
// WhoCalls -- WhoCalls("Name")
// NAME
//   WhoCalls - alias of Callers.
// SYNOPSIS
//   WhoCalls("Name")
// DESCRIPTION
//   alias of Callers.
// INPUTS
//   "Name" - string argument
// OUTPUTS
//   alias of Callers.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 WhoCalls(U8 *name)
{
  Callers(name);
}
// CallersGo -- CallersGo("Name")
// NAME
//   CallersGo - Callers then prompt 1..n and Src that caller.
// SYNOPSIS
//   CallersGo("Name")
// DESCRIPTION
//   Callers then prompt 1..n and Src that caller.
// INPUTS
//   "Name" - string argument
// OUTPUTS
//   Callers then prompt 1..n and Src that caller.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 CallersGo(U8 *name)
{
  I64 n, k;
  U8 *s;
  n = CallersScan(name);
  if (n <= 0)
    return;
  if (n == 1) {
    s = CallerName(0);
    if (s)
      Src(s);
    return;
  }
  if (n > 9) {
    "CallersGo: too many (%d) -- Callers; then Src(\"Name\");\n", n;
    return;
  }
  "number (1-%d, 0=abort): ", n;
  k = GetCh();
  PutCh(k);
  "\n";
  if (k < '1' || k >= '1' + n)
    return;
  s = CallerName(k - '1');
  if (s)
    Src(s);
}
