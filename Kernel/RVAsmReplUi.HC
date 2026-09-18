// RVAsmReplUi.HC — AsmRepl: type instructions, watch the machine.
//
// AsmStep already runs one instruction against the debugger's register file and prints what
// moved. This is the loop around it: its own prompt with history and Tab completion, the
// register pane above, and memory beside it, both repainted after every step. The panes are
// documents rendered by Kernel/RVDocText.HC, so a step costs a few dozen bytes on the wire.
//
// Commands (anything else is assembled and stepped):
//   q            leave
//   d <addr>     point the memory pane somewhere (default: sp)
//   r            repaint
//   ?            the key list
//
// Include after RVDocVT.HC, RVDocText.HC, RVRegPane.HC, RVDbgView.HC and RVLineEd.HC.
#ifndef RV_ASM_REPL_UI_HC
#define RV_ASM_REPL_UI_HC
#help_index "Dbg"

#define ASMUI_CTX 0x87000400
// the register file: x0..x31, shared with the debugger and the _Xn labels
#define ASMUI_SIDE_COLS 44
// two 64-bit registers to a row, side by side: 2 x 22
#define ASMUI_MIN_TEXT 50
// The text column has to stay usable. A sidebar costs 44 columns, so an 80-column terminal
// would leave 35 — narrow enough that a register diff line ("a0   0000... -> 0000...", 43
// characters) wraps. Below this the panes stack across the top instead, where they get the full
// width and the prompt gets a scroll region. A sidebar therefore wants ~94 columns or more.

// The values live in a column on the right and the REPL has the left: registers at the top,
// the machine state under them, memory under that.
//
// A terminal cannot pin a column — DECSTBM scrolls whole rows — so the sidebar is not pinned,
// it is REPAINTED: printed output is kept inside the text column (RVDolAnsiWrap, RVLineEdWrap)
// so it can never be written over the panes, and the panes are put back at every prompt, which
// is the moment the screen is quiet again. What changed is latched at the step (RegPaneMark),
// so a register that moved is still red however many times the pane is repainted afterwards.
//
// On a terminal too narrow to split, the same panes stack across the top with the prompt in a
// scroll region below them. Which one is in force is decided from the size the terminal
// reported (RVVtProbeSize), not assumed.
I64 asmui_mem_addr, asmui_running, asmui_step_fn, asmui_mode;
I64 asmui_side, asmui_side_col, asmui_text_cols, asmui_mem_row, asmui_mem_rows, asmui_ready;
I64 asmui_dis_addr, asmui_trace_pc, asmui_tracing;
#define ASMUI_DIS_LINES 12
// how many instructions `u` shows at a time — a screenful of the text column, not a flood

// AsmReplInstallStep -- AsmReplInstallStep(&AsmStep)
// NAME
//   AsmReplInstallStep - give the loop its stepper
// DESCRIPTION
//   AsmStep lives in the compiler image (Compiler/RVAsmRepl.HC) and this loop lives in the
//   kernel image, which is linked first — so the call goes through a pointer, the same way the
//   register pane is handed to AsmStep. Without one, AsmRepl says so instead of stepping.
// SEE ALSO
//   AsmRepl  AsmStep
public U0 AsmReplInstallStep(I64 fn)
{
  asmui_step_fn = fn;
}

// Tab's vocabulary: the register names, which are not in any catalog, and then the documented
// mnemonics themselves (AsmComplete over the same 244 entries AsmList prints and AsmDoc
// explains). A hand-written word list used to sit here and had already drifted from what the
// assembler takes — completing a mnemonic the catalog does not document, and not completing
// most of the ones it does.
U8 *AsmUiWords()
{
  return "zero ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 "
         "s11 t3 t4 t5 t6";
}

// One completion, and only when it is unambiguous: a stepper that guesses wrong wastes a step.
I64 AsmUiComplete(U8 *word, U8 *out, I64 max)
{
  U8 *p, cand[32];
  I64 i, n, hits = 0;
  if (!word || !*word)
    return FALSE;
  n = StrLen(word);
  p = AsmUiWords();
  while (*p) {
    i = 0;
    while (*p && *p != ' ' && i < 30)
      cand[i++] = *p++;
    cand[i] = 0;
    while (*p == ' ')
      p++;
    if (i >= n && !MemCmp(cand, word, n)) {
      hits++;
      if (hits == 1 && i < max - 1)
        StrCpy(out, cand);
    }
  }
  if (hits == 1)
    return 1;
  if (hits > 1)
    return 0;
  if (rv_led_line && rv_led_line[0] == '?')
    return AsmComplete(word, out, max);
  // `? fcv` is asking about a mnemonic, so complete from the catalog and nothing else — a
  // register name is not something AsmDoc can explain. A bare `?` lists what there is.
  i = AsmComplete(word, out, max);
  if (i)
    return i;
  // not a register or a documented mnemonic: fall through to everything else the REPL knows, so
  // Dr, _A0, AsmStep and anything you just defined complete here too
  return RVHashComplete(word, out, max);
}

// The scroll region keeps the prompt's scrolling away from the pane rows, so the renderer's
// shadow stays true and a step only sends the cells that changed. Nothing to do here now — kept
// as the one place that would need to invalidate if the layout ever lets text touch the panes.
U0 AsmUiScrolled()
{
}

// How many rows the register pane gets, and whether the float block is one of the things in it.
//
// Three values per row of screen is the whole problem: 32 registers, pc, 4 CSRs and 32 float
// registers want about 40 rows at two to a row, which is a whole terminal. So they are ranked.
// The registers and machine state always fit. The float block is next — if showing it leaves no
// room for memory, memory goes, because someone who asked for float registers asked for them.
// If it does not fit even then, it is turned OFF rather than cut in half: a pane that silently
// stops half way through is how ten registers went missing.
#define ASMUI_MEM_MIN 3
I64 AsmUiRegRows(I64 avail)
{
  I64 want, i = 0;
  // Ranked, most wanted first, and the first that fits wins.
  //
  // MEMORY OUTRANKS THE FLOAT BLOCK. Both were asked for and they do not fit together on a
  // 40-row terminal: registers, pc and the machine state are 23 rows, the 32 float registers
  // another 17, and memory needs at least 3 more. Memory wins by default because a stepper
  // without a memory view is half a debugger, and because the float block is one keystroke away
  // (`f`) while a pane that silently vanished is not. The heading says which one is hidden.
  //
  // When it is forced on, the float block takes memory's rows rather than being cut in half.
  while (i < 4) {
    RegPaneFp(regp_fp_want && i < 2);
    RegPaneCsrs(8);
    if (i & 1)
      RegPaneCsrs(4);
    want = RegPaneRowsNeeded;
    if (want <= avail - ASMUI_MEM_MIN)
      return want;
    // ...and memory under it
    if (regp_fp_want && want <= avail)
      return want;
    // ...instead of memory, but only because the floats were asked for
    i++;
  }
  // Nothing fits whole: the smallest set, clipped. A pane that stops half way through a block
  // is the failure this ranking exists to avoid, so this is the last resort.
  RegPaneFp(FALSE);
  RegPaneCsrs(4);
  want = RegPaneRowsNeeded;
  if (want > avail)
    want = avail;
  return want;
}

// The memory pane, under the registers in whichever layout is in force. Not every layout has
// room for one — the float block takes its rows on a short screen.
U0 AsmUiPanes()
{
  I64 addr;
  if (!asmui_ready || asmui_mem_rows < 2)
    return;
  addr = asmui_mem_addr;
  if (!addr)
    addr = *(I64 *)(ASMUI_CTX + 2 * 8);
  // sp by default — the stack is what you want beside a stepper. But this context's sp is only
  // set once something writes it, and a pane that shows nothing teaches nothing, so fall back
  // to the register file itself: `d <addr>` is then an obvious next move.
  if (!addr)
    addr = ASMUI_CTX;
  DbgMemAt(addr, asmui_mem_row, asmui_side ? asmui_side_col : 0, asmui_mem_rows,
           asmui_side ? ASMUI_SIDE_COLS : asmui_text_cols);
}

// One instruction at `pc`, as text, with the address prefix stripped — "0x8001F5A4:  ld t1,
// 0x0(sp)" becomes "ld t1, 0x0(sp)", which is exactly what the assembler takes back. The round
// trip is deliberate: what gets stepped is what the disassembler said, so a lie in either one
// shows up as an assembly error rather than as a wrong answer.
I64 AsmUiInsnText(I64 pc, U8 *out, I64 max)
{
  U8 *cap, *p;
  I64 n = 0;
  cap = MAlloc(512);
  if (!cap)
    return FALSE;
  DbgVCapture(pc, 1, cap, 512);
  p = cap;
  while (*p && *p != ':')
    p++;
  if (*p == ':')
    p++;
  while (*p == ' ' || *p == '\t')
    p++;
  while (*p && *p != '\n' && n < max - 1)
    out[n++] = *p++;
  out[n] = 0;
  Free(cap);
  return n > 0;
}

// Does this instruction move the pc itself? Those cannot be handed to AsmStep — it runs the line
// inside a wrapper, and a branch would leave it — so tracing reports them and steps over.
I64 AsmUiIsFlow(U8 *text)
{
  if (!MemCmp(text, "b", 1) && (text[1] == 'e' || text[1] == 'n' || text[1] == 'l' ||
                                text[1] == 'g'))
    return TRUE;
  // beq bne blt bge bltu bgeu beqz bnez
  if (!MemCmp(text, "j", 1) && (text[1] == ' ' || text[1] == 'a' || text[1] == 'r'))
    return TRUE;
  // j jal jalr jr
  if (!MemCmp(text, "ret", 3))
    return TRUE;
  if (!MemCmp(text, "call", 4))
    return TRUE;
  if (!MemCmp(text, "ecall", 5) || !MemCmp(text, "ebreak", 6))
    return TRUE;
  if (!MemCmp(text, "c.j", 3) || !MemCmp(text, "c.b", 3))
    return TRUE;
  return FALSE;
}

// AsmUiLayout -- AsmUiLayout(mode, home)
// NAME
//   AsmUiLayout - put up the standing pane layout and the prompt's scroll region
// SYNOPSIS
//   AsmUiLayout(0, TRUE);    // prompt layout, cursor at the top of its region
//   AsmUiLayout(-1, FALSE);  // same mode as before, prompt continues at the bottom
// DESCRIPTION
//   mode 0 is registers over the prompt, mode 1 adds the memory pane (the asm REPL); -1 keeps
//   whichever is current. DECSTBM homes the cursor to row 1 — inside the panes — so this always
//   moves it back into the region afterwards: `home` puts it at the top (a fresh screen) and
//   otherwise at the bottom, where the prompt carries on without overwriting what it printed.
// SEE ALSO
//   AsmRepl  RVDocTextScrollRegion  RegPaneUpdate  Cls
public U0 AsmUiLayout(I64 mode = -1, I64 home = FALSE)
{
  I64 rows, cols, reg_rows;
  if (mode >= 0)
    asmui_mode = mode;
  rows = rv_vt_term_rows;
  cols = rv_vt_term_cols;
  asmui_side = cols - ASMUI_SIDE_COLS >= ASMUI_MIN_TEXT;
  if (asmui_side) {
    asmui_side_col = cols - ASMUI_SIDE_COLS;
    asmui_text_cols = asmui_side_col - 1;
    // one column of gutter, so a full line of text does not touch the pane
    RegPaneAt(0, asmui_side_col, 1, ASMUI_SIDE_COLS);
    reg_rows = AsmUiRegRows(rows);
    RegPaneAt(0, asmui_side_col, reg_rows, ASMUI_SIDE_COLS);
    asmui_mem_row = reg_rows;
    asmui_mem_rows = rows - reg_rows;
    RVDocTextScrollRegion(0, 0);
    // the text column scrolls the whole screen; the sidebar is repainted rather than pinned
    if (home) {
      RVVtGoto(0, 0);
      RVVtFlush;
    }
  } else {
    RegPaneAt(0, 0, 1, cols);
    reg_rows = AsmUiRegRows(rows - 5);
    // stacked, the prompt needs rows of its own below the panes
    RegPaneAt(0, 0, reg_rows, cols);
    asmui_text_cols = cols;
    asmui_mem_row = reg_rows;
    asmui_mem_rows = asmui_mode ? 5 : 0;
    RVDocTextScrollRegion(reg_rows + asmui_mem_rows + 1, rows);
    RVVtGoto(home ? reg_rows + asmui_mem_rows : rows - 1, 0);
    // DECSTBM homes the cursor into the panes, so it always has to be put back in the region
    RVVtFlush;
  }
  RVLineEdWrap(asmui_text_cols);
  RVDolAnsiWrap(asmui_text_cols);
  asmui_ready = 1;
  RVDocTextInvalidate;
  // whatever was on those rows, the shadow no longer describes it
  RegPaneUpdate;
  AsmUiPanes;
}

// AsmUiPrePrompt -- installed with RVLineEdPrePrompt(&AsmUiPrePrompt)
// NAME
//   AsmUiPrePrompt - put the sidebar back before each line is read
// DESCRIPTION
//   Output scrolls the screen and the sidebar scrolls with it. Rather than fight the terminal
//   for every line, the panes are repainted at the prompt — the one moment the screen is quiet
//   and the operator is looking. The marks from the last step survive it, so the registers that
//   moved are still red.
// SEE ALSO
//   AsmUiLayout  RegPaneMark  RVLineEdPrePrompt
U0 AsmUiPrePrompt()
{
  if (!asmui_ready)
    return;
  if (rv_vt_probe_ok && !rv_vt_inband)
    RVVtProbeSize(40);
  // A terminal that reports resizes in band has already told us; one that answered a probe once
  // but says nothing when it is dragged gets asked again here, cheaply, at the only moment the
  // answer can be read without stealing a keystroke. One that never answered is never asked.
  if (!asmui_side)
    return;
  // Only the sidebar needs this. Stacked, the panes sit above a scroll region and the terminal
  // keeps them still by itself, so a step costs the cells that changed and a prompt costs
  // nothing — repainting there would throw that away.
  RVDocTextInvalidate;
  RegPaneUpdate;
  AsmUiPanes;
}

// AsmUiResized -- installed with RVVtOnResize(&AsmUiResized)
// NAME
//   AsmUiResized - lay the screen out again at the terminal's new size
// DESCRIPTION
//   Everything on screen was placed for the old size, so this clears before relaying out: panes
//   in the old columns would otherwise sit there as garbage the renderer no longer owns. The
//   split itself may change — a window dragged narrow stops being a sidebar and becomes stacked
//   panes with the prompt below them.
// SEE ALSO
//   RVVtOnResize  AsmUiLayout  RVVtResizeReports
public U0 AsmUiResized()
{
  if (!asmui_ready)
    return;
  Cls;
  // Cls relayouts through its hook; without one, put it up directly
  if (!dbgv_relayout_fn)
    AsmUiLayout(-1, TRUE);
}

// AsmRepl -- AsmRepl()
// NAME
//   AsmRepl - an assembler REPL with the registers and memory on screen
// SYNOPSIS
//   AsmRepl;
// DESCRIPTION
//   Each line is assembled and run against the debugger's register file (AsmStep), then the
//   register pane and the memory pane are repainted — so you watch the machine change rather
//   than reading a dump after the fact. History and Tab completion come from RVLineEd; the
//   registers are the same ones _A0 and Dr see, so you can leave the loop, poke a register
//   through a label, and come back.
// EXAMPLES
//   AsmRepl;
//     asm> li a0, 0x40
//     asm> add a1, a0, a0
//     asm> d 0x87000400      // point the memory pane at the register file itself
//     asm> q
// SEE ALSO
//   AsmStep  AsmRegs  Dr  Dbg  RVLineEd
public U0 AsmRepl()
{
  U8 line[192];
  I64 n, prev_fn;
  asmui_running = 1;
  prev_fn = rv_led_complete_fn;
  RVLineEdComplete(&AsmUiComplete);
  Cls;
  // Cls re-applies the layout through the relayout hook; without one (an image that did not wire
  // it) put it up directly, so the loop works either way.
  if (!dbgv_relayout_fn)
    AsmUiLayout(1, TRUE);
  "asm REPL: instructions are stepped; q leaves, d <addr> moves the memory pane, ? for keys\n";
  while (asmui_running) {
    n = RVLineEd(line, 192, "asm> ");
    if (n < 0)
      break;
    // Ctrl-C
    if (!n)
      continue;
    if (line[0] == 'q' && !line[1])
      break;
    if (line[0] == '?' && !line[1]) {
      "  q  leave   d <addr>  memory pane   u <sym|addr>  disassemble   r  repaint\n"
      "  t <sym|addr>  trace a compiled function, t again to step   f  float regs\n"
      "  ? <mn>  what it does   ?? the catalog\n";
      continue;
    }
    if (line[0] == '?' && line[1] == '?' && !line[2]) {
      AsmList;
      continue;
    }
    if (line[0] == '?') {
      // `? addi` — the documentation for the thing you were about to type, without leaving the
      // stepper to go and ask
      U8 *mn;
      mn = line + 1;
      while (*mn == ' ')
        mn++;
      AsmDoc(mn);
      continue;
    }
    if (line[0] == 'r' && !line[1]) {
      Cls;
      continue;
    }
    if (line[0] == 'f' && !line[1]) {
      RegPaneFpWant(!regp_fp_want);
      AsmUiLayout(-1, FALSE);
      if (regp_fp_want)
        "asm REPL: float registers in, memory out (f again to swap back)\n";
      else
        "asm REPL: memory back\n";
      continue;
    }
    if (line[0] == 'f' && line[1] == ' ') {
      // `f 10` — what fa0 actually IS: the number, and the sign/exponent/mantissa it is built
      // from. The pane can only afford the bits.
      RegPaneFd(Str2I64(line + 2));
      continue;
    }
    if (line[0] == 't' && (line[1] == ' ' || !line[1])) {
      // `t Foo` — write C at the prompt, compile it, then walk its instructions here. Each step
      // disassembles the instruction at the cursor and runs THAT TEXT through the stepper, so
      // you watch a compiled function move the registers one instruction at a time.
      U8 *arg, insn[128];
      I64 (*step)(U8 *t);
      arg = line + 1;
      while (*arg == ' ')
        arg++;
      if (*arg) {
        if (*arg >= '0' && *arg <= '9')
          asmui_trace_pc = Str2I64(arg);
        else
          asmui_trace_pc = RVDisFnAddr(arg);
        if (!asmui_trace_pc) {
          "asm REPL: no symbol '%s'\n", arg;
          continue;
        }
        asmui_tracing = 1;
        "asm REPL: tracing from 0x%X — t steps, q leaves\n", asmui_trace_pc;
      }
      if (!asmui_tracing) {
        "asm REPL: t <symbol|addr> to start tracing\n";
        continue;
      }
      if (!AsmUiInsnText(asmui_trace_pc, insn, 128)) {
        "asm REPL: nothing to disassemble at 0x%X\n", asmui_trace_pc;
        asmui_tracing = 0;
        continue;
      }
      "0x%X:  %s\n", asmui_trace_pc, insn;
      if (AsmUiIsFlow(insn)) {
        // Control flow cannot run inside the wrapper: it would jump out of it. Stepped over,
        // and said so, rather than pretending to have executed it.
        "  (control flow — not executed; t 0x<target> to follow it)\n";
      } else if (asmui_step_fn) {
        step = asmui_step_fn;
        step(insn);
      }
      asmui_trace_pc += 4;
      // RVC would be 2; the disassembler prints the width, and a compressed instruction here
      // simply lands the cursor mid-instruction, which the next disassembly shows plainly
      AsmUiPanes;
      continue;
    }
    if (line[0] == 'u' && (line[1] == ' ' || !line[1])) {
      // `u Foo` / `u 0x80001234` — read the machine's own instructions without leaving the
      // stepper. This is how you find an idiom worth copying: disassemble something that
      // already works, then type its instructions here and watch them move the registers.
      U8 *arg;
      I64 at;
      arg = line + 1;
      while (*arg == ' ')
        arg++;
      at = asmui_dis_addr;
      if (*arg >= '0' && *arg <= '9')
        at = Str2I64(arg);
      else if (*arg)
        at = RVDisFnAddr(arg);
      if (!at && *arg)
        "asm REPL: no symbol '%s' (Uf lists them)\n", arg;
      else if (!at)
        "asm REPL: u <symbol|addr> — nothing disassembled yet\n";
      else {
        DisasmAt(at, ASMUI_DIS_LINES, 0);
        asmui_dis_addr = at + ASMUI_DIS_LINES * 4;
        // a bare `u` next time carries on where this stopped, the way a debugger's u does
      }
      continue;
    }
    if (line[0] == 'd' && line[1] == ' ') {
      asmui_mem_addr = Str2I64(line + 2);
      AsmUiScrolled;
      AsmUiPanes;
      continue;
    }
    AsmUiScrolled;
    if (asmui_step_fn) {
      I64 (*step)(U8 *t);
      step = asmui_step_fn;
      step(line);
    } else {
      "asm REPL: no stepper installed (AsmReplInstallStep)\n";
    }
    AsmUiPanes;
  }
  asmui_running = 0;
  RVLineEdComplete(prev_fn);
  asmui_mode = 0;
  // the sidebar stays up: the registers are live at the HolyC prompt too
  Cls;
  "asm REPL: out\n";
}

#endif
