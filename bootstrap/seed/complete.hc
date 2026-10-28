// complete.hc -- case-insensitive Tab completion for editors (Vi / EditHoly / Ed).
// CompTab(line,max,list_ok): uses CompCx as cursor in/out. If a partial ident/path
// sits before CompCx, fill from HTT_FUN (via FunCollect) + #defines (HTT_DEFINE_STR
// via SymDefineHash when host publishes define_table; else explicit CompAdd of
// MemMapSelected.hc / csr.hc macros — AOT U8* define pipes are unreliable) + session
// #define names (DefRegister / DefTryRegister via ExePutS) or memfs (CI).
// Inside asm{} (see asm_complete.hc): opcodes / GPRs / CSR names instead of HolyC syms.
// Returns 1 if Tab was handled; 0 if caller should insert 2-space indent.
// Thin-path define Tab covers MEM_*/UART_*/VIRTIO_*/REG_*/CSR_* without host-slot addresses.
#define COMP_MAX 64
#define COMP_NAME 48
U8 CompNames[COMP_MAX][COMP_NAME];
I64 CompN;
I64 CompCx;
U8 CompPfx[128];
I64 CompIsIdent(I64 c)
{
  if (c >= 'a' && c <= 'z')
    return 1;
  if (c >= 'A' && c <= 'Z')
    return 1;
  if (c >= '0' && c <= '9')
    return 1;
  if (c == '_')
    return 1;
  return 0;
}

I64 CompIsPath(I64 c)
{
  if (CompIsIdent(c))
    return 1;
  if (c == '.' || c == '/' || c == '-' || c == '+')
    return 1;
  return 0;
}

I64 CompChEq(I64 a, I64 b)
{
  if (a >= 'A' && a <= 'Z')
    a += 32;
  if (b >= 'A' && b <= 'Z')
    b += 32;
  return a == b;
}

I64 CompPrefixEq(U8 *s, U8 *p, I64 plen)
{
  I64 i = 0;
  if (!s)
    return 0;
  while (i < plen) {
    if (!s[i] || !CompChEq(s[i], p[i]))
      return 0;
    i++;
  }
  return 1;
}

I64 CompCommonPfx(I64 n)
{
  I64 i, j;
  U8 c;
  if (n <= 0)
    return 0;
  i = 0;
  while (1) {
    c = CompNames[0][i];
    if (!c)
      return i;
    for (j = 1; j < n; j++)
      if (!CompNames[j][i] || !CompChEq(CompNames[j][i], c))
        return i;
    i++;
  }
}

I64 CompStrOk(U8 *s)
{
  I64 k = 0;
  if (!s)
    return 0;
  while (k < COMP_NAME) {
    if (!s[k])
      return k > 0;
    if (!CompIsIdent(s[k]) && s[k] != '.' && s[k] != '/')
      return 0;
    k++;
  }
  return 0;
}

U0 CompAdd(U8 *s, U8 *pfx, I64 plen)
{
  I64 i, k, same;
  if (!CompStrOk(s) || CompN >= COMP_MAX)
    return;
  if (!CompPrefixEq(s, pfx, plen))
    return;
  for (i = 0; i < CompN; i++) {
    same = 1;
    k = 0;
    while (k < COMP_NAME) {
      if (CompNames[i][k] != s[k]) {
        same = 0;
        break;
      }
      if (!s[k])
        break;
      k++;
    }
    if (same)
      return;
  }
  k = 0;
  while (k < COMP_NAME - 1 && s[k]) {
    CompNames[CompN][k] = s[k];
    k++;
  }
  CompNames[CompN][k] = 0;
  CompN++;
}
// Session #define registry (thin repl-holyc: no host define_table slot).
// DefTryRegister on ExePutS / ReplEvalOne; Tab via CompCollectDefines.
#define DEF_MAX 64
#define DEF_NAME 48
U8 DefNames[DEF_MAX][DEF_NAME];
I64 DefN;
U0 DefRegister(U8 *name)
{
  I64 i, k, same;
  if (!name || !name[0] || DefN >= DEF_MAX)
    return;
  if (!CompStrOk(name))
    return;
  for (i = 0; i < DefN; i++) {
    same = 1;
    k = 0;
    while (k < DEF_NAME) {
      if (DefNames[i][k] != name[k]) {
        same = 0;
        break;
      }
      if (!name[k])
        break;
      k++;
    }
    if (same)
      return;
  }
  k = 0;
  while (k < DEF_NAME - 1 && name[k]) {
    DefNames[DefN][k] = name[k];
    k++;
  }
  DefNames[DefN][k] = 0;
  DefN++;
}

U0 DefCollect(U8 *pfx, I64 plen)
{
  I64 i;
  for (i = 0; i < DefN; i++)
    CompAdd(&DefNames[i][0], pfx, plen);
}

I64 DefTryRegister(U8 *line)
{
  U8 *p, *start;
  U8 name[DEF_NAME];
  I64 i;
  if (!line)
    return 0;
  p = line;
  while (*p == ' ' || *p == '\t')
    p++;
  if (*p != '#')
    return 0;
  p++;
  while (*p == ' ' || *p == '\t')
    p++;
  if (p[0] != 'd' || p[1] != 'e' || p[2] != 'f' || p[3] != 'i' || p[4] != 'n' || p[5] != 'e')
    return 0;
  if (CompIsIdent(p[6]))
    return 0;
  p += 6;
  while (*p == ' ' || *p == '\t')
    p++;
  i = 0;
  while (i < DEF_NAME - 1 && CompIsIdent (*p)) {
    name[i] = *p;
    i++;
    p++;
  }
  name[i] = 0;
  if (i)
    DefRegister(name);
  // Only consume a define-only unit (no trailing stmts after this line).
  start = p;
  while (*start == ' ' || *start == '\t')
    start++;
  while (*start && *start != '\n')
    start++;
  if (*start == '\n') {
    start++;
    while (*start == ' ' || *start == '\t' || *start == '\n')
      start++;
    if (*start)
      return 0;
  }
  return 1;
}
// Thin path define catalog (MemMapSelected + csr.hc). AOT U8* pipes are
// unreliable — explicit CompAdd (proven for MEM_*). Before Fun* under COMP_MAX.
U0 CompCollectDefines(U8 *pfx, I64 plen)
{
  CompAdd("MEM_RAM", pfx, plen);
  CompAdd("MEM_TEST", pfx, plen);
  CompAdd("MEM_CLINT", pfx, plen);
  CompAdd("MEM_CLINT_MTIME_OFF", pfx, plen);
  CompAdd("MEM_CLINT_MTIMECMP_OFF", pfx, plen);
  CompAdd("MEM_MTIME", pfx, plen);
  CompAdd("MEM_MTIMECMP", pfx, plen);
  CompAdd("MEM_PLIC", pfx, plen);
  CompAdd("MEM_PLIC_ENABLE_OFF", pfx, plen);
  CompAdd("MEM_PLIC_THRESHOLD_OFF", pfx, plen);
  CompAdd("MEM_PLIC_CLAIM_OFF", pfx, plen);
  CompAdd("MEM_PLIC_PENDING_OFF", pfx, plen);
  CompAdd("MEM_UART", pfx, plen);
  CompAdd("MEM_UART1", pfx, plen);
  CompAdd("MEM_GPIO", pfx, plen);
  CompAdd("MEM_PRCI", pfx, plen);
  CompAdd("MEM_ETH", pfx, plen);
  CompAdd("MEM_VIRTIO", pfx, plen);
  CompAdd("MEM_VIRTIO_STRIDE", pfx, plen);
  CompAdd("MEM_FW_CFG", pfx, plen);
  CompAdd("MEM_RTC", pfx, plen);
  CompAdd("MEM_FS", pfx, plen);
  CompAdd("MEM_HEAP", pfx, plen);
  CompAdd("MEM_FB", pfx, plen);
  CompAdd("MEM_FIXED", pfx, plen);
  CompAdd("MEM_TRAP_SNAP", pfx, plen);
  CompAdd("MEM_REGS_SNAP", pfx, plen);
  CompAdd("MEM_HOST_SLOTS", pfx, plen);
  CompAdd("MEM_STACK", pfx, plen);
  CompAdd("MEM_COMPILER", pfx, plen);
  CompAdd("UART_LSR_OFF", pfx, plen);
  CompAdd("UART_LSR_THRE", pfx, plen);
  CompAdd("UART_LSR_DR", pfx, plen);
  CompAdd("VIRTIO_MAGIC", pfx, plen);
  CompAdd("VIRTIO_REG_MAGIC", pfx, plen);
  CompAdd("VIRTIO_REG_VERSION", pfx, plen);
  CompAdd("VIRTIO_REG_DEVICE_ID", pfx, plen);
  CompAdd("VIRTIO_REG_GUEST_PGSZ", pfx, plen);
  CompAdd("VIRTIO_REG_STATUS", pfx, plen);
  CompAdd("REG_ZERO", pfx, plen);
  CompAdd("REG_RA", pfx, plen);
  CompAdd("REG_SP", pfx, plen);
  CompAdd("REG_GP", pfx, plen);
  CompAdd("REG_TP", pfx, plen);
  CompAdd("REG_T0", pfx, plen);
  CompAdd("REG_T1", pfx, plen);
  CompAdd("REG_T2", pfx, plen);
  CompAdd("REG_S0", pfx, plen);
  CompAdd("REG_FP", pfx, plen);
  CompAdd("REG_S1", pfx, plen);
  CompAdd("REG_A0", pfx, plen);
  CompAdd("REG_A1", pfx, plen);
  CompAdd("REG_A2", pfx, plen);
  CompAdd("REG_A3", pfx, plen);
  CompAdd("REG_A4", pfx, plen);
  CompAdd("REG_A5", pfx, plen);
  CompAdd("REG_A6", pfx, plen);
  CompAdd("REG_A7", pfx, plen);
  CompAdd("REG_S2", pfx, plen);
  CompAdd("REG_S3", pfx, plen);
  CompAdd("REG_S4", pfx, plen);
  CompAdd("REG_S5", pfx, plen);
  CompAdd("REG_S6", pfx, plen);
  CompAdd("REG_S7", pfx, plen);
  CompAdd("REG_S8", pfx, plen);
  CompAdd("REG_S9", pfx, plen);
  CompAdd("REG_S10", pfx, plen);
  CompAdd("REG_S11", pfx, plen);
  CompAdd("REG_T3", pfx, plen);
  CompAdd("REG_T4", pfx, plen);
  CompAdd("REG_T5", pfx, plen);
  CompAdd("REG_T6", pfx, plen);
  CompAdd("CSR_SSTATUS", pfx, plen);
  CompAdd("CSR_SIE", pfx, plen);
  CompAdd("CSR_STVEC", pfx, plen);
  CompAdd("CSR_SSCRATCH", pfx, plen);
  CompAdd("CSR_SEPC", pfx, plen);
  CompAdd("CSR_SCAUSE", pfx, plen);
  CompAdd("CSR_STVAL", pfx, plen);
  CompAdd("CSR_SIP", pfx, plen);
  CompAdd("CSR_SATP", pfx, plen);
  CompAdd("CSR_MSTATUS", pfx, plen);
  CompAdd("CSR_MISA", pfx, plen);
  CompAdd("CSR_MEDELEG", pfx, plen);
  CompAdd("CSR_MIDELEG", pfx, plen);
  CompAdd("CSR_MIE", pfx, plen);
  CompAdd("CSR_MTVEC", pfx, plen);
  CompAdd("CSR_MCOUNTEREN", pfx, plen);
  CompAdd("CSR_MSCRATCH", pfx, plen);
  CompAdd("CSR_MEPC", pfx, plen);
  CompAdd("CSR_MCAUSE", pfx, plen);
  CompAdd("CSR_MTVAL", pfx, plen);
  CompAdd("CSR_MIP", pfx, plen);
  CompAdd("CSR_MCYCLE", pfx, plen);
  CompAdd("CSR_MINSTRET", pfx, plen);
  CompAdd("CSR_CYCLE", pfx, plen);
  CompAdd("CSR_TIME", pfx, plen);
  CompAdd("CSR_INSTRET", pfx, plen);
  CompAdd("CSR_MHARTID", pfx, plen);
  DefCollect(pfx, plen);
}

I64 CompCollectSyms(U8 *pfx, I64 plen)
{
  I64 body, mask, b, e, ty, nwalk, i, nfun;
  U8 *nm;
  CompN = 0;
  body = SymHashBody();
  mask = SymHashMask();
  if (body && mask >= 0) {
    nwalk = 0;
    for (b = 0; b <= mask && CompN < COMP_MAX; b++) {
      e = *(I64 *)(body + b * 8);
      while (e && CompN < COMP_MAX) {
        nwalk++;
        if (nwalk > 2048)
          break;
        ty = *(I64 *)(e + 16);
        if (ty & 0x100) {
          nm = *(I64 *)(e + 8);
          CompAdd(nm, pfx, plen);
        }
        e = *(I64 *)e;
      }
      if (nwalk > 2048)
        break;
    }
  }
  // Host define_table when published (legacy / future slots).
  body = SymDefineHashBody();
  mask = SymDefineHashMask();
  if (body && mask >= 0) {
    // Cap: empty-bucket scan must not hang if the slot is stale/corrupt.
    if (mask > 2047)
      mask = 2047;
    nwalk = 0;
    for (b = 0; b <= mask && CompN < COMP_MAX; b++) {
      nwalk++;
      if (nwalk > 4096)
        break;
      e = *(I64 *)(body + b * 8);
      while (e && CompN < COMP_MAX) {
        nwalk++;
        if (nwalk > 4096)
          break;
        ty = *(I64 *)(e + 16);
        if (ty & 0x040) {
          nm = *(I64 *)(e + 8);
          CompAdd(nm, pfx, plen);
        }
        e = *(I64 *)e;
      }
      if (nwalk > 4096)
        break;
    }
  }
  CompCollectDefines(pfx, plen);
  // JIT / Fun* table (repl-holyc man_sym) when host hash is empty.
  nfun = FunCount();
  for (i = 0; i < nfun && CompN < COMP_MAX; i++) {
    nm = FunName(i);
    if (nm)
      CompAdd(nm, pfx, plen);
  }
  return CompN;
}

I64 CompCollectFiles(U8 *pfx, I64 plen)
{
  I64 i, cl, k;
  U8 *cwd, *nm, *rest, *b;
  CompN = 0;
  cwd = FsCwd();
  if (!cwd)
    return 0;
  cl = 0;
  while (cl < 63 && cwd[cl])
    cl++;
  for (i = 0; i < MEMFS_MAX && CompN < COMP_MAX; i++) {
    if (!FsSlotUsed(i))
      continue;
    nm = FsName(i);
    if (!nm)
      continue;
    k = 0;
    while (k < cl && nm[k] == cwd[k])
      k++;
    if (k != cl)
      continue;
    rest = nm + cl;
    if (rest[0] == '.')
      continue;
    CompAdd(rest, pfx, plen);
    b = FsBaseName(rest);
    if (b != rest)
      CompAdd(b, pfx, plen);
    if (cl)
      CompAdd(nm, pfx, plen);
  }
  return CompN;
}

I64 CompCollectAsm(I64 kind, U8 *pfx, I64 plen)
{
  U8 *p, *s;
  U8 tmp[COMP_NAME];
  I64 n, i;
  CompN = 0;
  if (kind == ASM_COMP_NONE)
    return 0;
  if (kind == ASM_COMP_OP)
    p = AsmCompOps;
  else if (kind == ASM_COMP_CSR)
    p = AsmCompCsrs;
  else
    p = AsmCompRegs;
  if (!p)
    return 0;
  while (*p) {
    s = p;
    while (*p && *p != '|')
      p++;
    n = p - s;
    if (n > 0 && n < COMP_NAME) {
      i = 0;
      while (i < n) {
        tmp[i] = s[i];
        i++;
      }
      tmp[n] = 0;
      CompAdd(tmp, pfx, plen);
    }
    if (*p == '|')
      p++;
  }
  return CompN;
}

I64 CompApply(U8 *line, I64 max, I64 list_ok)
{
  I64 end, start, pathish, nm, fill, old, delta, i, need, in_asm, akind;
  U8 *best;
  end = CompCx;
  start = end;
  pathish = 0;
  if (end > 0 && (line[end - 1] == '"' || line[end - 1] == '\''))
    return 1;
  while (start > 0 && CompIsPath(line[start - 1]))
    start--;
  if (start == end)
    return 0;
  for (i = start; i < end; i++)
    if (line[i] == '.' || line[i] == '/')
      pathish = 1;
  if (start > 0 && line[start - 1] == '"')
    pathish = 1;
  old = end - start;
  if (old >= 127)
    return 1;
  for (i = 0; i < old; i++)
    CompPfx[i] = line[start + i];
  CompPfx[i] = 0;
  // CompAsmMode=0 → re-detect from line[0..CompCx); ignore stale depth.
  if (CompAsmMode == 0) {
    CompAsmReset();
    CompAsmFeed(line, CompCx);
    in_asm = CompAsmInside();
  } else
    in_asm = CompAsmInside();
  if (in_asm && !pathish) {
    akind = CompAsmKind(line, CompCx);
    nm = CompCollectAsm(akind, CompPfx, old);
    if (!nm)
      return 1;
  } else if (pathish)
    nm = CompCollectFiles(CompPfx, old);
  else {
    nm = CompCollectSyms(CompPfx, old);
    if (!nm)
      nm = CompCollectFiles(CompPfx, old);
  }
  if (!nm)
    return 1;
  best = &CompNames[0][0];
  if (nm == 1) {
    fill = 0;
    while (best[fill])
      fill++;
  } else
    fill = CompCommonPfx(nm);
  delta = fill - old;
  if (CompCx - old + fill >= max)
    return 1;
  need = 0;
  if (delta)
    need = 1;
  else {
    for (i = 0; i < fill; i++)
      if (line[start + i] != best[i])
        need = 1;
  }
  if (need) {
    if (delta > 0) {
      i = 0;
      while (line[end + i] && end + i < max - 1)
        i++;
      while (i >= 0) {
        if (end + delta + i < max)
          line[end + delta + i] = line[end + i];
        i--;
      }
    } else if (delta < 0) {
      i = 0;
      while (1) {
        line[end + delta + i] = line[end + i];
        if (!line[end + i])
          break;
        i++;
      }
    }
    for (i = 0; i < fill; i++)
      line[start + i] = best[i];
    CompCx = start + fill;
  }
  if (list_ok && nm > 1 && fill <= old) {
    PutCh('\n');
    for (i = 0; i < nm; i++) {
      U8 *tpl;
      UartStr("  ");
      UartStr(&CompNames[i][0]);
      if (in_asm && akind == ASM_COMP_OP) {
        tpl = AsmDocTemplate(&CompNames[i][0]);
        if (tpl && *tpl) {
          UartStr("  — ");
          UartStr(tpl);
        }
      }
      PutCh('\n');
    }
  } else if (need && in_asm && akind == ASM_COMP_OP && nm == 1) {
    U8 *tpl = AsmDocTemplate(best);
    if (tpl && *tpl) {
      PutCh('\n');
      UartStr("  → ");
      UartStr(tpl);
      PutCh('\n');
    }
  }
  return 1;
}

I64 CompTab(U8 *line, I64 max, I64 list_ok)
{
  return CompApply(line, max, list_ok);
}
// Probe: CompTab mid-line (CompCx ≠ EOL) fills token and preserves suffix.
U0 CompMidDemo()
{
  U8 line[32];
  U8 *s;
  I64 i;
  s = "x=MEM_PL;";
  i = 0;
  while (s[i] && i < 31) {
    line[i] = s[i];
    i++;
  }
  line[i] = 0;
  CompAsmMode = 0;
  CompAsmReset();
  // Cursor after 'L' (index of ';') so token is MEM_PL.
  CompCx = 8;
  CompTab(line, 32, 0);
  UartStr(line);
  PutCh('\n');
}
// Probe: the asm{} tables are live. AsmCompOps / AsmCompRegs / AsmCompCsrs and AsmDocRaw
// are file-scope stores, not baked data, and both CompCollectAsm and AsmDocTemplate answer
// 0 silently when they are NULL — so an image that lost them looks like "Tab offers
// nothing", which no count alone would catch.
U0 CompAsmDemo()
{
  U8 *tpl;
  "asm_tab_ops=%d\n", CompCollectAsm(ASM_COMP_OP, "csrr", 4);
  "asm_tab_regs=%d\n", CompCollectAsm(ASM_COMP_REG, "a", 1);
  "asm_tab_csrs=%d\n", CompCollectAsm(ASM_COMP_CSR, "mca", 3);
  tpl = AsmDocTemplate("slli");
  if (!tpl || !*tpl) {
    UartStr("asm_tab_tpl=(none)\n");
    return;
  }
  "asm_tab_tpl=%s\n", tpl;
}
