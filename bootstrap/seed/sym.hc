// sym.hc -- FnAddr/Fun*/Src* over published hash + srcmap slots (no C RuntimeRegister).
#define HTT_FUN 0x100
#define SRCMAP_STRIDE 112
U8 SymTmp[64];
U8 srcfile_buf[64];
U8 fun_sec_name_buf[24];
U8 FunListBuf[8192];
I64 g_funs_buf[512];
I64 g_fun_n = 0;
// g_caller_n lives in callers.hc (CallersScan)
// gd/^]/Src seek: globals so VLoad/EvLoad cant clobber them (must precede dir.hc in boot)
U8 JumpIdent[64];
U8 JumpFile[64];
I64 SymHash()
{
  return *(I64 *)MEM_HOST_SLOTS + 0x70;
}

I64 SymHashMask()
{
  I64 h = SymHash();
  if (!h)
    return -1;
  return *(I64 *)(h + 8);
}

I64 SymHashBody()
{
  I64 h = SymHash();
  if (!h)
    return 0;
  return *(I64 *)h;
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

I64 FnAddr(U8 *name)
{
  I64 body, mask, b, e;
  body = SymHashBody();
  mask = SymHashMask();
  if (!body || mask < 0)
    return 0;
  for (b = 0; b <= mask; b++) {
    e = *(I64 *)(body + b * 8);
    while (e) {
      if ((*(I64 *)(e + 16) & HTT_FUN) && SymStrEq (*(I64 *)(e + 8), name))
        return *(I64 *)(e + 56);
      e = *(I64 *)e;
    }
  }
  return 0;
}

I64 FnSize(U8 *name)
{
  I64 body, mask, b, e;
  body = SymHashBody();
  mask = SymHashMask();
  if (!body || mask < 0)
    return 0;
  for (b = 0; b <= mask; b++) {
    e = *(I64 *)(body + b * 8);
    while (e) {
      if ((*(I64 *)(e + 16) & HTT_FUN) && SymStrEq (*(I64 *)(e + 8), name))
        return *(I64 *)(e + 40);
      e = *(I64 *)e;
    }
  }
  return 0;
}

I64 SymNearest(I64 addr)
{
  I64 body, mask, b, e, best, ea, sz;
  body = SymHashBody();
  mask = SymHashMask();
  best = 0;
  if (!body || mask < 0)
    return 0;
  for (b = 0; b <= mask; b++) {
    e = *(I64 *)(body + b * 8);
    while (e) {
      if (*(I64 *)(e + 16) & HTT_FUN) {
        ea = *(I64 *)(e + 56);
        sz = *(I64 *)(e + 40);
        if (ea && ea <= addr && (!sz || addr < ea + sz) && (!best || ea > *(I64 *)(best + 56)))
          best = e;
      }
      e = *(I64 *)e;
    }
  }
  return best;
}

I64 SymBase(I64 addr)
{
  I64 e = SymNearest(addr);
  if (!e)
    return 0;
  return *(I64 *)(e + 56);
}

U8 *SymName(I64 addr)
{
  I64 e = SymNearest(addr);
  if (!e)
    return 0;
  return *(I64 *)(e + 8);
}

U8 *FunSegFind(I64 addr, I64 *off_p)
{
  I64 e = SymNearest(addr);
  if (!e) {
    if (off_p)
      *off_p = 0;
    return 0;
  }
  if (off_p)
    *off_p = addr - *(I64 *)(e + 56);
  return *(I64 *)(e + 8);
}

U8 *SrcMapBase()
{
  return *(I64 *)MEM_HOST_SLOTS + 0x48;
}

I64 SrcMapMax()
{
  return *(I64 *)MEM_HOST_SLOTS + 0x50;
}

U8 *SrcmapGet(U8 *name)
{
  U8 *base, *ent;
  I64 i, max;
  base = SrcMapBase();
  max = SrcMapMax();
  if (!base)
    return 0;
  for (i = 0; i < max; i++) {
    ent = base + i *SRCMAP_STRIDE;
    if (*(I32 *)ent && SymStrEq(ent + 4, name))
      return *(I64 *)(ent + 104);
  }
  return 0;
}

U8 *SrcmapFileOf(U8 *name)
{
  U8 *base, *ent;
  I64 i, max;
  base = SrcMapBase();
  max = SrcMapMax();
  if (!base)
    return 0;
  for (i = 0; i < max; i++) {
    ent = base + i *SRCMAP_STRIDE;
    if (*(I32 *)ent && SymStrEq(ent + 4, name) && ent[36])
      return ent + 36;
  }
  return 0;
}
// DocFileFor -- leftover C man pages lived in c_api.hc / rt.hc; both are empty of
// `// Name --` blocks now (holy_rt is not RuntimeRegister'd). Kept as a no-op so Src*
// paths stay honest: only srcmap / memfs names resolve.
U8 *DocFileFor(U8 *name)
{
  return 0;
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
  U8 *base, *ent, *nm;
  I64 body, mask, b, e, i, j, max;
  if (!name || !*name || !out)
    return 0;
  body = SymHashBody();
  mask = SymHashMask();
  if (body && mask >= 0) {
    for (b = 0; b <= mask; b++) {
      e = *(I64 *)(body + b * 8);
      while (e) {
        if ((*(I64 *)(e + 16) & HTT_FUN)) {
          nm = *(I64 *)(e + 8);
          if (nm && !StrICmp(nm, name)) {
            j = 0;
            while (nm[j] && j < 63) {
              out[j] = nm[j];
              j++;
            }
            out[j] = 0;
            return 1;
          }
        }
        e = *(I64 *)e;
      }
    }
  }
  base = SrcMapBase();
  max = SrcMapMax();
  if (base) {
    for (i = 0; i < max; i++) {
      ent = base + i *SRCMAP_STRIDE;
      if (*(I32 *)ent) {
        nm = ent + 4;
        if (!StrICmp(nm, name)) {
          j = 0;
          while (nm[j] && j < 63) {
            out[j] = nm[j];
            j++;
          }
          out[j] = 0;
          return 1;
        }
      }
    }
  }
  j = 0;
  while (name[j] && j < 63) {
    out[j] = name[j];
    j++;
  }
  out[j] = 0;
  return 0;
}
// SymFile -- SymFile("Name")
// NAME
//   SymFile - memfs path defining a symbol (no editor, no spill)
// SYNOPSIS
//   U8 *SymFile(U8 *name);
// DESCRIPTION
//   Returns the memfs filename where Name is defined: srcmap Run() origin,
//   an existing memfs seed (Name.hc), or man_topics.hc for hardware topics.
//   Case-insensitive for HolyC functions (Print/print). Silent on failure (0).
//   Unlike SrcFile, does not materialize srcmap spill files or print UART errors.
// EXAMPLES
//   Print("%s\n", SymFile("Print"));
//   Print("%s\n", SymFile("CLINT"));
//   if (!SymFile("Foo")) Print("Foo: no file\n");
// SEE ALSO
//   SrcFile  Src  SrcmapFileOf  DocFileFor  Man
// BUGS
//   REPL-only defs with srcmap text but no file return 0 until Src spills Name.hc.
U8 *SymFile(U8 *name)
{
  U8 *f, *df;
  I64 j;
  if (!name || !*name)
    return 0;
  SymCanonInto(name, SymTmp);
  f = SrcmapFileOf(SymTmp);
  if (f) {
    j = 0;
    while (f[j] && j < 63) {
      srcfile_buf[j] = f[j];
      j++;
    }
    srcfile_buf[j] = 0;
    return srcfile_buf;
  }
  if (FileLen(name) >= 0) {
    j = 0;
    while (name[j] && j < 63) {
      srcfile_buf[j] = name[j];
      j++;
    }
    srcfile_buf[j] = 0;
    return srcfile_buf;
  }
  NameDotHc(SymTmp, srcfile_buf);
  if (FileLen(srcfile_buf) >= 0)
    return srcfile_buf;
  NameDotHc(name, srcfile_buf);
  if (FileLen(srcfile_buf) >= 0)
    return srcfile_buf;
  df = DocFileFor(name);
  if (!df)
    df = DocFileFor(SymTmp);
  if (df) {
    j = 0;
    while (df[j] && j < 63) {
      srcfile_buf[j] = df[j];
      j++;
    }
    srcfile_buf[j] = 0;
    return srcfile_buf;
  }
  return 0;
}
// Prefer host call_editor (slot MEM_HOST_SLOTS+0x78): uses HolyC `editor` global, falls back to C Edit.
U0 HcCallEditor(U8 *name)
{
  U0 (*ed)(U8 *name);
  ed = *(I64 *)MEM_HOST_SLOTS + 0x78;
  if (ed)
    ed(name);
}

U8 *SrcFile(U8 *name)
{
  U8 *f, *s;
  I64 n;
  if (!name || !*name)
    return 0;
  f = SymFile(name);
  if (f)
    return f;
  SymCanonInto(name, SymTmp);
  s = SrcmapGet(SymTmp);
  if (s) {
    NameDotHc(SymTmp, srcfile_buf);
    n = 0;
    while (s[n])
      n++;
    FileWrite(srcfile_buf, s, n);
    return srcfile_buf;
  }
  UartStr("SrcFile: no source for ");
  UartStr(name);
  UartStr("\n");
  return 0;
}

U8 *SrcText(U8 *name)
{
  U8 *s, *f;
  s = SrcmapGet(name);
  if (s)
    return s;
  f = DocFileFor(name);
  if (f)
    return FileRead(f);
  return 0;
}
// Stash symbol for Vi/EditHoly seek-on-open (matches C src_jump_set).
U0 SrcJumpSet(U8 *name)
{
  I64 i;
  JumpIdent[0] = 0;
  if (!name || !*name)
    return;
  i = 0;
  while (name[i] && i < 63) {
    JumpIdent[i] = name[i];
    i++;
  }
  JumpIdent[i] = 0;
}
// Src("Name") -- TempleOS goto-definition: open defining source in preferred editor, then Run.
U0 Src(U8 *name)
{
  U8 *fn, *s;
  I64 n;
  U0 (*dasm)(U8 *name);
  if (!name || !*name) {
    UartStr("Src: no source\n");
    return;
  }
  fn = SrcmapFileOf(name);
  if (fn) {
    SrcJumpSet(name);
    HcCallEditor(fn);
    JumpIdent[0] = 0;
    Run(fn);
    return;
  }
  s = SrcmapGet(name);
  if (s) {
    NameDotHc(name, SymTmp);
    n = 0;
    while (s[n])
      n++;
    FileWrite(SymTmp, s, n);
    SrcJumpSet(name);
    HcCallEditor(SymTmp);
    JumpIdent[0] = 0;
    Run(SymTmp);
    return;
  }
  if (FileLen(name) >= 0) {
    HcCallEditor(name);
    Run(name);
    return;
  }
  NameDotHc(name, SymTmp);
  if (FileLen(SymTmp) >= 0) {
    SrcJumpSet(name);
    HcCallEditor(SymTmp);
    JumpIdent[0] = 0;
    Run(SymTmp);
    return;
  }
  fn = DocFileFor(name);
  if (fn) {
    SrcJumpSet(name);
    HcCallEditor(fn);
    JumpIdent[0] = 0;
    return;
    // comments only — no Run
  }
  if (FnAddr(name)) {
    UartStr("Src: no source for ");
    UartStr(name);
    UartStr(" -- disassembling:\n");
    dasm = FnAddr("Disasm");
    if (dasm)
      dasm(name);
    return;
  }
  UartStr("Src: no source for ");
  UartStr(name);
  UartStr(" (not a HolyC function or a file)\n");
}

U0 FunCollect()
{
  I64 body, mask, b, e;
  g_fun_n = 0;
  body = SymHashBody();
  mask = SymHashMask();
  if (!body || mask < 0)
    return;
  for (b = 0; b <= mask; b++) {
    e = *(I64 *)(body + b * 8);
    while (e) {
      if ((*(I64 *)(e + 16) & HTT_FUN) && *(I64 *)(e + 8) && g_fun_n < 512)
        g_funs_buf[g_fun_n++] = e;
      e = *(I64 *)e;
    }
  }
}

I64 FunCount()
{
  FunCollect();
  return g_fun_n;
}

U8 *FunName(I64 idx)
{
  /* Do not FunCollect() here — O(n) per call made Funs("Print") / FpRebuild
   * O(n²) and hung under QEMU at n=512. Call FunCount()/FunCollect() first. */
  if (idx < 0 || idx >= g_fun_n)
    return 0;
  return *(I64 *)(g_funs_buf[idx] + 8);
}

I64 FunHasSrc(I64 idx)
{
  U8 *nm = FunName(idx);
  if (!nm)
    return 0;
  if (SrcmapGet(nm))
    return 1;
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
  if (SymStrEq(b, "man.hc") || SymStrEq(b, "boot.hc") || SymStrEq(b, "ops.hc") || SymStrEq(b, "funs.hc") || SymStrEq(b, "callers.hc") || SymStrEq(b, "run.hc") || SymStrEq(b, "sym.hc") || SymStrEq(b, "log.hc") || SymStrEq(b, "sys.hc"))
    return 1;
  if (SymStrEq(b, "dir.hc") || SymStrEq(b, "files.hc") || SymStrEq(b, "fs.hc") || SymStrEq(b, "zmodem.hc"))
    return 2;
  if (SymStrEq(b, "uart.hc") || SymStrEq(b, "term.hc") || SymStrEq(b, "str.hc") || SymStrEq(b, "print.hc"))
    return 3;
  if (SymStrEq(b, "ed.hc") || SymStrEq(b, "edit.hc") || SymStrEq(b, "vim.hc"))
    return 4;
  if (SymStrEq(b, "debug.hc") || SymStrEq(b, "disasm.hc") || SymStrEq(b, "start.hc") || SymStrEq(b, "trap.hc") || SymStrEq(b, "timer.hc") || SymStrEq(b, "math.hc") || SymStrEq(b, "csr.hc") || SymStrEq(b, "man_topics.hc"))
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
  return 1;
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

U0 Funs()
{
  I64 i, n, editable;
  editable = 0;
  n = FunCount();
  if (n > 200)
    n = 200;
  // cap listing for UART
  UartStr("Symbol table: ");
  "%d", n;
  UartStr(" functions\n");
  for (i = 0; i < n; i++) {
    UartStr("  ");
    UartStr(FunName(i));
    if (FunHasSrc(i)) {
      UartStr("  [src]");
      editable++;
    }
    UartStr("\n");
  }
  UartStr("  Src-editable: ");
  "%d\n", editable;
}
// FunsList -- FunsList()
// NAME
//   FunsList - non-interactive dump of the function symbol table
// SYNOPSIS
//   U0 FunsList();
// DESCRIPTION
//   Prints up to 200 HTT_FUN names (UART-capped) with [src] when Src()/edit is
//   available. Prefer Funs; for the interactive filter → Src picker.
// EXAMPLES
//   FunsList;
// SEE ALSO
//   Funs  FunPick  FunsS  FunsSec  FunWrite
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
  FunsSec(0);
}

U0 FunWrite()
{
  I64 i, n;
  U8 *p, *nm, *q;
  n = FunCount();
  p = FunListBuf;
  for (i = 0; i < n && p < FunListBuf + 8000; i++) {
    nm = FunName(i);
    q = nm;
    if (!q)
      goto nxt;
    while (*q && p < FunListBuf + 8000) {
      *p++ = *q++;
    }
    *p++ = '\n';
    nxt:
  }
  *p = 0;
  FileWrite(".funlist", FunListBuf, p - FunListBuf);
  "wrote .funlist\n";
}
// CallersScan / MemMap / Regs / StkRep: MemMap+Regs in csr.hc; StkRep in debug.hc;
// CallersScan in callers.hc (HolyC + optional host slot / g_callers_hc).
// g_caller_n kept for CallerCnt compatibility with Fun* tooling.
