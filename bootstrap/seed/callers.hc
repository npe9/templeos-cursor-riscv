// callers.hc -- reverse call xref. Callers("Foo") lists JIT functions that call Foo.
// HolyC CallersScan: host slot on legacy REPL, else SymHash walk, else g_callers_hc
// (repl-holyc sets this to a JitFind body scanner). Soft dbg lane (G1).
#define CALLERS_MAX 64
I64 g_caller_n;
U8 *g_caller_names[CALLERS_MAX];
I64 (*g_callers_hc)(U8 *name);
I64 CallersHasDirect(I64 entry, I64 size, I64 target)
{
  I64 i, nwords, pc, auipc_imm, jalr_imm;
  U32 w0, w1;
  if (!entry || !target || size < 8)
    return 0;
  nwords = size / 4;
  for (i = 0; i + 1 < nwords; i++) {
    w0 = *(U32 *)(entry + i * 4);
    w1 = *(U32 *)(entry + i * 4 + 4);
    if ((w0 & 0x7F) != 0x17)
      continue;
    if (((w0 >> 7) & 0x1F) != 1)
      continue;
    if ((w1 & 0x7F) != 0x67)
      continue;
    if (((w1 >> 7) & 0x1F) != 1)
      continue;
    if (((w1 >> 15) & 0x1F) != 1)
      continue;
    pc = entry + i * 4;
    auipc_imm = w0 & 0xFFFFF000;
    jalr_imm = (w1 << 20) >> 20;
    if (pc + auipc_imm + jalr_imm == target)
      return 1;
  }
  return 0;
}

I64 CallersHasAbsLit(I64 entry, I64 size, I64 target)
{
  I64 i, lim;
  if (!entry || !target || size < 8)
    return 0;
  lim = size - 8;
  for (i = 0; i <= lim; i += 4)
    if (*(I64 *)(entry + i) == target)
      return 1;
  return 0;
}

I64 CallersScanHc(U8 *name)
{
  I64 body, mask, b, e, te, target, sz, i, j;
  U8 *nm, *key;
  g_caller_n = 0;
  if (!name || !*name) {
    UartStr("Callers: need a name\n");
    return 0;
  }
  target = FnAddr(name);
  if (!target) {
    UartStr("Callers: no such function: ");
    UartStr(name);
    PutCh('\n');
    return 0;
  }
  body = SymHashBody();
  mask = SymHashMask();
  if (!body || mask < 0) {
    if (g_callers_hc)
      return g_callers_hc(name);
    UartStr("Callers: no symbol table\n");
    return 0;
  }
  for (b = 0; b <= mask && g_caller_n < CALLERS_MAX; b++) {
    e = *(I64 *)(body + b * 8);
    while (e && g_caller_n < CALLERS_MAX) {
      if (*(I64 *)(e + 16) & HTT_FUN) {
        sz = *(I64 *)(e + 40);
        te = *(I64 *)(e + 56);
        nm = *(U8 **)(e + 8);
        if (sz > 0 && te && te != target)
          if (CallersHasDirect(te, sz, target) || CallersHasAbsLit(te, sz, target)) {
            g_caller_names[g_caller_n] = nm;
            g_caller_n++;
          }
      }
      e = *(I64 *)e;
    }
  }
  for (i = 1; i < g_caller_n; i++) {
    key = g_caller_names[i];
    j = i - 1;
    while (j >= 0 && StrCmp(g_caller_names[j] ? g_caller_names[j] : "", key ? key : "") > 0) {
      g_caller_names[j + 1] = g_caller_names[j];
      j--;
    }
    g_caller_names[j + 1] = key;
  }
  if (!g_caller_n) {
    UartStr("Callers: no JIT callers of ");
    UartStr(name);
    PutCh('\n');
    return 0;
  }
  for (i = 0; i < g_caller_n; i++) {
    "  %d) %s", i + 1, g_caller_names[i] ? g_caller_names[i] : "?";
    if (SrcmapGet(g_caller_names[i]))
      UartStr("  [src]");
    PutCh('\n');
  }
  "(%d callers of %s)\n", g_caller_n, name;
  return g_caller_n;
}

I64 CallersScan(U8 *name)
{
  I64 (*scan)(U8 *name);
  scan = *(I64 *)0x870010E8;
  if (SoftDbgSlotFnOk(scan)) {
    g_caller_n = scan(name);
    return g_caller_n;
  }
  return CallersScanHc(name);
}

I64 CallerCnt()
{
  I64 (*cnt)();
  cnt = *(I64 *)0x87001120;
  if (SoftDbgSlotFnOk(cnt))
    return cnt();
  return g_caller_n;
}

U8 *CallerName(I64 idx)
{
  U8 * (*nm)(I64 idx);
  nm = *(I64 *)0x87001118;
  if (SoftDbgSlotFnOk(nm))
    return nm(idx);
  if (idx < 0 || idx >= g_caller_n)
    return 0;
  return g_caller_names[idx];
}
// Callers -- Callers("Name")
// NAME
//   Callers - list HolyC functions that call Name.
// SYNOPSIS
//   Callers("Name")
U0 Callers(U8 *name)
{
  CallersScan(name);
}

U0 WhoCalls(U8 *name)
{
  Callers(name);
}

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
