// RVDbgView.HC — Dbg: the debugger view, as documents rendered to the terminal.
//
// Stock TempleOS (tos/Doc/DbgOverview.DD) has no modal debugger UI: you call Dbg(), you are at a
// prompt, and you inspect with ordinary functions — Dr, U, D/Dm, and registers as var-like
// labels. This file is that entry point for RISC-V: it paints what you always want to see after
// a fault (registers, and the fault itself decoded) and leaves you at the HolyC prompt, where
// _A0, U(_PC-16), AsmStep, Bp and the rest already work.
//
// Both panes are DolDoc documents rendered by Kernel/RVDocText.HC into rectangles the caller
// chooses — the window manager's whole remaining job. The renderer diffs, so re-entering Dbg
// after a step costs a few dozen bytes, not a repaint.
//
// Include after RVDocVT.HC, RVDocText.HC and RVRegPane.HC.
#ifndef RV_DBG_VIEW_HC
#define RV_DBG_VIEW_HC
#help_index "Dbg"

#define DBGV_SNAP 0x87000100
// legacy freeze slots: 18 mcause, 19 mepc, 20 mtval, 21 mstatus
#define DBGV_SNAP_X 0x87000400
// canonical x0..x31
#define DBGV_STATUS_ROW REGP_ROWS
// straight under the register pane

CDoc *dbgv_doc, *dbgv_dis, *dbgv_mem;
I64 dbgv_bytes, dbgv_dis_bytes, dbgv_mem_bytes, dbgv_in_trap, dbgv_primed;

// --- capturing the disassembler -------------------------------------------------------------
// DisasmOne PRINTS (a thousand lines of it); it has no buffer form. Rather than fork it, sit in
// the StdOut chain AHEAD of the console and swallow what it emits while a capture is armed.
// Off, the sink returns FALSE and output flows to the console as usual.
//
// Priority is LOWEST-FIRST: KeyDevAdd walks back from the tail while an entry's priority is
// GREATER than the new one, so the chain runs in ascending priority from head.next, and PutS
// stops at the first sink that returns TRUE. The console registers at CONFIG_UART_BASE
// (0x10000000, KBootRV.HC:82), so a capture sink must be BELOW that to see output first — a
// high number puts it behind the console, where it never runs.
#define DBGV_CAP_PRI 1
U8 *dbgv_cap;
I64 dbgv_cap_len, dbgv_cap_max, dbgv_cap_on;

U0 DbgVCapCh(I64 ch)
{
  if (!dbgv_cap || dbgv_cap_len + 1 >= dbgv_cap_max)
    return;
  dbgv_cap[dbgv_cap_len++] = ch;
}

Bool DbgVCapPutS(U8 *st)
{
  if (!dbgv_cap_on)
    return FALSE;
  while (st && *st) {
    DbgVCapCh(*st);
    st++;
  }
  return TRUE;
}

Bool DbgVCapPutKey(I64 ch, I64 sc)
{
  no_warn sc;
  if (!dbgv_cap_on)
    return FALSE;
  DbgVCapCh(ch);
  return TRUE;
}

// DbgViewInit -- DbgViewInit()
// NAME
//   DbgViewInit - register the capture sink Dbg uses to put disassembly in a document
// SEE ALSO
//   Dbg
public U0 DbgViewInit()
{
  KeyDevAdd(&DbgVCapPutKey, &DbgVCapPutS, DBGV_CAP_PRI, FALSE);
}

I64 DbgVCapture(I64 addr, I64 n, U8 *out, I64 max)
{
  dbgv_cap = out;
  dbgv_cap_len = 0;
  dbgv_cap_max = max;
  dbgv_cap_on = 1;
  U(addr, n);
  dbgv_cap_on = 0;
  out[dbgv_cap_len] = 0;
  return dbgv_cap_len;
}

// Append captured text as document source, escaping '$' ('$$' is DolDoc's literal '$') and
// breaking it into lines. Shared by the disassembly and memory tiles.
U0 DbgVPutEscaped(CDoc *doc, U8 *text)
{
  U8 line[160], *p;
  I64 i = 0;
  p = text;
  while (*p) {
    if (*p == '\n' || i >= 150) {
      line[i] = 0;
      if (i)
        DocPutS(doc, line);
      DocPutS(doc, "\n");
      i = 0;
      if (*p == '\n')
        p++;
      continue;
    }
    if (*p == '$' && i < 150)
      line[i++] = '$';
    line[i++] = *p;
    p++;
  }
  if (i) {
    line[i] = 0;
    DocPutS(doc, line);
    DocPutS(doc, "\n");
  }
}

// Disassembly around a PC, as a rendered document. Captures U()'s output, escapes '$' so
// DolDoc does not read the text as commands, and paints it under the status pane.
U0 DbgDisasmPane(I64 pc)
{
  U8 *cap;
  I64 n;
  if (!pc)
    return;
  if (!dbgv_dis) {
    dbgv_dis = DocNew();
    if (!dbgv_dis)
      return;
  }
  cap = MAlloc(4096);
  DbgVCapture(pc, 8, cap, 4096);
  DocClear(dbgv_dis);
  DocPutS(dbgv_dis, "$FG,5$disasm at _PC$FG$\n");
  DbgVPutEscaped(dbgv_dis, cap);
  Free(cap);
  n = DBGV_STATUS_ROW + 6;
  dbgv_dis_bytes = RVDocTextRender(dbgv_dis, n, 0, 10, 80);
}

// Dbg -- Dbg()
// NAME
//   Dbg - enter the debugger view: registers + the decoded fault, then back to the prompt
// SYNOPSIS
//   Dbg;
// DESCRIPTION
//   Paints the register pane and a status line (cause name, mepc, mtval, ra, sp, mstatus) from
//   the fault freeze, then returns. There is no modal loop and no separate command language:
//   you are at the HolyC prompt, so inspect with Dr, U(_PC-16), D/Dm, _A0, AsmStep, Bp — the
//   same functions that work anywhere else. That is how stock TempleOS debugs.
//   The REPL calls this for you when a line faults.
// EXAMPLES
//   Dbg;  U(_PC - 16);  _A0 = 5;  AsmStep("addi a0,a0,1");
// SEE ALSO
//   Dr  AsmStep  RegPaneUpdate  U  Uf  Bp  G
// BUGS
//   The disassembly tile captures U()'s printed output through a StdOut sink rather than a
//   buffer-returning disassembler; DisasmOne has no buffer form. DbgViewInit must have run.
public U0 Dbg()
{
  U8 line[192];
  I64 cause;
  RegPaneUpdate;
  if (!dbgv_doc) {
    dbgv_doc = DocNew();
    if (!dbgv_doc)
      return;
  }
  cause = *(I64 *)(DBGV_SNAP + 18 * 8);
  DocClear(dbgv_doc);
  StrPrint(line, "$FG,4$%s$FG$\n", RVWinMcauseName(cause));
  DocPutS(dbgv_doc, line);
  StrPrint(line, "mepc=%016X  mtval=%016X\n", *(I64 *)(DBGV_SNAP + 19 * 8),
           *(I64 *)(DBGV_SNAP + 20 * 8));
  DocPutS(dbgv_doc, line);
  StrPrint(line, "ra  =%016X  sp   =%016X\n", *(I64 *)(DBGV_SNAP_X + 1 * 8),
           *(I64 *)(DBGV_SNAP_X + 2 * 8));
  DocPutS(dbgv_doc, line);
  StrPrint(line, "mstatus=%016X\n", *(I64 *)(DBGV_SNAP + 21 * 8));
  DocPutS(dbgv_doc, line);
  DocPutS(dbgv_doc, "$FG,7$Dr  U(_PC-16)  _A0  AsmStep(\"...\")  Bp(addr)$FG$\n");
  dbgv_bytes = RVDocTextRender(dbgv_doc, DBGV_STATUS_ROW, 0, 6, 80);
  DbgDisasmPane(*(I64 *)(DBGV_SNAP + 19 * 8));
}

// Memory as a document, using the same StdOut capture as the disassembly tile.
U0 DbgMemPane(I64 addr, I64 n)
{
  U8 *cap;
  I64 got;
  if (!addr)
    return;
  if (!dbgv_mem) {
    dbgv_mem = DocNew();
    if (!dbgv_mem)
      return;
  }
  cap = MAlloc(4096);
  dbgv_cap = cap;
  dbgv_cap_len = 0;
  dbgv_cap_max = 4096;
  dbgv_cap_on = 1;
  RVWinSerialMd(addr, n);
  dbgv_cap_on = 0;
  cap[dbgv_cap_len] = 0;
  DocClear(dbgv_mem);
  DocPutS(dbgv_mem, "$FG,5$memory$FG$\n");
  DbgVPutEscaped(dbgv_mem, cap);
  Free(cap);
  dbgv_mem_bytes = RVDocTextRender(dbgv_mem, DBGV_STATUS_ROW + 6, 40, 10, 40);
}

// D -- D(addr, n)
// NAME
//   D - hex dump numbered from zero (stock TempleOS name)
// SYNOPSIS
//   D(addr, n = 64);
// DESCRIPTION
//   Stock D() numbers from zero rather than showing absolute addresses — it is for looking at a
//   structure's layout, where the offset is what you want. Dm() is the same bytes with their
//   real addresses. Built directly rather than captured: the offset column is the whole point,
//   and RVWinSerialMd prints absolute addresses.
// SEE ALSO
//   Dm  Da  Dr  Dbg
public U0 DbgD(I64 addr, I64 n = 64)
{
  U8 line[160], cell[8];
  I64 i, b;
  if (!addr || n <= 0)
    return;
  if (n > 0x400)
    n = 0x400;
  if (!dbgv_mem) {
    dbgv_mem = DocNew();
    if (!dbgv_mem)
      return;
  }
  DocClear(dbgv_mem);
  DocPutS(dbgv_mem, "$FG,5$D (offsets from 0)$FG$\n");
  i = 0;
  while (i < n) {
    StrPrint(line, "%04X ", i);
    b = 0;
    while (b < 16 && i + b < n) {
      StrPrint(cell, "%02X ", *(U8 *)(addr + i + b));
      StrCat(line, cell);
      b++;
    }
    DocPutS(dbgv_mem, line);
    DocPutS(dbgv_mem, "\n");
    i += 16;
  }
  dbgv_mem_bytes = RVDocTextRender(dbgv_mem, DBGV_STATUS_ROW + 6, 40, 10, 40);
}

// Da -- Da(addr, n)
// NAME
//   Da - one-column address dump with symbol names (stock TempleOS name)
// SYNOPSIS
//   Da(addr, n = 16);
// DESCRIPTION
//   Reads n I64s and names any that look like code, which is what makes a stack readable: this
//   is the tool for "whose return addresses are on my stack". Symbols come from
//   RVWinSerialSymName, the same source the backtrace uses.
// EXAMPLES
//   Da(_SP, 16);   // the stack under the fault
// SEE ALSO
//   D  Dm  Dbg  Dr
public U0 DbgDa(I64 addr, I64 n = 16)
{
  U8 line[192], *sym;
  I64 i, v;
  if (!addr || n <= 0)
    return;
  if (n > 128)
    n = 128;
  if (!dbgv_mem) {
    dbgv_mem = DocNew();
    if (!dbgv_mem)
      return;
  }
  DocClear(dbgv_mem);
  DocPutS(dbgv_mem, "$FG,5$Da (addresses)$FG$\n");
  i = 0;
  while (i < n) {
    v = *(I64 *)(addr + i * 8);
    sym = RVWinSerialSymName(v);
    if (sym)
      StrPrint(line, "%016X %016X $FG,2$%s$FG$", addr + i * 8, v, sym);
    else
      StrPrint(line, "%016X %016X", addr + i * 8, v);
    DocPutS(dbgv_mem, line);
    DocPutS(dbgv_mem, "\n");
    i++;
  }
  dbgv_mem_bytes = RVDocTextRender(dbgv_mem, DBGV_STATUS_ROW + 6, 40, 10, 40);
}

// Dm -- Dm(addr, n)
// NAME
//   Dm - dump memory into the debugger's memory tile (stock TempleOS name)
// SYNOPSIS
//   Dm(addr, n = 64);
// SEE ALSO
//   Dbg  Dr  U
public U0 DbgDm(I64 addr, I64 n = 64)
{
  DbgMemPane(addr, n);
}

// DbgViewPrime -- DbgViewPrime()
// NAME
//   DbgViewPrime - create the view's documents up front
// DESCRIPTION
//   The panes allocate on first use. Inside a trap that is exactly the wrong time — a fault in
//   the allocator would fault again — so the images that install the trap hook prime the docs
//   while everything is still healthy.
// SEE ALSO
//   DbgTrapHook
public U0 DbgViewPrime()
{
  if (!dbgv_doc)
    dbgv_doc = DocNew();
  if (!dbgv_dis)
    dbgv_dis = DocNew();
  if (!dbgv_mem)
    dbgv_mem = DocNew();
  dbgv_primed = 1;
}

// Cls -- Cls()
// NAME
//   Cls - clear the terminal (stock TempleOS name)
// SYNOPSIS
//   Cls;
// DESCRIPTION
//   Clears the screen AND forgets what the renderer thinks is on it. Both halves matter: panes
//   only send cells that differ from their shadow, so clearing the terminal without
//   invalidating would leave the next repaint convinced the old contents are still there and
//   paint nothing.
// SEE ALSO
//   Dbg  G  RVDocTextInvalidate
public U0 Cls()
{
  RVVtClear;
  RVVtFlush;
  // RVVtClear only buffers; the pane paths flush at the end of a render, so a bare clear would
  // otherwise sit in the buffer and never reach the terminal.
  RVDocTextInvalidate;
}

// DbgTrapHook -- installed with RVSetDbgHook(&DbgTrapHook)
// NAME
//   DbgTrapHook - the debugger, running inside the trap, so G can actually continue
// DESCRIPTION
//   The runtime calls this on a synchronous exception once the freeze is published. It paints
//   the view and then takes single keys from the POLLED uart (interrupts are off in a trap, so
//   the IRQ ring never fills):
//     g  continue past the faulting instruction
//     p  continue at _PC (edit it first, or a register, and the copy-back applies it)
//     r  repaint
//     q  give up and let the REPL's recovery return you to the prompt
//   Returns the resume address, or 0 to fall through to the old behaviour. Refuses to re-enter:
//   a fault inside the debugger must not recurse.
// SEE ALSO
//   Dbg  G  DbgViewPrime
I64 DbgTrapHook(I64 cause, I64 epc, I64 tval)
{
  I64 ch;
  no_warn cause;
  no_warn tval;
  if (dbgv_in_trap || !dbgv_primed)
    return 0;
  dbgv_in_trap = 1;
  Dbg;
  "\n[dbg] g=go p=go@_PC r=repaint q=prompt\n";
  while (TRUE) {
    ch = RVUartGetC();
    if (ch == 'g') {
      dbgv_in_trap = 0;
      Cls;
      return epc + 4;
    }
    if (ch == 'p') {
      dbgv_in_trap = 0;
      Cls;
      return *(I64 *)(DBGV_SNAP + 19 * 8);
    }
    if (ch == 'r')
      Dbg;
    if (ch == 'q')
      break;
  }
  dbgv_in_trap = 0;
  Cls;
  // leaving the debugger hands back a clean terminal, however you leave it
  return 0;
}

// G -- G()
// NAME
//   G - continue (stock TempleOS name)
// SYNOPSIS
//   G;
// DESCRIPTION
//   Registers edited while stopped are already applied on resume by the trap path's copy-back
//   (TrapSnapApply / HolyTrapSnapApply), so after a fault that the REPL recovered from there is
//   nothing left to resume — the line was abandoned and you are back at the prompt. G exists so
//   the stock name means something: it leaves the debugger and clears the view. Inside a trap,
//   `g` continues the stopped context; a line the REPL already recovered has nothing to resume.
// SEE ALSO
//   Dbg  Dr  AsmStep
public U0 G()
{
  Cls;
  dbgv_bytes = 0;
}

I64 DbgViewCost()
{
  return dbgv_bytes;
}

I64 DbgDisasmCost()
{
  return dbgv_dis_bytes;
}

#endif
