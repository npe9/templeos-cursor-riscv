// sym.hc -- FnAddr/Fun*/Src* over published hash + srcmap slots (no C RuntimeRegister).
#define HTT_FUN 0x100
#define SRCMAP_STRIDE 112
U8 SymTmp[64];
U8 srcfile_buf[64];
U8 fun_sec_name_buf[24];
U8 FunListBuf[8192];
I64 g_funs_buf[512];
I64 g_fun_n = 0;
I64 g_caller_n = 0;
I64 SymHash()
{
  return *(I64 *)0x87001070;
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
  return *(I64 *)0x87001048;
}

I64 SrcMapMax()
{
  return *(I64 *)0x87001050;
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
// Prefer host call_editor (slot 0x87001078): uses HolyC `editor` global, falls back to C Edit.
U0 HcCallEditor(U8 *name)
{
  U0 (*ed)(U8 *name);
  ed = *(I64 *)0x87001078;
  if (ed)
    ed(name);
}

U8 *SrcFile(U8 *name)
{
  U8 *f, *s;
  I64 n, j;
  if (!name || !*name)
    return 0;
  f = SrcmapFileOf(name);
  if (f)
    return f;
  s = SrcmapGet(name);
  if (s) {
    NameDotHc(name, SymTmp);
    n = 0;
    while (s[n])
      n++;
    FileWrite(SymTmp, s, n);
    j = 0;
    while (SymTmp[j] && j < 63) {
      srcfile_buf[j] = SymTmp[j];
      j++;
    }
    srcfile_buf[j] = 0;
    return srcfile_buf;
  }
  if (FileLen(name) >= 0)
    return name;
  NameDotHc(name, SymTmp);
  if (FileLen(SymTmp) >= 0) {
    j = 0;
    while (SymTmp[j] && j < 63) {
      srcfile_buf[j] = SymTmp[j];
      j++;
    }
    srcfile_buf[j] = 0;
    return srcfile_buf;
  }
  f = DocFileFor(name);
  if (f)
    return f;
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
    HcCallEditor(fn);
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
    HcCallEditor(SymTmp);
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
    HcCallEditor(SymTmp);
    Run(SymTmp);
    return;
  }
  fn = DocFileFor(name);
  if (fn) {
    HcCallEditor(fn);
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
  FunCollect();
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
  if (SymStrEq(b, "man.hc") || SymStrEq(b, "boot.hc") || SymStrEq(b, "funs.hc") || SymStrEq(b, "callers.hc") || SymStrEq(b, "run.hc") || SymStrEq(b, "sym.hc"))
    return 1;
  if (SymStrEq(b, "dir.hc") || SymStrEq(b, "files.hc") || SymStrEq(b, "fs.hc"))
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
// CallersScan/CallerName/CallerCnt/MemMap/Regs/StkRep: once-indirect to working C.
// Hollow HolyC bodies that printed labels without live data were a lie — keep real C until
// a HolyC port can read code_pos/callers_buf/GPR snap without host help.
I64 CallersScan(U8 *name)
{
  I64 (*scan)(U8 *name);
  scan = *(I64 *)0x870010E8;
  if (!scan) {
    g_caller_n = 0;
    return 0;
  }
  g_caller_n = scan(name);
  return g_caller_n;
}

I64 CallerCnt()
{
  I64 (*cnt)();
  cnt = *(I64 *)0x87001120;
  if (cnt)
    return cnt();
  return g_caller_n;
}

U8 *CallerName(I64 idx)
{
  U8 * (*nm)(I64 idx);
  nm = *(I64 *)0x87001118;
  if (!nm)
    return 0;
  return nm(idx);
}
// MemMap -- MemMap()
// NAME
//   MemMap - print RISC-V memory map with MEM_* symbols and owning drivers
// SYNOPSIS
//   U0 MemMap();
// DESCRIPTION
//   Lists RAM, live JIT code/heap, HolyC memfs/heap, FB, trap/regs snaps, stack,
//   and MMIO (UART/CLINT/PLIC/virtio/fw_cfg). Last column is the HolyC driver or
//   subsystem (e.g. RVUart16550 / uart.hc, RVTimer / CLINT, RVPlicHw, DskVirtioRV,
//   RVFb / ramfb). Dig-down: MemMapDrvFind("uart"); MemMapDrv; Regs; Reg("mstatus");
//   Man("MemMap"); RegHelp; MemMapFind("heap"); Print("%X\n", MEM_HEAP);
// INPUTS
//   none
// OUTPUTS
//   UART map + dig-down hints (driver column included)
// BUGS
//   Live sizes need C host slots on repl.elf. Driver column is virt defaults;
//   Kernel boards use Kernel/Drv/RVMemMap.HC + Kconfig.
U0 MemMap()
{
  I64 (*mm)();
  mm = *(I64 *)0x87001128;
  if (mm) {
    mm();
    return;
  }
  UartStr("MemMap: host slot empty — MemMapDrv; after csr.hc for driver legend\n");
}
// Regs -- Regs()
// NAME
//   Regs - dump all GPRs + CSRs with descriptions
// SYNOPSIS
//   U0 Regs();
// DESCRIPTION
//   Snapshots GPRs at the call site (xN / ABI / REG_*) and prints M-mode CSRs (mstatus,
//   mie, mip, mtvec, mepc, mcause, mtval, mscratch, satp, …) with short "what it does" text.
//   Dig-down: Reg("sp"); Reg("mstatus"); GetMStatus; CSRGet(CSR_MSTATUS); RegHelp; Man("Regs").
// INPUTS
//   none
// OUTPUTS
//   UART dump
// BUGS
//   GPR snap is C naked stub; CSR Get/Set live in csr.hc (real csrr/csrw).
U0 Regs()
{
  I64 (*rg)();
  rg = *(I64 *)0x87001130;
  if (rg) {
    rg();
    return;
  }
  UartStr("Regs: host slot empty\n");
}

U0 StkRep()
{
  I64 (*sr)();
  sr = *(I64 *)0x87001138;
  if (sr) {
    sr();
    return;
  }
  UartStr("StkRep: host slot empty\n");
}
