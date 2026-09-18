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

// Redraw the whole line: \r, the prompt, the text, then erase to end and put the cursor back.
U0 RVLedRedraw(U8 *prompt, U8 *buf, I64 n, I64 cur)
{
  I64 i;
  RVLedPutC('\r');
  if (prompt)
    RVUartPutS(prompt);
  RVUartPutS(buf);
  RVVtCsi;
  RVVtPut('K');
  RVVtFlush;
  i = n;
  while (i > cur) {
    RVLedPutC(8);
    i--;
  }
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
  I64 n = 0, cur = 0, ch, i, j;
  I64 (*complete)(U8 *w, U8 *o, I64 m);
  if (max > RV_LED_MAX)
    max = RV_LED_MAX;
  buf[0] = 0;
  while (TRUE) {
    ch = RVUartGetC;
    if (ch == '\r' || ch == '\n') {
      RVUartPutS("\n");
      buf[n] = 0;
      RVLedHistAdd(buf);
      return n;
    }
    if (ch == 3) {
      // Ctrl-C
      RVUartPutS("\n");
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
      if (complete(word, comp, 128)) {
        // replace [i,cur) with comp
        buf[i] = 0;
        StrCat(buf, comp);
        n = StrLen(buf);
        cur = n;
        RVLedRedraw(prompt, buf, n, cur);
      }
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
    if (cur == n)
      RVLedPutC(ch);
    else
      RVLedRedraw(prompt, buf, n, cur);
  }
  return n;
}

#endif
