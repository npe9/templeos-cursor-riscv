// man_sym.hc -- thin Fn*/Fun*/Sym* for repl-holyc Man/Funs (G4).
// dbg owns seed/sym.hc (host-slot hash/srcmap). This file is man-lane only:
// JitFind-backed FnAddr/FnSize + memfs-oriented Fun* listing. No host-slot addresses.
// Include after jit.hc; man.hc redefines DocFileFor and adds SrcText/SrcFile.
#define HTT_FUN 0x100
#define SRCMAP_STRIDE 112
U8 SymTmp[64];
U8 srcfile_buf[64];
U8 fun_sec_name_buf[24];
I64 SymHash()
{
  return 0;
}

I64 SymHashMask()
{
  return -1;
}

I64 SymHashBody()
{
  return 0;
}
// complete.hc CompCollectSyms — CompAdd catalog + session DefRegister (#define).
I64 SymDefineHashBody()
{
  return 0;
}

I64 SymDefineHashMask()
{
  return -1;
}

U8 *SrcMapBase()
{
  return 0;
}

I64 SrcMapMax()
{
  return 0;
}

U8 *SrcmapGet(U8 *name)
{
  return 0;
}

U8 *SrcmapFileOf(U8 *name)
{
  return 0;
}

I64 SymStrEq(U8 *a, U8 *b)
{
  if (!a || !b)
    return 0;
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return !*a && !*b;
}

U0 NameDotHc(U8 *name, U8 *out)
{
  I64 j = 0;
  while (name[j] && j < 31) {
    out[j] = name[j];
    j++;
  }
  out[j] = '.';
  out[j + 1] = 'h';
  out[j + 2] = 'c';
  out[j + 3] = 0;
}

I64 SymCanonInto(U8 *name, U8 *out)
{
  I64 j, i;
  if (!name || !out)
    return 0;
  j = JitFind(name);
  if (j >= 0) {
    i = 0;
    while (jit_funs[j].name[i] && i < 63) {
      out[i] = jit_funs[j].name[i];
      i++;
    }
    out[i] = 0;
    return 1;
  }
  i = 0;
  while (name[i] && i < 63) {
    out[i] = name[i];
    i++;
  }
  out[i] = 0;
  return 0;
}

I64 FnAddr(U8 *name)
{
  I64 i;
  if (!name || !*name)
    return 0;
  i = JitFind(name);
  if (i < 0)
    return 0;
  return jit_funs[i].entry;
}

I64 FnSize(U8 *name)
{
  // Thin image has no ELF/hash size table; nonzero marks a live Jit symbol.
  if (!FnAddr(name))
    return 0;
  return 64;
}

U8 *DocFileFor(U8 *name)
{
  return 0;
}

I64 FunSecFromFile(U8 *file)
{
  U8 *b, *p;
  if (!file)
    return 0;
  b = file;
  for (p = file; *p; p++)
    if (*p == '/')
      b = p + 1;
  if (SymStrEq(b, "man.hc") || SymStrEq(b, "boot.hc") || SymStrEq(b, "ops.hc") || SymStrEq(b, "funs.hc") || SymStrEq(b, "run.hc") || SymStrEq(b, "sym.hc") || SymStrEq(b, "man_sym.hc") || SymStrEq(b, "eval.hc") || SymStrEq(b, "repl.hc") || SymStrEq(b, "log.hc") || SymStrEq(b, "sys.hc"))
    return 1;
  if (SymStrEq(b, "dir.hc") || SymStrEq(b, "files.hc") || SymStrEq(b, "fs.hc") || SymStrEq(b, "zmodem.hc") || SymStrEq(b, "fs_dump_changes.hc"))
    return 2;
  if (SymStrEq(b, "uart.hc") || SymStrEq(b, "term.hc") || SymStrEq(b, "str.hc") || SymStrEq(b, "print.hc"))
    return 3;
  if (SymStrEq(b, "ed.hc") || SymStrEq(b, "edit.hc") || SymStrEq(b, "vim.hc"))
    return 4;
  if (SymStrEq(b, "debug.hc") || SymStrEq(b, "disasm.hc") || SymStrEq(b, "start.hc") || SymStrEq(b, "trap.hc") || SymStrEq(b, "timer.hc") || SymStrEq(b, "math.hc") || SymStrEq(b, "csr.hc") || SymStrEq(b, "man_topics.hc") || SymStrEq(b, "jit.hc"))
    return 5;
  if (SymStrEq(b, "mem.hc"))
    return 9;
  return 0;
}

I64 FunSec(U8 *name)
{
  U8 *f;
  I64 s;
  f = SrcmapFileOf(name);
  if (f) {
    s = FunSecFromFile(f);
    if (s)
      return s;
  }
  // Do not consult srcfile_buf (Man/SrcFile scratch — stale across calls).
  if (!name || !*name)
    return 1;
  NameDotHc(name, SymTmp);
  s = FunSecFromFile(SymTmp);
  if (s)
    return s;
  return 1;
}

I64 FunCount()
{
  return jit_nfun;
}

U8 *FunName(I64 idx)
{
  if (idx < 0 || idx >= jit_nfun)
    return 0;
  return jit_funs[idx].name;
}

I64 FunHasSrc(I64 idx)
{
  U8 *nm = FunName(idx);
  if (!nm)
    return 0;
  if (FileLen(nm) >= 0)
    return 1;
  NameDotHc(nm, SymTmp);
  if (FileLen(SymTmp) >= 0)
    return 1;
  return 0;
}

I64 FunSecAt(I64 idx)
{
  U8 *nm = FunName(idx);
  if (!nm)
    return 0;
  return FunSec(nm);
}

U8 *FunSecName(I64 sec)
{
  U8 *t;
  I64 i;
  t = "?";
  if (sec == 1)
    t = "shell/cmds";
  else if (sec == 2)
    t = "files/FS";
  else if (sec == 3)
    t = "terminal";
  else if (sec == 4)
    t = "editor";
  else if (sec == 5)
    t = "debug/runtime";
  else if (sec == 9)
    t = "internal";
  i = 0;
  while (t[i] && i < 23) {
    fun_sec_name_buf[i] = t[i];
    i++;
  }
  fun_sec_name_buf[i] = 0;
  return fun_sec_name_buf;
}

U0 FunsList()
{
  I64 i, n, editable, pass, want, s, shown, any;
  I64 order[6];
  editable = 0;
  shown = 0;
  n = FunCount();
  order[0] = 1;
  order[1] = 2;
  order[2] = 3;
  order[3] = 4;
  order[4] = 5;
  order[5] = 9;
  UartStr("Symbol table: ");
  "%d", n;
  UartStr(" functions (by topic)\n");
  for (pass = 0; pass < 6; pass++) {
    want = order[pass];
    any = 0;
    for (i = 0; i < n && shown < 200; i++) {
      s = FunSecAt(i);
      if (s != want)
        continue;
      if (!any) {
        "--- %d %s ---\n", want, FunSecName(want);
        any = 1;
      }
      UartStr("  ");
      UartStr(FunName(i));
      if (FunHasSrc(i)) {
        UartStr("  [src]");
        editable++;
      }
      UartStr("\n");
      shown++;
    }
  }
  UartStr("  Src-editable: ");
  "%d\n", editable;
}

U0 FunsSec(I64 want)
{
  I64 i, n, cnt, s;
  cnt = 0;
  n = FunCount();
  "--- %d %s ---\n", want, FunSecName(want);
  for (i = 0; i < n; i++) {
    s = FunSecAt(i);
    if (!want || s == want) {
      "  %s\n", FunName(i);
      cnt++;
    }
  }
  if (!cnt)
    " (no functions in section %d)\n", want;
  else
    " in section %d\n", want;
}

U0 FunsS()
{
  FunsSec(1);
  FunsSec(2);
  FunsSec(3);
  FunsSec(4);
  FunsSec(5);
  FunsSec(9);
}
// Thin Funs: non-interactive list (FunPick/term.hc need dbg/ide lanes + RX ring).
U0 Funs(U8 *filt = 0)
{
  I64 i, n;
  U8 *nm;
  if (!filt || !*filt) {
    FunsList();
    return;
  }
  n = FunCount();
  UartStr("Funs filter: ");
  UartStr(filt);
  PutCh('\n');
  for (i = 0; i < n; i++) {
    nm = FunName(i);
    if (!nm)
      continue;
    if (!StrIMatch(filt, nm, 0))
      continue;
    UartStr("  ");
    UartStr(nm);
    PutCh('\n');
  }
}

U0 FunWrite()
{
  UartStr("FunWrite: not on thin repl-holyc (use FunsList;)\n");
}

U0 FunEd()
{
  UartStr("FunEd: not on thin repl-holyc\n");
}
