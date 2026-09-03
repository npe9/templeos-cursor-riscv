// man.hc -- Man("Name"): integrated help. TempleOS Man jumps to a symbol's src / MN: page;
// here Man prints a Unix-complete text page sourced from the `// Name --` doc block above
// the definition, or from man_topics.hc for hardware/symbol topics (CLINT, PLIC, MEM_*, …).
// Lookup is case-insensitive where practical. Template (plain English + runnable examples):
//
//   // Name -- Name(args)
//   // NAME
//   //   Name - short description
//   // SYNOPSIS
//   //   ret Name(args);
//   // DESCRIPTION
//   //   What it does, when to use it, caveats — no assumed expert jargon.
//   // EXAMPLES
//   //   Name(...);          // 1–3 copy-paste lines for the UART REPL
//   // SEE ALSO
//   //   RelatedFun  RelatedTopic
//   // BUGS          (optional short limitations)
//
// Blocks are consecutive `//` lines. Stop at the next `// OtherFun --` or a blank line.
// Section titles (NAME, DESCRIPTION, ...) are not boundaries -- only `// Ident --` is.
// Prefer PutCh/UartStr here: Print varargs are fragile under the JIT frame spill.
//
// Manual sections (Unix-like; FunsS; groups by these, FunsSec(n); filters one):
//   1 shell/cmds     Run Src Funs Man Help MemMap Regs Sys SafeMode Recover Reset  (funs.hc man.hc boot.hc ops.hc sys.hc)
//   2 files/FS       Dir Cat Cd Copy Find File* Zmodem* FsChanges     (dir.hc files.hc zmodem.hc)
//   3 terminal       PutCh GetCh Term* Uart*                          (term.hc uart.hc)
//   4 editor         Ed Edit Vi EdC EditC                             (ed.hc edit.hc vim.hc)
//   5 debug/runtime  Disasm Bp StkRep Reg RegHelp CpuRep CSR* Trap*   (debug/csr/disasm/trap/...)
//   9 internal       mem heap helpers (mem.hc); holy_rt is NOT in the REPL hash
// Sections; prints this legend. FunSec("Name") / FunSecName(n) for reflection (FunPick too).
// Sections -- Sections()
// NAME
//   Sections - print the manual-section legend
// SYNOPSIS
//   U0 Sections();
// DESCRIPTION
//   Lists the numbered help groups used by FunsS / FunsSec / FunSec. Use this when
//   browsing which shell, file, editor, or debug APIs belong together.
// EXAMPLES
//   Sections;
//   FunsSec(1);   // shell/cmds
// SEE ALSO
//   Help  Man  FunsS  FunsSec
// BUGS
//   Legend is hand-maintained; new seeds may need a FunSec map update in the REPL C.
U0 Sections()
{
  UartStr("Manual sections (FunsS;  FunsSec(n);  FunSec(\"Name\")):\n");
  UartStr("  1 shell/cmds     2 files/FS     3 terminal\n");
  UartStr("  4 editor         5 debug/runtime  9 internal\n");
  UartStr("Topics (not functions): Man(\"CLINT\"); Man(\"PLIC\"); Man(\"Sys\");  see man_topics.hc\n");
  UartStr("HolyC seeds: uart/mem/print/str/term/...  (no C RuntimeRegister Man pages)\n");
}
// ManIdent -- ManIdent(c)
// NAME
//   ManIdent - identifier character test for Man parser
// SYNOPSIS
//   I64 ManIdent(I64 c);
// DESCRIPTION
//   Nonzero if c is A-Z, a-z, 0-9, or underscore (HolyC identifier body).
// INPUTS
//   c - character code
// OUTPUTS
//   1 if identifier char, else 0
// BUGS
//   Does not accept '$' (TempleOS special names).
I64 ManIdent(I64 c)
{
  if (c >= 'A' && c <= 'Z')
    return 1;
  if (c >= 'a' && c <= 'z')
    return 1;
  if (c >= '0' && c <= '9')
    return 1;
  if (c == '_')
    return 1;
  return 0;
}
U8 ManNm[40];
// ManHex -- ManHex(v)
// NAME
//   ManHex - print hex without Print
// SYNOPSIS
//   U0 ManHex(I64 v);
// DESCRIPTION
//   Writes v as 8 hex digits (lowercase A-F via table) using PutCh.
// INPUTS
//   v - value
// OUTPUTS
//   UART text; no return
// BUGS
//   Always 8 nybbles (low 32 bits of the shift walk); fine for RV pointers in practice.
U0 ManHex(I64 v)
{
  I64 i, d;
  U8 *h = "0123456789ABCDEF";
  for (i = 28; i >= 0; i = i - 4) {
    d = (v >> i) & 15;
    PutCh(h[d]);
  }
}
// ManDec -- ManDec(v)
// NAME
//   ManDec - print decimal without Print
// SYNOPSIS
//   U0 ManDec(I64 v);
// DESCRIPTION
//   Writes a signed decimal integer with PutCh.
// INPUTS
//   v - value (negative prints a leading '-')
// OUTPUTS
//   UART text; no return
// BUGS
//   None known.
U0 ManDec(I64 v)
{
  U8 b[20];
  I64 n, x;
  if (v < 0) {
    PutCh('-');
    v = -v;
  }
  if (!v) {
    PutCh('0');
    return;
  }
  n = 0;
  x = v;
  while (x) {
    b[n] = x % 10 + '0';
    n++;
    x = x / 10;
  }
  while (n > 0) {
    n--;
    PutCh(b[n]);
  }
}
// ManChIEq -- ManChIEq(a,b)
// NAME
//   ManChIEq - case-insensitive ASCII char equality
// SYNOPSIS
//   I64 ManChIEq(I64 a,I64 b);
I64 ManChIEq(I64 a, I64 b)
{
  if (a >= 'A' && a <= 'Z')
    a += 32;
  if (b >= 'A' && b <= 'Z')
    b += 32;
  return a == b;
}
// ManDoc -- ManDoc(s,name)
// NAME
//   ManDoc - find `// Name --` in a source unit (case-insensitive name)
// SYNOPSIS
//   U8 *ManDoc(U8 *s,U8 *name);
// DESCRIPTION
//   Scans s for a man-page anchor line `// Name -- ...` and returns a pointer to that
//   `//`. TempleOS Man uses hash src_link / MN:; we locate the comment block instead.
//   Name match is case-insensitive (Clint / CLINT / clint).
// INPUTS
//   s - source text (may be NULL)
//   name - symbol name
// OUTPUTS
//   Pointer into s at the doc block, or NULL if not found / NULL args
// BUGS
//   Requires the ` --` after the name; bare `// Name` is not an anchor.
U8 *ManDoc(U8 *s, U8 *name)
{
  I64 i, j, k;
  if (!s || !name)
    return 0;
  i = 0;
  while (s[i]) {
    if (s[i] == '/' && s[i + 1] == '/' && s[i + 2] == ' ') {
      j = i + 3;
      k = 0;
      while (name[k] && s[j + k] && ManChIEq(name[k], s[j + k]))
        k++;
      if (k && !name[k] && s[j + k] == ' ' && s[j + k + 1] == '-' && s[j + k + 2] == '-')
        return s + i;
    }
    while (s[i] && s[i] != '\n')
      i++;
    if (s[i])
      i++;
  }
  return 0;
}
// ManDocCanon -- ManDocCanon(s,name) — copy anchored Name into ManNm (file spelling)
U0 ManDocCanon(U8 *s, U8 *name)
{
  I64 j, k;
  s = ManDoc(s, name);
  if (!s)
    return;
  j = 3;
  // past "// "
  k = 0;
  while (ManIdent(s[j]) && k < 39) {
    ManNm[k] = s[j];
    k++;
    j++;
  }
  ManNm[k] = 0;
}
// ManPut -- ManPut(s,name)
// NAME
//   ManPut - print a symbol's man-page comment block
// SYNOPSIS
//   U0 ManPut(U8 *s,U8 *name);
// DESCRIPTION
//   Prints the leading `//` doc block for Name from s (after ManDoc). Strips the `// `
//   prefix so the UART looks like a man page. Stops at the next `// Other --` or a blank
//   line. Section headers (`// NAME`, `// BUGS`, ...) are part of the page.
// INPUTS
//   s - source unit or doc file text
//   name - symbol to document
// OUTPUTS
//   UART text; no return
// BUGS
//   If no `// Name --` block exists, prints a short definition snippet and a hint.
U0 ManPut(U8 *s, U8 *name)
{
  I64 i, j, k, m, first;
  U8 *doc, *base;
  if (!name)
    name = "";
  if (!s) {
    UartStr("(no HolyC source -- a C builtin)\n");
    return;
  }
  base = s;
  doc = ManDoc(s, name);
  if (!doc) {
    i = 0;
    while (s[i] && s[i] != '{' && s[i] != '\n' && i < 100) {
      PutCh(s[i]);
      i++;
    }
    PutCh('\n');
    UartStr("(add // Name -- Name(...); then NAME/SYNOPSIS/DESCRIPTION/EXAMPLES/SEE ALSO)\n");
    return;
  }
  s = doc;
  i = 0;
  first = 1;
  while (s[i] == ' ' || s[i] == 9 || s[i] == '\n' || s[i] == '\r')
    i++;
  if (s[i] == '/' && s[i + 1] == '/') {
    while (s[i] == '/' && s[i + 1] == '/') {
      if (!first && s[i + 2] == ' ') {
        j = i + 3;
        // Boundary is only `// OtherName --`, not `// NAME` / `// DESCRIPTION`.
        if (ManIdent(s[j])) {
          m = j;
          while (ManIdent(s[m]))
            m++;
          if (s[m] == ' ' && s[m + 1] == '-' && s[m + 2] == '-') {
            k = 0;
            while (name[k] && s[j + k] && ManChIEq(name[k], s[j + k]))
              k++;
            if (!(k && !name[k] && j + k == m))
              break;
          }
        }
      }
      j = i + 2;
      if (s[j] == ' ')
        j++;
      while (s[j] && s[j] != '\n') {
        PutCh(s[j]);
        j++;
      }
      PutCh('\n');
      i = j;
      if (s[i])
        i++;
      first = 0;
      if (s[i] == '\n')
        break;
    }
  } else {
    s = base;
    i = 0;
    while (s[i] && s[i] != '{' && s[i] != '\n' && i < 100) {
      PutCh(s[i]);
      i++;
    }
    PutCh('\n');
    UartStr("(add // Name -- Name(...); then NAME/SYNOPSIS/DESCRIPTION/EXAMPLES/SEE ALSO)\n");
  }
}
// ManHdr -- ManHdr()
// NAME
//   ManHdr - print address / size / section header for ManNm
// SYNOPSIS
//   U0 ManHdr();
// DESCRIPTION
//   Emits the Man page banner: address, HolyC size or C-builtin tag, manual section,
//   and Uf/Src/Callers deep-dive hints (TempleOS-style "go look at the code").
// INPUTS
//   none (uses global ManNm)
// OUTPUTS
//   UART text; no return
// BUGS
//   Silent if FnAddr(ManNm) is 0 (Man() still prints the doc body via SrcText, with a
//   NOT IN REPL banner when the page is doc-only).
U0 ManHdr()
{
  I64 a, n, sec;
  U8 *sn;
  a = FnAddr(ManNm);
  if (!a)
    return;
  n = FnSize(ManNm);
  UartStr(ManNm);
  UartStr(": 0x");
  ManHex(a);
  if (n) {
    UartStr(", ");
    ManDec(n);
    UartStr(" bytes (HolyC)\n");
  } else
    UartStr(" (C builtin)\n");
  sec = FunSec(ManNm);
  sn = FunSecName(sec);
  UartStr("  section ");
  ManDec(sec);
  UartStr(" (");
  if (sn)
    UartStr(sn);
  UartStr(")\n");
  UartStr("  --  Uf(\"");
  UartStr(ManNm);
  UartStr("\"); Src(\"");
  UartStr(ManNm);
  UartStr("\"); Callers(\"");
  UartStr(ManNm);
  UartStr("\");\n");
}
// ManFunCanon -- resolve HTT_FUN name case-insensitively into ManNm
I64 ManFunCanon(U8 *name)
{
  I64 body, mask, b, e, htt_fun;
  U8 *nm;
  I64 i;
  htt_fun = 0x100;
  // HTT_FUN (sym.hc)
  body = SymHashBody();
  mask = SymHashMask();
  if (!body || mask < 0 || !name)
    return 0;
  for (b = 0; b <= mask; b++) {
    e = *(I64 *)(body + b * 8);
    while (e) {
      if ((*(I64 *)(e + 16) & htt_fun)) {
        nm = *(I64 *)(e + 8);
        if (nm && !StrICmp(nm, name)) {
          i = 0;
          while (nm[i] && i < 39) {
            ManNm[i] = nm[i];
            i++;
          }
          ManNm[i] = 0;
          return 1;
        }
      }
      e = *(I64 *)e;
    }
  }
  return 0;
}
// ManSrcCanon -- resolve srcmap name case-insensitively into ManNm
I64 ManSrcCanon(U8 *name)
{
  U8 *base, *ent, *nm;
  I64 i, max, j, stride;
  stride = 112;
  // SRCMAP_STRIDE
  base = SrcMapBase();
  max = SrcMapMax();
  if (!base || !name)
    return 0;
  for (i = 0; i < max; i++) {
    ent = base + i *stride;
    if (*(I32 *)ent) {
      nm = ent + 4;
      if (!StrICmp(nm, name)) {
        j = 0;
        while (nm[j] && j < 39) {
          ManNm[j] = nm[j];
          j++;
        }
        ManNm[j] = 0;
        return 1;
      }
    }
  }
  return 0;
}
// DocFileFor -- topic/symbol man pages live in man_topics.hc (redefines stub)
// NAME
//   DocFileFor - memfs file holding a `// Name --` topic page
U8 *DocFileFor(U8 *name)
{
  U8 *s;
  if (!name || !*name)
    return 0;
  s = FileRead("man_topics.hc");
  if (!s)
    s = FileRead("Doc/man_topics.hc");
  if (!s)
    return 0;
  if (ManDoc(s, name))
    return "man_topics.hc";
  return 0;
}
// ManUnitFor -- memfs basename whose `// Name --` documents Name
// Explicit FileRead list (no U8*[] table — AOT pointer-index hazards).
U8 *ManUnitFor(U8 *name)
{
  U8 *s, *path, *base;
  I64 j, pass;
  if (!name || !*name)
    return 0;
  for (pass = 0; pass < 18; pass++) {
    if (pass == 0)
      path = "print.hc";
    else if (pass == 1)
      path = "str.hc";
    else if (pass == 2)
      path = "mem.hc";
    else if (pass == 3)
      path = "files.hc";
    else if (pass == 4)
      path = "dir.hc";
    else if (pass == 5)
      path = "run.hc";
    else if (pass == 6)
      path = "fs.hc";
    else if (pass == 7)
      path = "uart.hc";
    else if (pass == 8)
      path = "boot.hc";
    else if (pass == 9)
      path = "man.hc";
    else if (pass == 10)
      path = "man_topics.hc";
    else if (pass == 11)
      path = "funs.hc";
    else if (pass == 12)
      path = "log.hc";
    else if (pass == 13)
      path = "Lib/print.hc";
    else if (pass == 14)
      path = "Lib/log.hc";
    else if (pass == 15)
      path = "Doc/man_topics.hc";
    else if (pass == 16)
      path = "Doc/man.hc";
    else
      path = "Apps/funs.hc";
    s = FileRead(path);
    if (!s)
      continue;
    if (ManDoc(s, name)) {
      base = path;
      for (j = 0; path[j]; j++)
        if (path[j] == '/')
          base = path + j + 1;
      j = 0;
      while (base[j] && j < 63) {
        srcfile_buf[j] = base[j];
        j++;
      }
      srcfile_buf[j] = 0;
      return srcfile_buf;
    }
  }
  return 0;
}
// SymFile -- SymFile("Name") (redefines sym.hc; srcmap first, then memfs Man scan)
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
  f = ManUnitFor(SymTmp);
  if (f)
    return f;
  f = ManUnitFor(name);
  if (f)
    return f;
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
// SrcFile -- SrcFile("Name") (redefines sym.hc; keep srcmap spill for legacy)
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
// SrcText -- SrcText("Name") (redefines sym.hc; srcmap → ManUnitFor → topics)
U8 *SrcText(U8 *name)
{
  U8 *s, *f;
  if (!name || !*name)
    return 0;
  s = SrcmapGet(name);
  if (s)
    return s;
  f = ManUnitFor(name);
  if (f)
    return FileRead(f);
  f = DocFileFor(name);
  if (f)
    return FileRead(f);
  return 0;
}
// Man -- Man("Name")
// NAME
//   Man - owner's manual for a symbol or topic
// SYNOPSIS
//   U0 Man(U8 *name);
// DESCRIPTION
//   Prints a short help page for a HolyC function or a hardware/topic name. Prefer this
//   over reading raw source when learning an API. Pages come from the `// Name --` block
//   above the definition, or from man_topics.hc for topics like CLINT / PLIC / SiFive.
//   Lookup is case-insensitive where practical (Print/print, CLINT/Clint). Pass NULL or
//   "" and you get "Man: nil" — never a crash. After the page, Uf/Src/Callers dig deeper.
// EXAMPLES
//   Man("Print");
//   Man("Clint");     // same topic as Man("CLINT")
//   Man("MemMap");
// SEE ALSO
//   Help  Src  Uf  Sections  CLINT  PLIC
// BUGS
//   No DolDoc / MN: hyperlinks yet. Missing doc blocks fall back to a definition snippet.
//   Topic pages are documentation only (not callable). FnAddr=0 with orphan SrcText prints
//   NOT IN REPL — do not treat that name as a live function.
U0 Man(U8 *name)
{
  I64 i, topic;
  U8 *src, *df;
  if (!name || !*name) {
    UartStr("Man: nil\n");
    return;
  }
  i = 0;
  while (name[i] && i < 39) {
    ManNm[i] = name[i];
    i++;
  }
  ManNm[i] = 0;
  if (!ManFunCanon(ManNm))
    ManSrcCanon(ManNm);
  df = DocFileFor(ManNm);
  topic = 0;
  if (df) {
    src = FileRead(df);
    if (src) {
      ManDocCanon(src, ManNm);
      topic = 1;
    }
  } else
    src = 0;
  if (!FnAddr(ManNm) && !SrcText(ManNm) && !topic) {
    UartStr("Man: no such symbol: ");
    UartStr(ManNm);
    PutCh('\n');
    return;
  }
  if (topic && !FnAddr(ManNm)) {
    UartStr(ManNm);
    UartStr(": topic (see man_topics.hc)\n");
    UartStr("  --  Man(\"CLINT\"); Man(\"TimerArm\"); Man(\"PLIC\"); Sections;\n");
    ManPut(src, ManNm);
    return;
  }
  if (!FnAddr(ManNm)) {
    UartStr("Man: ");
    UartStr(ManNm);
    UartStr(" - NOT IN REPL (FnAddr=0; doc-only)\n");
  }
  ManHdr;
  ManPut(SrcText(ManNm), ManNm);
}
// SrcFileRep / FnSizeRep — UART reports (thin-image smoke; JIT Print %s is fragile)
U0 SrcFileRep(U8 *name)
{
  U8 *f;
  UartStr("SrcFile ");
  if (name)
    UartStr(name);
  UartStr("=");
  f = SrcFile(name);
  if (f)
    UartStr(f);
  else
    UartStr("(nil)");
  PutCh('\n');
}

U0 FnSizeRep(U8 *name)
{
  UartStr("FnSize ");
  if (name)
    UartStr(name);
  UartStr("=");
  ManDec(FnSize(name));
  PutCh('\n');
}
