// ds.hc -- datasheet-driven bitfield decoder for the UART REPL.
// Boot after csr.hc. Sheets in datasheet/ds_*.hc call DsBegin/DsField/DsEnd.
// Man("Datasheet");  docs/DATASHEET.md
#define DS_KIND_NONE 0
#define DS_KIND_CSR 1
#define DS_KIND_MMIO 2
#define DS_MAX_REGS 48
#define DS_MAX_FIELDS 32
#define DS_ENUM_BUF 48
class CDsField
{
  U8 *name;
  I64 lo;
  I64 hi;
  U8 *enums;
  U8 *note;
};

class CDsReg
{
  U8 *id;
  U8 *device;
  I64 kind;
  I64 addr;
  I64 width;
  I64 n_fields;
  CDsField fields[DS_MAX_FIELDS];
};
CDsReg g_ds_regs[DS_MAX_REGS];
I64 g_ds_n = 0;
I64 g_ds_cur = -1;
U8 g_ds_enum_buf[DS_ENUM_BUF];
I64 DsBitMask(I64 nbits)
{
  if (nbits <= 0)
    return 0;
  if (nbits >= 64)
    return -1;
  return (1 << nbits) - 1;
}

I64 DsExtract(I64 val, I64 lo, I64 hi)
{
  I64 w;
  if (hi < lo) {
    w = lo;
    lo = hi;
    hi = w;
  }
  w = hi - lo + 1;
  return (val >> lo) & DsBitMask(w);
}

U8 *DsEnumLookup(U8 *enums, I64 v)
{
  U8 *p;
  I64 n, i, neg;
  if (!enums || !*enums)
    return 0;
  p = enums;
  while (*p) {
    while (*p == ' ' || *p == ',')
      p++;
    if (!*p)
      break;
    neg = 0;
    if (*p == '-') {
      neg = 1;
      p++;
    }
    n = 0;
    while (*p >= '0' && *p <= '9') {
      n = n * 10 + (*p - '0');
      p++;
    }
    if (neg)
      n = -n;
    if (*p != '=')
      break;
    p++;
    i = 0;
    while (*p && *p != ',' && i < DS_ENUM_BUF - 1) {
      g_ds_enum_buf[i] = *p;
      i++;
      p++;
    }
    g_ds_enum_buf[i] = 0;
    if (n == v)
      return g_ds_enum_buf;
    if (*p == ',')
      p++;
  }
  return 0;
}

CDsReg *DsLookup(U8 *id)
{
  I64 i;
  if (!id)
    return 0;
  for (i = 0; i < g_ds_n; i++) {
    if (!StrICmp(g_ds_regs[i].id, id))
      return &g_ds_regs[i];
  }
  return 0;
}

I64 DsPeek(CDsReg *r)
{
  if (!r)
    return 0;
  if (r->kind == DS_KIND_CSR)
    return CSRGet(r->addr);
  if (r->kind == DS_KIND_MMIO) {
    if (!r->addr)
      return 0;
    if (r->width == 1)
      return *(U8 *)r->addr;
    if (r->width == 4)
      return *(U32 *)r->addr;
    return *(I64 *)r->addr;
  }
  return 0;
}

U0 DsBegin(U8 *id, U8 *device, I64 kind, I64 addr, I64 width)
{
  CDsReg *r;
  I64 i;
  r = 0;
  for (i = 0; i < g_ds_n; i++) {
    if (!StrICmp(g_ds_regs[i].id, id)) {
      r = &g_ds_regs[i];
      g_ds_cur = i;
      break;
    }
  }
  if (!r) {
    if (g_ds_n >= DS_MAX_REGS) {
      UartStr("DsBegin: registry full\n");
      g_ds_cur = -1;
      return;
    }
    r = &g_ds_regs[g_ds_n];
    g_ds_cur = g_ds_n;
    g_ds_n++;
  }
  r->id = id;
  r->device = device;
  r->kind = kind;
  r->addr = addr;
  r->width = width;
  r->n_fields = 0;
}

U0 DsField(U8 *name, I64 lo, I64 hi, U8 *enums = 0, U8 *note = 0)
{
  CDsReg *r;
  CDsField *f;
  if (g_ds_cur < 0 || g_ds_cur >= g_ds_n)
    return;
  r = &g_ds_regs[g_ds_cur];
  if (r->n_fields >= DS_MAX_FIELDS)
    return;
  f = &r->fields[r->n_fields];
  f->name = name;
  f->lo = lo;
  f->hi = hi;
  f->enums = enums;
  f->note = note;
  r->n_fields++;
}

U0 DsEnd()
{
  g_ds_cur = -1;
}

U0 DsPrintFieldLegend(CDsField *f)
{
  if (!f || !f->name)
    return;
  if (f->lo == f->hi)
    "  [%d] %s", f->lo, f->name;
  else
    "  [%d:%d] %s", f->hi, f->lo, f->name;
  if (f->enums && *f->enums)
    "  {%s}", f->enums;
  if (f->note && *f->note)
    "  %s", f->note;
  UartStr("\n");
}

U0 DsPrintFieldVal(CDsField *f, I64 val)
{
  I64 bits, w;
  U8 *sym;
  if (!f || !f->name)
    return;
  bits = DsExtract(val, f->lo, f->hi);
  w = f->hi - f->lo + 1;
  if (w < 1)
    w = 1;
  if (f->lo == f->hi)
    "  [%d] %s = %d", f->lo, f->name, bits;
  else
    "  [%d:%d] %s = 0x%X (%d)", f->hi, f->lo, f->name, bits, bits;
  sym = DsEnumLookup(f->enums, bits);
  if (sym)
    "  %s", sym;
  else if (f->note && *f->note && w == 1 && bits)
    "  %s", f->note;
  else if (f->note && *f->note && w > 1)
    "  %s", f->note;
  UartStr("\n");
}
// DsShow -- DsShow("mstatus")
// NAME
//   DsShow - print datasheet field legend for a register (no value)
// SYNOPSIS
//   U0 DsShow(U8 *id);
// DESCRIPTION
//   Lists bit ranges, enum maps, and notes from the OS-owned datasheet
//   table for id (e.g. "mstatus", "uart.lsr", "mie"). See Man("Datasheet").
// EXAMPLES
//   DsShow("mstatus");
//   DsShow("uart.lsr");
// SEE ALSO
//   DsDecode  DsFind  Bits  Reg  Man
// BUGS
//   Unknown id prints a hint; sheets load at boot from ds_*.hc.
U0 DsShow(U8 *id)
{
  CDsReg *r;
  I64 i;
  r = DsLookup(id);
  if (!r) {
    UartStr("DsShow: unknown — try DsFind(\"\"); Man(\"Datasheet\");\n");
    return;
  }
  "DsShow %s  device=%s", r->id, r->device;
  if (r->kind == DS_KIND_CSR)
    "  CSR=0x%X", r->addr;
  else if (r->kind == DS_KIND_MMIO)
    "  MMIO=0x%X width=%d", r->addr, r->width;
  UartStr("\n");
  for (i = 0; i < r->n_fields; i++)
    DsPrintFieldLegend(&r->fields[i]);
}

U0 DsDecodeBody(CDsReg *r, I64 val, I64 live)
{
  I64 i;
  if (!r)
    return;
  "DsDecode %s", r->id;
  if (live)
    UartStr(" (live)");
  "  = 0x%X  (%d)\n", val, val;
  if (r->kind == DS_KIND_CSR)
    "  CSR 0x%X via CSRGet\n", r->addr;
  else if (r->kind == DS_KIND_MMIO)
    "  MMIO 0x%X\n", r->addr;
  for (i = 0; i < r->n_fields; i++)
    DsPrintFieldVal(&r->fields[i], val);
}
// DsDecode -- DsDecode("mstatus") / DsDecode("uart.lsr", 0x21)
// NAME
//   DsDecode - decode a register value into named bitfields
// SYNOPSIS
//   I64 DsDecode(U8 *id, ...);
// DESCRIPTION
//   Looks up id in the datasheet registry. With no extra args, peeks live
//   (CSRGet or MMIO). With one I64 arg, decodes that value. Prints hex,
//   decimal, and each field with symbolic enum text when defined.
//   Alias: Bits("mstatus");
// EXAMPLES
//   DsDecode("mstatus");
//   DsDecode("uart.lsr", 0x21);
//   Bits("mie");
// SEE ALSO
//   DsShow  DsFind  DsFieldGet  Reg  CSRGet  Man
// BUGS
//   Live peek only for sheets with kind CSR/MMIO and a known addr.
I64 DsDecode(U8 *id,...)
{
  CDsReg *r;
  I64 val, live;
  r = DsLookup(id);
  if (!r) {
    UartStr("DsDecode: unknown — try DsFind(\"\"); Man(\"Datasheet\");\n");
    return -1;
  }
  live = 1;
  val = 0;
  if (argc >= 1) {
    val = argv[0];
    live = 0;
  } else {
    val = DsPeek(r);
  }
  DsDecodeBody(r, val, live);
  return val;
}
// Bits -- Bits("mstatus")
// NAME
//   Bits - alias for DsDecode (datasheet bitfield dig-down)
// SYNOPSIS
//   I64 Bits(U8 *id, ...);
// DESCRIPTION
//   Same as DsDecode. Sibling to Reg("mstatus") for symbolic bitfields.
// EXAMPLES
//   Bits("mstatus");
//   Bits("uart.lsr", UART_LSR_THRE|UART_LSR_DR);
// SEE ALSO
//   DsDecode  Reg  RegHelp
I64 Bits(U8 *id,...)
{
  if (argc >= 1)
    return DsDecode(id, argv[0]);
  return DsDecode(id);
}
// DsFieldGet -- DsFieldGet("uart.lsr","THRE",0x21)
// NAME
//   DsFieldGet - extract one named field from a value
// SYNOPSIS
//   I64 DsFieldGet(U8 *id, U8 *field, I64 val);
// DESCRIPTION
//   Returns the bitfield named field from val using the datasheet for id.
// EXAMPLES
//   DsFieldGet("uart.lsr", "THRE", 0x21);  // → 1
//   DsFieldGet("mstatus", "MIE", GetMStatus());
// SEE ALSO
//   DsDecode  DsShow
I64 DsFieldGet(U8 *id, U8 *field, I64 val)
{
  CDsReg *r;
  I64 i;
  r = DsLookup(id);
  if (!r || !field)
    return -1;
  for (i = 0; i < r->n_fields; i++) {
    if (!StrICmp(r->fields[i].name, field))
      return DsExtract(val, r->fields[i].lo, r->fields[i].hi);
  }
  return -1;
}
// DsFind -- DsFind("plic")
// NAME
//   DsFind - list datasheet registers matching a substring
// SYNOPSIS
//   I64 DsFind(U8 *needle);
// DESCRIPTION
//   Prints id / device / kind for each registered sheet whose id or device
//   contains needle (case-insensitive). Empty needle lists all.
// EXAMPLES
//   DsFind("uart");
//   DsFind("");
//   DsFind("csr");
// SEE ALSO
//   DsShow  DsDecode  Man
I64 DsFind(U8 *needle)
{
  I64 i, n, len;
  U8 *id, *dev;
  if (!needle)
    needle = "";
  len = StrLen(needle);
  n = 0;
  UartStr("DsFind — datasheet registers:\n");
  for (i = 0; i < g_ds_n; i++) {
    id = g_ds_regs[i].id;
    dev = g_ds_regs[i].device;
    if (len && !StrIMatch(needle, id, 0) && !(dev && StrIMatch(needle, dev, 0)))
      continue;
    "  %s  %s", id, dev;
    if (g_ds_regs[i].kind == DS_KIND_CSR)
      "  CSR 0x%X", g_ds_regs[i].addr;
    else if (g_ds_regs[i].kind == DS_KIND_MMIO)
      "  MMIO 0x%X", g_ds_regs[i].addr;
    else
      UartStr("  (legend)");
    UartStr("\n");
    n++;
  }
  "  (%d match)\n", n;
  return n;
}
// DsHelp -- DsHelp()
// NAME
//   DsHelp - short cheat sheet for datasheet decode
// SYNOPSIS
//   U0 DsHelp();
// DESCRIPTION
//   Entry points for DsFind / DsShow / DsDecode / Bits.
// EXAMPLES
//   DsHelp;
// SEE ALSO
//   Man  RegHelp
U0 DsHelp()
{
  UartStr("DsHelp — datasheet bitfields (Man(\"Datasheet\"))\n");
  UartStr("  DsFind(\"uart\");  DsShow(\"mstatus\");\n");
  UartStr("  DsDecode(\"mstatus\");  Bits(\"mie\");\n");
  UartStr("  DsDecode(\"uart.lsr\", 0x21);  DsFieldGet(\"uart.lsr\",\"THRE\",0x21);\n");
  UartStr("  Sheets: Run(\"ds_csr.hc\"); after edit. Live: CSRGet / MMIO peek.\n");
}
