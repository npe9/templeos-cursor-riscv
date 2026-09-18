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

// The memory pane, under the registers in whichever layout is in force.
U0 AsmUiPanes()
{
  I64 addr;
  if (!asmui_ready)
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
    reg_rows = RegPaneRowsNeeded;
    // ask at this width, then give it what it asked for
    if (reg_rows > rows - 3)
      reg_rows = rows - 3;
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
    reg_rows = RegPaneRowsNeeded;
    if (reg_rows > rows - 6)
      reg_rows = rows - 6;
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
  if (!asmui_ready || !asmui_side)
    return;
  // Only the sidebar needs this. Stacked, the panes sit above a scroll region and the terminal
  // keeps them still by itself, so a step costs the cells that changed and a prompt costs
  // nothing — repainting there would throw that away.
  RVDocTextInvalidate;
  RegPaneUpdate;
  AsmUiPanes;
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
      "  q  leave   d <addr>  memory pane   r  repaint   ? <mn>  what it does   "
      "?? the catalog\n";
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
