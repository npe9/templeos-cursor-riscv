// RVLineEd.HC — a line editor for the UART prompts: history, tab completion, cursor keys.
//
// RVUartGetLine (Kernel/Drv/RVUart16550.HC) reads a line and handles backspace, and that is all
// it was meant to do. At a real terminal you want the last thing you typed back, and you want
// Tab to finish a register or a mnemonic — especially in the asm REPL, where every line is
// three tokens and two of them are register names.
//
// Keys: Enter, Backspace/DEL, Ctrl-C (abandon), Ctrl-U (kill line), Tab (complete),
//       Up/Down (history), Left/Right (move), Home/End.
// Escape sequences arrive as ESC [ <final> from the terminal; anything not understood is
// dropped rather than inserted, because inserting it is how you get "^[[A" in your source line.
#ifndef RV_LINE_ED_HC
#define RV_LINE_ED_HC
#help_index "Term"

#define RV_LED_HIST 16
#define RV_LED_MAX 192

U8 rv_led_hist[RV_LED_HIST * RV_LED_MAX];
I64 rv_led_hist_n, rv_led_hist_pos;
// completion hook: fills `out` with the completion of `word`, returns TRUE if it found one
I64 rv_led_complete_fn;
// called just before the prompt is read: where the panes are put back up
I64 rv_led_pre_fn;
// the text column's width, 0 for the whole terminal. Echo that runs past it would be written
// over the panes beside it, so a long line scrolls sideways under the cursor instead.
I64 rv_led_wrap;

U0 RVLedPutC(I64 ch)
{
  U8 e[2];
  e[0] = ch;
  e[1] = 0;
  RVUartPutS(e);
}

U0 RVLedHistAdd(U8 *line)
{
  I64 i;
  if (!line || !*line)
    return;
  if (rv_led_hist_n >= RV_LED_HIST) {
    i = 0;
    while (i < RV_LED_HIST - 1) {
      StrCpy(rv_led_hist + i * RV_LED_MAX, rv_led_hist + (i + 1) * RV_LED_MAX);
      i++;
    }
    rv_led_hist_n = RV_LED_HIST - 1;
  }
  StrCpy(rv_led_hist + rv_led_hist_n * RV_LED_MAX, line);
  rv_led_hist_n++;
  rv_led_hist_pos = rv_led_hist_n;
}

// Redraw the whole line: \r, the prompt, as much of the text as the column holds, then erase to
// end and put the cursor back. When the line is longer than the column it scrolls sideways so
// that the cursor is always on screen — the same thing a shell does in a narrow window.
U0 RVLedRedraw(U8 *prompt, U8 *buf, I64 n, I64 cur)
{
  I64 i, plen = 0, avail, start = 0, last;
  if (prompt)
    plen = StrLen(prompt);
  RVLedPutC('\r');
  if (prompt)
    RVUartPutS(prompt);
  avail = n;
  if (rv_led_wrap) {
    avail = rv_led_wrap - plen - 1;
    if (avail < 8)
      avail = 8;
  }
  if (n > avail) {
    start = cur - avail;
    if (start < 0)
      start = 0;
  }
  last = start + avail;
  if (last > n)
    last = n;
  i = start;
  while (i < last) {
    RVLedPutC(buf[i]);
    i++;
  }
  RVVtCsi;
  RVVtPut('K');
  RVVtFlush;
  i = last;
  while (i > cur) {
    RVLedPutC(8);
    i--;
  }
}

// RVLineEdPrePrompt -- RVLineEdPrePrompt(&fn)
// NAME
//   RVLineEdPrePrompt - install what runs just before each line is read
// SYNOPSIS
//   RVLineEdPrePrompt(&AsmUiPrePrompt);   // U0 fn()
// DESCRIPTION
//   Output scrolls the screen, and anything painted beside it — a register sidebar — scrolls
//   with it. The prompt is the moment the screen is quiet again, so it is where the panes are
//   put back. Every prompt in the image gets this for free.
// SEE ALSO
//   RVLineEd  AsmUiLayout
public U0 RVLineEdPrePrompt(I64 fn)
{
  rv_led_pre_fn = fn;
}

// RVLineEdWrap -- RVLineEdWrap(cols)
// NAME
//   RVLineEdWrap - how wide the text column is (0 = the whole terminal)
// SEE ALSO
//   RVLineEd  RVDolAnsiWrap
public U0 RVLineEdWrap(I64 cols)
{
  rv_led_wrap = cols;
}

// RVLineEdComplete -- install the tab-completion hook
// NAME
//   RVLineEdComplete - set the function Tab calls
// SYNOPSIS
//   RVLineEdComplete(&MyComplete);   // I64 MyComplete(U8 *word, U8 *out, I64 max)
// SEE ALSO
//   RVLineEd
public U0 RVLineEdComplete(I64 fn)
{
  rv_led_complete_fn = fn;
}

// RVLineEd -- RVLineEd(buf, max, prompt)
// NAME
//   RVLineEd - read a line with history, completion and cursor keys
// SYNOPSIS
//   I64 RVLineEd(U8 *buf, I64 max, U8 *prompt = NULL);
// DESCRIPTION
//   Returns the length, or -1 if the line was abandoned with Ctrl-C. History is shared by every
//   prompt that uses this, which is what you want when you flip between the HolyC prompt and
//   the asm REPL.
// SEE ALSO
//   RVLineEdComplete  AsmRepl  RVUartGetLine
public I64 RVLineEd(U8 *buf, I64 max, U8 *prompt = NULL)
{
  U8 word[64], comp[128];
  I64 n = 0, cur = 0, ch, i, j, plen = 0;
  I64 (*complete)(U8 *w, U8 *o, I64 m);
  U0 (*pre)();
  if (rv_led_pre_fn) {
    pre = rv_led_pre_fn;
    pre();
  }
  if (max > RV_LED_MAX)
    max = RV_LED_MAX;
  if (prompt) {
    plen = StrLen(prompt);
    RVUartPutS(prompt);
    // the editor owns the prompt now — it redraws the line, so it has to have written it
    RVDolAnsiCol(plen);
  }
  buf[0] = 0;
  while (TRUE) {
    ch = RVUartGetC;
    if (ch == '\r' || ch == '\n') {
      RVUartPutS("\n\r");
      RVDolAnsiCol(0);
      // the editor writes straight to the wire, so the markup translator's idea of which column
      // it is in has to be corrected — it wraps printed output at the text column's width
      buf[n] = 0;
      RVLedHistAdd(buf);
      return n;
    }
    if (ch == 3) {
      // Ctrl-C
      RVUartPutS("\n\r");
      RVDolAnsiCol(0);
      buf[0] = 0;
      return -1;
    }
    if (ch == 21) {
      // Ctrl-U
      n = 0;
      cur = 0;
      buf[0] = 0;
      RVLedRedraw(prompt, buf, n, cur);
      continue;
    }
    if (ch == 8 || ch == 127) {
      if (cur > 0) {
        i = cur - 1;
        while (i < n) {
          buf[i] = buf[i + 1];
          i++;
        }
        n--;
        cur--;
        buf[n] = 0;
        RVLedRedraw(prompt, buf, n, cur);
      }
      continue;
    }
    if (ch == 9) {
      // Tab: complete the word under the cursor
      if (!rv_led_complete_fn)
        continue;
      i = cur;
      while (i > 0 && buf[i - 1] > ' ' && buf[i - 1] != ',' && buf[i - 1] != '(')
        i--;
      j = 0;
      while (i + j < cur && j < 62) {
        word[j] = buf[i + j];
        j++;
      }
      word[j] = 0;
      if (!j)
        continue;
      complete = rv_led_complete_fn;
      j = complete(word, comp, 128);
      if (j == 1) {
        // replace [i,cur) with comp
        buf[i] = 0;
        StrCat(buf, comp);
        n = StrLen(buf);
        cur = n;
      }
      if (j)
        RVLedRedraw(prompt, buf, n, cur);
      // 2 = the hook listed the candidates; the line is unchanged but the screen moved, so it
      // has to be drawn again either way
      continue;
    }
    if (ch == 27) {
      // CSI: arrows and friends. Unknown sequences are dropped, never inserted.
      ch = RVUartGetC;
      if (ch != '[')
        continue;
      ch = RVUartGetC;
      if (ch == 'A' || ch == 'B') {
        if (ch == 'A' && rv_led_hist_pos > 0)
          rv_led_hist_pos--;
        else if (ch == 'B' && rv_led_hist_pos < rv_led_hist_n)
          rv_led_hist_pos++;
        if (rv_led_hist_pos < rv_led_hist_n)
          StrCpy(buf, rv_led_hist + rv_led_hist_pos * RV_LED_MAX);
        else
          buf[0] = 0;
        n = StrLen(buf);
        cur = n;
        RVLedRedraw(prompt, buf, n, cur);
        continue;
      }
      if (ch == 'C') {
        if (cur < n) {
          cur++;
          RVVtCsi;
          RVVtPut('C');
          RVVtFlush;
        }
        continue;
      }
      if (ch == 'D') {
        if (cur > 0) {
          cur--;
          RVLedPutC(8);
        }
        continue;
      }
      if (ch == 'H') {
        cur = 0;
        RVLedRedraw(prompt, buf, n, cur);
        continue;
      }
      if (ch == 'F') {
        cur = n;
        RVLedRedraw(prompt, buf, n, cur);
        continue;
      }
      continue;
    }
    if (ch < ' ' || ch > 126 || n >= max - 1)
      continue;
    i = n;
    while (i > cur) {
      buf[i] = buf[i - 1];
      i--;
    }
    buf[cur] = ch;
    n++;
    cur++;
    buf[n] = 0;
    if (cur == n && (!rv_led_wrap || plen + n < rv_led_wrap))
      RVLedPutC(ch);
    else
      RVLedRedraw(prompt, buf, n, cur);
  }
  return n;
}

#endif
