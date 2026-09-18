// RVDocVT.HC — present the WinMgr / DolDoc text grid on a VT100 / xterm.
//
// STATUS: UNVERIFIED — written but never compiled or run. Not in any .PRJ yet.
//
// This is deliberately NOT a DolDoc-to-text renderer. RVWinMgr already composites
// every window, border, menu, PopUp, FileMgr and DolDoc entry stream into
// rv_winmgr.text_base as U32 cells:
//
//     ch = cell & 255           (index into sys_font_std, NOT ASCII below 0x20)
//     fg = (cell >> 8) & 15     ST_COLORS
//     bg = (cell >> 12) & 15
//     ATTRF_INVERT / ATTRF_SEL  flag bits
//
// RVGrPaintDC's glyph loop is one consumer of that grid (cells -> 8x8 glyphs ->
// framebuffer). This file is a second consumer (cells -> ANSI -> UART). Everything
// above the grid is untouched: DocRecalc lays entries out exactly as before, and
// RVWinMgrLiteInit() already runs the whole stack headless at 80x25 with no FB.
// So "DolDoc on a VT100" costs a presenter, not a renderer.
//
// Bandwidth is the design constraint, not correctness. A naive full repaint of
// 80x25 is 2000 cells; with a colour escape per cell that is ~24 KiB, which at
// 115200 baud (~11.5 KiB/s) is over two seconds per frame — unusable. So:
//   - diff against a shadow of what the terminal is already showing,
//   - emit a cursor address only when the run is not contiguous with the last,
//   - emit an SGR only when the attribute actually changes.
// A one-line edit then costs ~80 chars plus a couple of escapes (~120 B, ~10 ms).
//
// Character translation is the one real mismatch. TempleOS's font puts box-drawing
// glyphs at 0x02..0x0D (see RVWinMgrBorderCharsInit / RVTextBorder), where a
// terminal expects control codes. Those twelve are mapped explicitly; 0x20..0x7E
// pass through; everything else falls back rather than emitting a stray control
// byte into the operator's terminal.
#ifndef RV_DOC_VT_HC
#define RV_DOC_VT_HC
#help_index "DolDoc/VT"

#define RV_VT_CELLS_MAX 8192
#define RV_VT_BUF       512

U32 rv_vt_shadow[RV_VT_CELLS_MAX];
U8 rv_vt_buf[RV_VT_BUF];
I64 rv_vt_n;          // bytes pending in rv_vt_buf
I64 rv_vt_ready;      // shadow is valid: diff instead of full repaint
I64 rv_vt_utf8;       // 1 = UTF-8 box drawing, 0 = ASCII + - | fallback
I64 rv_vt_color;      // 1 = emit SGR colour
I64 rv_vt_fg;         // last SGR state actually sent (-1 = unknown)
I64 rv_vt_bg;
I64 rv_vt_inv;
I64 rv_vt_cost;       // bytes sent by the last present (for the smoke / tuning)
I64 rv_vt_oversize;   // reported the too-big-grid refusal once

U0 RVVtFlush()
{
  if (!rv_vt_n)
    return;
  rv_vt_buf[rv_vt_n] = 0;
  RVUartPutS(rv_vt_buf);
  rv_vt_cost += rv_vt_n;
  rv_vt_n = 0;
}

U0 RVVtPut(I64 ch)
{
  if (rv_vt_n >= RV_VT_BUF - 8)
    RVVtFlush();
  rv_vt_buf[rv_vt_n] = ch & 255;
  rv_vt_n++;
}

U0 RVVtPutS(U8 *s)
{
  while (s && *s) {
    RVVtPut(*s);
    s++;
  }
}

// Digit scratch is file scope on purpose: stores into a narrow *local* array are a
// known codegen hazard in this compiler (an 8-byte store into a U8 slot clobbers
// its neighbours), and this runs on every cursor address.
U8 rv_vt_num[24];

U0 RVVtPutNum(I64 v)
{
  I64 i;
  if (v < 0)
    v = 0;
  i = 0;
  if (!v) {
    RVVtPut('0');
    return;
  }
  while (v > 0 && i < 20) {
    rv_vt_num[i] = '0' + v % 10;
    v = v / 10;
    i++;
  }
  while (i > 0) {
    i--;
    RVVtPut(rv_vt_num[i]);
  }
}

U0 RVVtCsi()
{
  RVVtPut(27);
  RVVtPut('[');
}
// DECSC/DECRC. A pane repaint happens while someone is typing at a prompt somewhere else on the
// screen: it has to put the cursor back, and the COLOUR back too — the pane's last SGR would
// otherwise tint the next thing the prompt echoes. ESC 7 saves both, ESC 8 restores both, which
// is why this and not a remembered row/col.
U0 RVVtSaveCur()
{
  RVVtPut(27);
  RVVtPut('7');
}
U0 RVVtRestoreCur()
{
  RVVtPut(27);
  RVVtPut('8');
}
// CSI row;colH — VT100 is 1-based, the grid is 0-based.
U0 RVVtGoto(I64 row, I64 col)
{
  RVVtCsi();
  RVVtPutNum(row + 1);
  RVVtPut(';');
  RVVtPutNum(col + 1);
  RVVtPut('H');
}
// ST_COLORS -> ANSI. TempleOS orders BLUE=1/GREEN=2/CYAN=3/RED=4 where ANSI has
// RED=1/GREEN=2/YELLOW=3/BLUE=4, so 1<->4 and 3<->6 swap; bit 3 is the bright
// plane (90/100 rather than 30/40). Same mapping as seed/term.hc TermSgrColor,
// duplicated because that file is the REPL image and this is the kernel image.
I64 RVVtSgrColor(I64 n)
{
  I64 c;
  c = n & 7;
  if (c == 1)
    c = 4;
  else if (c == 3)
    c = 6;
  else if (c == 4)
    c = 1;
  else if (c == 6)
    c = 3;
  if (n & 8)
    return 90 + c;
  return 30 + c;
}

// ---- Theme -------------------------------------------------------------------
// TempleOS's 16 colors are used as ROLES, not pixels: DolDoc and the WinMgr say
// "WHITE background, BLACK text, BLUE border" and mean "body ground, body ink,
// chrome". That is a light-ground assumption baked into 1990s hardware, and a
// terminal today is usually dark. So rather than rewrite every caller, reinterpret
// the 16 values here — one color->color function, before the ANSI mapping.
//
// The policy is split in two so it stays explainable:
//   lightness — the grayscale ramp BLACK(0) < DKGRAY(8) < LTGRAY(7) < WHITE(15) is
//               mirrored, so "black ink on white" becomes "white ink on black" and
//               relative emphasis is preserved rather than merely inverted;
//   hue       — the six hues keep their identity and take the bright variant, which
//               is what stays legible against a dark ground.
// Nothing here decides meaning; it only decides how a role is painted. The
// minimum-contrast floor below still runs afterwards as a backstop.
#define RV_VT_THEME_CLASSIC 0
#define RV_VT_THEME_DARK    1
I64 rv_vt_theme;
I64 RVVtThemeMap(I64 c)
{
  // Foreground policy: mirror the grayscale ramp, brighten the hues.
  c = c & 15;
  if (rv_vt_theme == RV_VT_THEME_CLASSIC)
    return c;
  if (c == BLACK)
    return WHITE;
  if (c == WHITE)
    return BLACK;
  if (c == DKGRAY)
    return LTGRAY;
  if (c == LTGRAY)
    return DKGRAY;
  return c | 8;
}

I64 RVVtThemeMapBg(I64 c)
{
  // Background policy is deliberately NOT the mirror of the foreground one:
  // a dark theme darkens light grounds but must never LIGHTEN a dark one.
  //
  // Mirroring both was the "white boundary": RVTextBorder plants attr<<8, so every
  // border cell carries bg = BLACK — not a colour choice, just an unset ground — and
  // a symmetric mirror turned all of them white. Same for any cell the WinMgr leaves
  // at its default ground. Backgrounds therefore move one way only.
  c = c & 15;
  if (rv_vt_theme == RV_VT_THEME_CLASSIC)
    return c;
  if (c == WHITE)
    return BLACK;
  if (c == LTGRAY)
    return DKGRAY;
  if (c == BLACK || c == DKGRAY)
    return c;
  // A hue used as a ground (BLUE title bars, wallpaper) keeps its identity and its
  // darker plane so foreground text still reads against it.
  return c & 7;
}
// Minimum-contrast guard. Default ON: set rv_vt_min_contrast = 0 for verbatim colors.
//
// A framebuffer renders TempleOS's 16 colors as actual RGB, so LTGRAY on WHITE is
// merely pale. A terminal maps them onto its own palette, where the same pair lands
// near 1.4:1 and is effectively unreadable — and DolDoc entries carry their own colors,
// so no window-level theme can reach them. This is the one place that sees the final
// pair, so it is the right place to enforce a floor.
//
// The rule is deliberately crude and predictable: classify each color light or dark by
// its bright bit and its base hue, and if foreground and background land in the same
// class, snap the foreground to the opposite extreme. Hue is preserved wherever it
// already contrasts, so colour still carries meaning; it just cannot carry it alone.
I64 rv_vt_min_contrast;
I64 RVVtIsLight(I64 c)
{
  // TempleOS: bit 3 is the bright plane. Bright anything reads light, and among the
  // dark half only LTGRAY(7) is light enough to fail against WHITE.
  c = c & 15;
  if (c & 8)
    return 1;
  if (c == LTGRAY)
    return 1;
  return 0;
}

U0 RVVtSgr(I64 fg, I64 bg, I64 inv)
{
  // rv_vt_fg/bg must record what the CALLER asked for, not what we painted: the
  // present loop compares the next cell's raw attr against them to decide whether an
  // SGR is needed at all. Caching themed values made every comparison differ, so the
  // full paint went 2373 -> 21710 bytes — an escape per cell, which is exactly the
  // bandwidth blow-up this presenter exists to avoid.
  I64 raw_fg = fg, raw_bg = bg;
  // Theme first (role -> paint), contrast floor second (paint -> legible paint).
  if (rv_vt_color) {
    if (!fg && !bg && rv_vt_theme != RV_VT_THEME_CLASSIC) {
      // An all-zero attr is an UNSET cell — rv_winmgr.text_base is MemSet to 0 — not
      // somebody choosing black-on-black. Theming it as a colour pair inverts it into
      // a white ground, which is how a dark theme ended up painting every blank cell
      // white while the text cells went dark. Paint it as the terminal's own ground.
      fg = LTGRAY;
      bg = BLACK;
    } else {
      fg = RVVtThemeMap(fg);
      bg = RVVtThemeMapBg(bg);
    }
  }
  if (rv_vt_min_contrast && rv_vt_color) {
    if (RVVtIsLight(fg) && RVVtIsLight(bg))
      fg = BLACK;
    else if (!RVVtIsLight(fg) && !RVVtIsLight(bg))
      fg = WHITE;
  }
  // One CSI carries the whole attribute change: ESC [ 0 ; fg ; bg [; 7] m.
  RVVtCsi();
  RVVtPut('0');
  if (rv_vt_color) {
    RVVtPut(';');
    RVVtPutNum(RVVtSgrColor(fg));
    RVVtPut(';');
    RVVtPutNum(RVVtSgrColor(bg) + 10);
  }
  if (inv) {
    RVVtPut(';');
    RVVtPut('7');
  }
  RVVtPut('m');
  rv_vt_fg = raw_fg;
  rv_vt_bg = raw_bg;
  rv_vt_inv = inv;
}
// TempleOS font code -> terminal bytes. 0x02..0x0D are the border glyphs
// RVTextBorder plants: even = unfocused (single line), odd = focused (double).
U0 RVVtPutGlyph(I64 ch)
{
  U8 *u;
  ch = ch & 255;
  if (ch >= 0x20 && ch < 0x7F) {
    RVVtPut(ch);
    return;
  }
  if (ch < 0x02 || ch > 0x0D) {
    // Anything else in the font (or a NUL cell) becomes a space rather than a
    // control byte the terminal would act on.
    RVVtPut(' ');
    return;
  }
  if (!rv_vt_utf8) {
    if (ch == 0x02 || ch == 0x03)
      RVVtPut('-');
    else if (ch == 0x04 || ch == 0x05)
      RVVtPut('|');
    else
      RVVtPut('+');
    return;
  }
  u = "";
  if (ch == 0x02)
    u = "─";
  else if (ch == 0x03)
    u = "═";
  else if (ch == 0x04)
    u = "│";
  else if (ch == 0x05)
    u = "║";
  else if (ch == 0x06)
    u = "┌";
  else if (ch == 0x07)
    u = "╔";
  else if (ch == 0x08)
    u = "┐";
  else if (ch == 0x09)
    u = "╗";
  else if (ch == 0x0A)
    u = "└";
  else if (ch == 0x0B)
    u = "╚";
  else if (ch == 0x0C)
    u = "┘";
  else if (ch == 0x0D)
    u = "╝";
  RVVtPutS(u);
}

I64 rv_vt_term_rows = 25, rv_vt_term_cols = 80;
// what the terminal said when asked; the safe default until it does
I64 rv_vt_resize_fn, rv_vt_probe_ok, rv_vt_inband;
// rv_vt_inband: the terminal sent an unsolicited resize report, so it will send the next one
// too and nobody needs to keep asking

// RVVtOnResize -- RVVtOnResize(&fn)
// NAME
//   RVVtOnResize - install what runs when the terminal changes size
// SYNOPSIS
//   RVVtOnResize(&AsmUiResized);   // U0 fn()
// SEE ALSO
//   RVVtSizeSet  RVVtResizeReports  RVVtProbeSize
public U0 RVVtOnResize(I64 fn)
{
  rv_vt_resize_fn = fn;
}

// RVVtSizeSet -- RVVtSizeSet(rows, cols)
// NAME
//   RVVtSizeSet - record a size the terminal reported, and relayout if it moved
// DESCRIPTION
//   The one place a new size takes effect, whichever way it arrived: the answer to a probe, or
//   an unsolicited report when the window was dragged. Returns TRUE if it actually changed —
//   a report that says what we already believe must not repaint the screen.
// SEE ALSO
//   RVVtOnResize  RVVtProbeSize
public I64 RVVtSizeSet(I64 rows, I64 cols)
{
  U0 (*fn)();
  if (rows < 10 || rows > 200 || cols < 40 || cols > 400)
    return FALSE;
  // a size outside this is a misread reply, and the old one is better than a wrong one
  rv_vt_probe_ok = 1;
  if (rows == rv_vt_term_rows && cols == rv_vt_term_cols)
    return FALSE;
  rv_vt_term_rows = rows;
  rv_vt_term_cols = cols;
  if (rv_vt_resize_fn) {
    fn = rv_vt_resize_fn;
    fn();
  }
  return TRUE;
}

// RVVtResizeReports -- RVVtResizeReports(on)
// NAME
//   RVVtResizeReports - ask the terminal to tell us when it is resized (mode 2048)
// SYNOPSIS
//   RVVtResizeReports(TRUE);
// DESCRIPTION
//   In-band resize notification: the terminal sends "CSI 48 ; rows ; cols ; ... t" whenever the
//   window changes, and one immediately when the mode is set. A serial guest gets no SIGWINCH —
//   this is the only way to hear about a resize as it happens rather than at the next prompt.
//   Terminals that do not know the mode ignore it, which is why the prompt also re-probes.
// SEE ALSO
//   RVVtSizeSet  RVVtProbeSize  RVLineEd
public U0 RVVtResizeReports(I64 on)
{
  RVVtCsi();
  RVVtPut('?');
  RVVtPut('2');
  RVVtPut('0');
  RVVtPut('4');
  RVVtPut('8');
  RVVtPut(on ? 'h' : 'l');
  RVVtFlush;
}

// RVVtProbeSize -- RVVtProbeSize(ms)
// NAME
//   RVVtProbeSize - ask the terminal its size, and believe the answer
// SYNOPSIS
//   RVVtProbeSize(300);   // returns TRUE if the terminal answered
// DESCRIPTION
//   Parks the cursor far beyond any real screen (the terminal clamps it to its own corner) and
//   asks where it ended up with DSR — the cursor-position report every terminal implements,
//   unlike the window-size report. Bounded wait: a terminal that says nothing leaves the
//   defaults, which is the whole point of asking rather than assuming. Bytes that are not part
//   of the reply are pushed back, because the operator may have typed ahead.
// SEE ALSO
//   rv_vt_term_rows  rv_vt_term_cols  AsmUiLayout
public I64 RVVtProbeSize(I64 ms = 300)
{
  I64 deadline, ch, r = 0, c = 0, st = 0;
  RVVtSaveCur();
  RVVtGoto(998, 998);
  RVVtCsi();
  RVVtPut('6');
  RVVtPut('n');
  RVVtRestoreCur();
  RVVtFlush;
  deadline = *(I64 *)(CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF) +
             ms * (CONFIG_TIMEBASE_FREQ / 1000);
  while (*(I64 *)(CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF) < deadline) {
    ch = RVUartTryGet;
    if (ch < 0)
      continue;
    if (st == 0) {
      if (ch == 27)
        st = 1;
      else
        RVUartSoftEnqueue(ch);
      continue;
    }
    if (st == 1) {
      if (ch == '[') {
        st = 2;
      } else {
        RVUartSoftEnqueue(27);
        RVUartSoftEnqueue(ch);
        st = 0;
      }
      continue;
    }
    if (ch >= '0' && ch <= '9') {
      if (st == 2)
        r = r * 10 + ch - '0';
      else
        c = c * 10 + ch - '0';
      continue;
    }
    if (ch == ';' && st == 2) {
      st = 3;
      continue;
    }
    if (ch == 'R' && st == 3) {
      // Sanity: a terminal smaller than this cannot hold any of these panes, and one this large
      // is a reply we misread. Either way the defaults are better than the answer.
      RVVtSizeSet(r, c);
      // TRUE means the terminal answered, not that the size changed
      return rv_vt_probe_ok;
    }
    // not the reply after all
    st = 0;
    r = 0;
    c = 0;
  }
  return FALSE;
}

U0 RVVtHome()
{
  RVVtCsi();
  RVVtPut('H');
}

U0 RVVtClear()
{
  RVVtCsi();
  RVVtPut('2');
  RVVtPut('J');
  RVVtHome();
}

// RVVtCursorStyle -- RVVtCursorStyle(style)
// NAME
//   RVVtCursorStyle - blinking block, underline or bar (DECSCUSR)
// SYNOPSIS
//   RVVtCursorStyle(1);   // blinking block   2 steady block
//   RVVtCursorStyle(3);   // blinking under   4 steady underline
//   RVVtCursorStyle(5);   // blinking bar     6 steady bar
//   RVVtCursorStyle(0);   // whatever the terminal had before
// DESCRIPTION
//   CSI Ps SP q — the space before the q is part of the sequence, not decoration. A terminal
//   that does not know it ignores it and keeps its own cursor, which is why this is safe to send
//   unasked.
// SEE ALSO
//   RVVtCursor  RVVtInit
U0 RVVtCursorStyle(I64 style)
{
  RVVtCsi();
  RVVtPutNum(style);
  RVVtPut(' ');
  RVVtPut('q');
}

U0 RVVtCursor(I64 on)
{
  RVVtCsi();
  RVVtPut('?');
  RVVtPut('2');
  RVVtPut('5');
  if (on)
    RVVtPut('h');
  else
    RVVtPut('l');
}
// Forget what the terminal is showing: the next present repaints every cell.
// Call after the operator's terminal was scribbled on (a Print, a crash dump).
U0 RVVtInvalidate()
{
  rv_vt_ready = 0;
}

U0 RVVtInit(I64 utf8, I64 color)
{
  // Set here rather than as file-scope initialisers: a global WITH an initialiser
  // compiles through PrsVarInit2, and adding two of those to the shared win Kernel
  // unit is what regressed kernel-win-interactive's DocInit_RV hash (lex 1 -> 0).
  rv_vt_theme = RV_VT_THEME_DARK;
  rv_vt_min_contrast = 1;
  rv_vt_utf8 = utf8;
  rv_vt_color = color;
  rv_vt_n = 0;
  rv_vt_cost = 0;
  RVVtInvalidate();
  RVVtCursor(1);
  RVVtCursorStyle(1);
  // A blinking block, and SHOWN: this used to hide the cursor for the life of the session, which
  // left the prompt with nothing to mark where you were typing. The panes hide it around their
  // own paints (RVDocTextRender) so it does not bounce across the screen on the way.
  RVVtClear();
  RVVtFlush();
}

U0 RVVtStop()
{
  // Leave the terminal usable: default attributes, cursor back on, on the LAST grid
  // row. Parking one row *below* the grid (rv_winmgr.rows, i.e. ESC[26;1H at 25 rows)
  // costs a scroll on any terminal exactly grid-height — the frame jumps up by one
  // line as the last act of a clean shutdown, which looks like a rendering bug and is
  // the shape of the 80x24-vs-80x25 problem in docs/DOLDOC_VT.md. The shell's next
  // prompt scrolls normally from here, which is what a terminal user expects.
  rv_vt_n = 0;
  RVVtSgr(WHITE, BLACK, 0);
  RVVtGoto(rv_winmgr.rows - 1, 0);
  RVVtCursor(1);
  RVVtFlush();
  RVVtInvalidate();
}
// Ship the current text grid to the terminal. Returns bytes written, so a smoke
// can assert that an idle frame costs 0 and a one-line edit costs far less than a
// full repaint — the property the whole design exists to provide.
I64 RVVtPresent()
{
  I64 rows, cols, row, col, i, cell, prev, ch, fg, bg, inv, run, cur_col;
  U32 *grid;
  if (!rv_winmgr.ready || !rv_winmgr.text_base)
    return 0;
  rows = rv_winmgr.rows;
  cols = rv_winmgr.cols;
  if (rows * cols > RV_VT_CELLS_MAX) {
    // A returned 0 otherwise reads as "nothing changed", so an oversized grid would
    // look like a working presenter painting a blank terminal. Say so once.
    if (!rv_vt_oversize) {
      rv_vt_oversize = 1;
      RVUartPutS("RVVtPresent: grid larger than RV_VT_CELLS_MAX; not presenting\n");
    }
    return -1;
  }
  grid = rv_winmgr.text_base;
  rv_vt_cost = 0;
  rv_vt_n = 0;
  // Attribute state is only known to match while the shadow is valid.
  if (!rv_vt_ready) {
    rv_vt_fg = -1;
    rv_vt_bg = -1;
    rv_vt_inv = -1;
    RVVtClear();
  }
  for (row = 0; row < rows; row++) {
    cur_col = -1;
    // -1 = cursor is not on this row at a useful column
    col = 0;
    while (col < cols) {
      i = row * cols + col;
      cell = grid[i];
      prev = rv_vt_shadow[i];
      if (rv_vt_ready && cell == prev) {
        col++;
        continue;
      }
      // Found a changed cell; emit from here until the cells match again. A short
      // matching gap is cheaper to overwrite than to re-address around, so only
      // break the run on a longer stretch of unchanged cells.
      run = 0;
      while (col < cols) {
        i = row * cols + col;
        cell = grid[i];
        prev = rv_vt_shadow[i];
        if (rv_vt_ready && cell == prev) {
          run++;
          if (run > 4)
            break;
        } else {
          run = 0;
        }
        ch = cell & 255;
        fg = (cell >> 8) & 15;
        bg = (cell >> 12) & 15;
        inv = 0;
        if (cell & ATTRF_INVERT)
          inv = 1;
        if (cell & ATTRF_SEL) {
          fg = fg ^ 15;
          bg = bg ^ 15;
        }
        if (col != cur_col) {
          RVVtGoto(row, col);
          cur_col = col;
        }
        if (fg != rv_vt_fg || bg != rv_vt_bg || inv != rv_vt_inv)
          RVVtSgr(fg, bg, inv);
        if (!ch)
          ch = ' ';
        RVVtPutGlyph(ch);
        cur_col++;
        rv_vt_shadow[i] = cell;
        col++;
      }
    }
  }
  rv_vt_ready = 1;
  RVVtFlush();
  return rv_vt_cost;
}
// Present, then park the terminal cursor where DolDoc's caret is, so a VT100 user
// sees the same insertion point an FB user sees.
I64 RVVtPresentAt(I64 crow, I64 ccol)
{
  I64 n;
  n = RVVtPresent();
  rv_vt_n = 0;
  RVVtGoto(crow, ccol);
  RVVtCursor(1);
  RVVtFlush();
  return n;
}
#endif
