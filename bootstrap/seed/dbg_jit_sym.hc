// dbg_jit_sym.hc -- SymNearest/Name/Base over jit_funs for repl-holyc (G1).
// Full REPL: seed/sym.hc. Thin image: man_sym has FnAddr but no reverse map.
// Include after jit.hc; do not include seed/sym.hc (Src clash with dir.hc).
I64 SymNearest(I64 addr)
{
  I64 i, best_i, ea, next;
  best_i = -1;
  for (i = 0; i < jit_nfun; i++) {
    ea = jit_funs[i].entry;
    if (!ea || ea > addr)
      continue;
    if (i + 1 < jit_nfun)
      next = jit_funs[i + 1].entry;
    else
      next = jit_at;
    if (next > ea && addr >= next)
      continue;
    if (best_i < 0 || ea > jit_funs[best_i].entry)
      best_i = i;
  }
  return best_i;
}

I64 SymBase(I64 addr)
{
  I64 i = SymNearest(addr);
  if (i < 0)
    return 0;
  return jit_funs[i].entry;
}

U8 *SymName(I64 addr)
{
  I64 i = SymNearest(addr);
  if (i < 0)
    return 0;
  return jit_funs[i].name;
}
