// TempleOS-style window manager on native 32-bpp FB (Phase F).
//
// Faithful subset of Adam WinMgr / GrScrn text path — NOT VGA:
//   - U32 text_base cells (ASCII + 4-bit FG/BG, same layout as Doc/TextBase.DD)
//   - TextBorder / TextRect / TextPrint into text_base (portable HolyC, no x86 asm)
//   - Z-ordered task windows with borders + titles
//   - Render text_base → rv_fb (XRGB8888) then RVFbPresent
//
// Gaps vs full Adam: no DolDoc, no mouse/kbd grab, no ODE, no 8-bit CDC blot /
// GrUpdateVGAGraphics. draw_it hooks paint pixels in the client rect after text.
#define RV_WIN_MAX       8
#define RV_WIN_TITLE_MAX 48
#define RV_WIN_BODY_MAX  768
class CRVWin
{
  //One on-screen window (TempleOS: one window per Core0 task).
  Bool used;
  Bool show;
  Bool no_border;
  Bool focused;
  I64 left;
  // inclusive text-cell coords (same as CTask.win_*)
  I64 right;
  I64 top;
  I64 bottom;
  I64 border_attr;
  // 4-bit color; TextBorder does attr<<8
  I64 text_attr;
  // BG<<4|FG for client fill (TempleOS text_attr)
  I64 z;
  // higher = on top (assigned at refresh)
  U8 title[RV_WIN_TITLE_MAX];
  U8 body[RV_WIN_BODY_MAX];
  // Doc-lite text; $$0-$$F FG (not full DolDoc)
  U0 (*draw_it)(CRVWin *w, CRVDC *dc);
  // optional pixel draw in client
}
;
class CRVWinMgrGlbls
{
  Bool ready;
  I64 cols;
  // text.cols analogue
  I64 rows;
  U32 *text_base;
  // cols*rows U32 cells
  U8 border_chars[16];
  // TempleOS graphics-mode border glyphs 0x02..0x0D
  I64 wallpaper_attr;
  // BG<<4|FG
  U8 wallpaper_line[96];
  I64 n_wins;
  CRVWin wins[RV_WIN_MAX];
  I64 focus;
  // index into wins[], or -1
  I64 updates;
}
;
CRVWinMgrGlbls rv_winmgr;
// Backing store sized for 800×600 (100×75). Init clips to actual FB text grid.
U32 rv_text_base_store[100 * 75];
U0 RVWinMgrBorderCharsInit()
{
  //Match Kernel/KMain.HC SysGrInit graphics-mode border_chars.
  rv_winmgr.border_chars[2](I64) = 0x0908070605040302;
  rv_winmgr.border_chars[10](U32) = 0x0D0C0B0A;
}

Bool RVWinMgrInit()
{
  //Requires RVGrInit / live rv_fb. Sets up text grid + empty window list.
  I64 cols, rows;
  if (!rv_fb.pixels || !rv_gr.dc)
    return FALSE;
  cols = rv_fb.width / FONT_WIDTH;
  rows = rv_fb.height / FONT_HEIGHT;
  if (cols < 20 || rows < 10)
    return FALSE;
  if (cols > 100)
    cols = 100;
  if (rows > 75)
    rows = 75;
  MemSet(&rv_winmgr, 0, sizeof(CRVWinMgrGlbls));
  rv_winmgr.cols = cols;
  rv_winmgr.rows = rows;
  rv_winmgr.text_base = rv_text_base_store;
  MemSet(rv_text_base_store, 0, cols *rows *sizeof(U32));
  RVWinMgrBorderCharsInit;
  rv_winmgr.wallpaper_attr = BLUE << 4 + WHITE;
  StrCpy(rv_winmgr.wallpaper_line, "TempleOS/RISC-V  WinMgr on 32-bpp FB");
  rv_winmgr.focus = -1;
  rv_winmgr.ready = TRUE;
  // Also mirror into global text.* so TaskInit-sized fields stay coherent.
  text.cols = cols;
  text.rows = rows;
  text.font = sys_font_std;
  text.aux_font = sys_font_cyrillic;
  MemCpy(text.border_chars, rv_winmgr.border_chars, 16);
  return TRUE;
}

I64 RVWinAttr(I64 bg, I64 fg)
{
  //Pack TempleOS-style attribute nibble pair.
  return (bg & 15) << 4 | (fg & 15);
}

U0 RVTextChar(I64 x, I64 y, I64 d)
{
  //Plot one text_base cell (absolute screen coords). No task clipping.
  if (!rv_winmgr.ready)
    return;
  if (x < 0 || y < 0 || x >= rv_winmgr.cols || y >= rv_winmgr.rows)
    return;
  rv_winmgr.text_base[y *rv_winmgr.cols + x] = d;
}

U0 RVTextRect(I64 l, I64 r, I64 t, I64 b, I64 d)
{
  //Fill text rect with cell value d (TempleOS TextRect).
  I64 x, y;
  if (!rv_winmgr.ready || l > r || t > b)
    return;
  if (t < 0)
    t = 0;
  if (b >= rv_winmgr.rows)
    b = rv_winmgr.rows - 1;
  if (l < 0)
    l = 0;
  if (r >= rv_winmgr.cols)
    r = rv_winmgr.cols - 1;
  for (y = t; y <= b; y++)
    for (x = l; x <= r; x++)
      rv_winmgr.text_base[y *rv_winmgr.cols + x] = d;
}

U0 RVTextBorder(I64 l, I64 r, I64 t, I64 b, I64 attr, Bool solid)
{
  //TempleOS TextBorder (portable). attr is 4-bit color; solid⇒focus chrome.
  I64 i, a;
  U8 *bc = rv_winmgr.border_chars;
  if (!rv_winmgr.ready)
    return;
  a = attr << 8;
  RVTextChar(l - 1, t - 1, bc[6 + solid] + a);
  RVTextChar(r + 1, t - 1, bc[8 + solid] + a);
  RVTextChar(l - 1, b + 1, bc[10 + solid] + a);
  RVTextChar(r + 1, b + 1, bc[12 + solid] + a);
  for (i = l; i <= r; i++) {
    RVTextChar(i, t - 1, bc[2 + solid] + a);
    RVTextChar(i, b + 1, bc[2 + solid] + a);
  }
  for (i = t; i <= b; i++) {
    RVTextChar(l - 1, i, bc[4 + solid] + a);
    RVTextChar(r + 1, i, bc[4 + solid] + a);
  }
}

U0 RVTextPrint(I64 x, I64 y, I64 attr, U8 *st)
{
  //Plot string at absolute cell (x,y). attr is BG<<4|FG (<<8 into cell).
  I64 a;
  if (!st || !rv_winmgr.ready)
    return;
  a = attr << 8;
  while (*st) {
    if (*st == '\n') {
      x = 0;
      y++;
      st++;
      continue;
    }
    if (x >= 0 && y >= 0 && x < rv_winmgr.cols && y < rv_winmgr.rows)
      rv_winmgr.text_base[y *rv_winmgr.cols + x] = (*st & 255) + a;
    x++;
    st++;
  }
}

I64 RVWinAlloc()
{
  //Allocate a free window slot; -1 if full.
  I64 i;
  for (i = 0; i < RV_WIN_MAX; i++) {
    if (!rv_winmgr.wins[i].used) {
      MemSet(&rv_winmgr.wins[i], 0, sizeof(CRVWin));
      rv_winmgr.wins[i].used = TRUE;
      rv_winmgr.wins[i].show = TRUE;
      rv_winmgr.wins[i].border_attr = BLUE;
      rv_winmgr.wins[i].text_attr = BLUE << 4 + WHITE;
      rv_winmgr.n_wins++;
      return i;
    }
  }
  return -1;
}

Bool RVWinHorz(I64 idx, I64 left, I64 right)
{
  //Set horizontal text-cell span (inclusive), TempleOS WinHorz.
  CRVWin *w;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return FALSE;
  w = &rv_winmgr.wins[idx];
  if (!w->used)
    return FALSE;
  if (left > right)
    return FALSE;
  w->left = left;
  w->right = right;
  return TRUE;
}

Bool RVWinVert(I64 idx, I64 top, I64 bottom)
{
  //Set vertical text-cell span (inclusive), TempleOS WinVert.
  CRVWin *w;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return FALSE;
  w = &rv_winmgr.wins[idx];
  if (!w->used)
    return FALSE;
  if (top > bottom)
    return FALSE;
  w->top = top;
  w->bottom = bottom;
  return TRUE;
}

U0 RVWinSetTitle(I64 idx, U8 *title)
{
  CRVWin *w;
  I64 i;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return;
  w = &rv_winmgr.wins[idx];
  if (!w->used)
    return;
  if (!title) {
    w->title[0] = 0;
    return;
  }
  for (i = 0; i < RV_WIN_TITLE_MAX - 1 && title[i]; i++)
    w->title[i] = title[i];
  w->title[i] = 0;
}

U0 RVWinSetWallpaper(U8 *line)
{
  //Adam WallPaper lite: status line drawn across the FB desktop.
  I64 i;
  if (!line)
    return;
  for (i = 0; i < 95 && line[i]; i++)
    rv_winmgr.wallpaper_line[i] = line[i];
  rv_winmgr.wallpaper_line[i] = 0;
}

U0 RVWinSetBody(I64 idx, U8 *body)
{
  CRVWin *w;
  I64 i;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return;
  w = &rv_winmgr.wins[idx];
  if (!w->used)
    return;
  if (!body) {
    w->body[0] = 0;
    return;
  }
  for (i = 0; i < RV_WIN_BODY_MAX - 1 && body[i]; i++)
    w->body[i] = body[i];
  w->body[i] = 0;
}

U0 RVWinFocus(I64 idx)
{
  //Mark window focused (solid border); others hollow.
  I64 i;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used) {
    rv_winmgr.focus = -1;
    for (i = 0; i < RV_WIN_MAX; i++)
      rv_winmgr.wins[i].focused = FALSE;
    return;
  }
  rv_winmgr.focus = idx;
  for (i = 0; i < RV_WIN_MAX; i++)
    rv_winmgr.wins[i].focused = (i == idx);
}

U0 RVWinMgrWallPaper()
{
  //Fill text_base with wallpaper + top status line (Adam/WallPaper lite).
  I64 attr = rv_winmgr.wallpaper_attr;
  RVTextRect(0, rv_winmgr.cols - 1, 0, rv_winmgr.rows - 1, attr << 8 + ' ');
  RVTextPrint(1, 0, BLUE << 4 + YELLOW, rv_winmgr.wallpaper_line);
  RVTextPrint(1, rv_winmgr.rows - 1, BLUE << 4 + LTGRAY, "RVWinMgr  text_base  MakeAdam/DolDoc-lite  $$0-F FG  $$B0-F BG");
}

U0 RVWinDrawTitle(CRVWin *w)
{
  //Stamp title onto the top border row (classic TempleOS chrome).
  I64 x, i, len, attr, max;
  if (!w->title[0] || w->no_border)
    return;
  len = StrLen(w->title);
  max = w->right - w->left + 1;
  if (max < 1)
    return;
  if (len > max)
    len = max;
  x = w->left + (max - len) / 2;
  attr = w->border_attr << 4 + YELLOW;
  for (i = 0; i < len; i++)
    RVTextChar(x + i, w->top - 1, (w->title[i] & 255) + (attr << 8));
}

U0 RVWinDrawBody(CRVWin *w)
{
  //Plot body text. Doc-lite: $$0-$$F FG; $$$$ → literal $$; $$B0-$$BF BG.
  I64 x, y, i, attr, ch, fg, bg, n;
  if (!w->body[0])
    return;
  attr = w->text_attr;
  fg = attr & 15;
  bg = (attr >> 4) & 15;
  x = 0;
  y = 0;
  for (i = 0; w->body[i]; i++) {
    ch = w->body[i];
    if (ch == '$' && w->body[i + 1]) {
      n = w->body[i + 1];
      if (n == '$') {
        i++;
        ch = '$';
      }
      // $$ → one '$'
      else if ((n == 'B' || n == 'b') && w->body[i + 2])
      {
        n = w->body[i + 2];
        if (n >= '0' && n <= '9') {
          bg = n - '0';
          i += 2;
          attr = bg << 4 + fg;
          continue;
        }
        if (n >= 'A' && n <= 'F') {
          bg = 10 + n - 'A';
          i += 2;
          attr = bg << 4 + fg;
          continue;
        }
        if (n >= 'a' && n <= 'f') {
          bg = 10 + n - 'a';
          i += 2;
          attr = bg << 4 + fg;
          continue;
        }
      }
      else if(n >= '0' && n <= '9')
      {
        fg = n - '0';
        i++;
        attr = bg << 4 + fg;
        continue;
      }
      else if(n >= 'A' && n <= 'F')
      {
        fg = 10 + n - 'A';
        i++;
        attr = bg << 4 + fg;
        continue;
      }
      else if(n >= 'a' && n <= 'f')
      {
        fg = 10 + n - 'a';
        i++;
        attr = bg << 4 + fg;
        continue;
      }
    }
    if (ch == '\n') {
      x = 0;
      y++;
      continue;
    }
    if (y > w->bottom - w->top)
      break;
    if (x <= w->right - w->left)
      RVTextChar(w->left + x, w->top + y, (ch & 255) + (attr << 8));
    x++;
  }
}

U0 RVWinMgrComposeWins()
{
  //Z-order: lower indices first; focused window last (on top).
  I64 i, z, pass;
  CRVWin *w;
  z = 1;
  // Two passes: unfocused then focused (matches WinMgr stacking intent).
  for (pass = 0; pass < 2; pass++) {
    for (i = 0; i < RV_WIN_MAX; i++) {
      w = &rv_winmgr.wins[i];
      if (!w->used || !w->show)
        continue;
      if (pass == 0 && w->focused)
        continue;
      if (pass == 1 && !w->focused)
        continue;
      w->z = z++;
      if (!w->no_border)
        RVTextBorder(w->left, w->right, w->top, w->bottom, w->border_attr, w->focused);
      RVTextRect(w->left, w->right, w->top, w->bottom, w->text_attr << 8 + ' ');
      RVWinDrawTitle(w);
      RVWinDrawBody(w);
    }
  }
}

U0 RVWinMgrBlitTextBase()
{
  //Render text_base glyphs into 32-bpp rv_fb (GrUpdateTextBG+FG portable).
  I64 row, col, px, py, gy, gx, ch, fg, bg, cell;
  U8 *glyph;
  U32 *pix, fgc, bgc;
  I64 cols = rv_winmgr.cols, rows = rv_winmgr.rows;
  I64 stride = rv_fb.width;
  if (!rv_fb.pixels || !rv_winmgr.text_base)
    return;
  pix = rv_fb.pixels;
  for (row = 0; row < rows; row++) {
    for (col = 0; col < cols; col++) {
      cell = rv_winmgr.text_base[row *cols + col];
      ch = cell & 255;
      fg = (cell >> 8) & 15;
      bg = (cell >> 12) & 15;
      if (cell & ATTRF_INVERT) {
        ch = fg;
        fg = bg;
        bg = ch;
        // reuse ch as tmp (glyph index reloaded below)
        ch = cell & 255;
      }
      if (cell & ATTRF_SEL) {
        fg ^= 15;
        bg ^= 15;
      }
      fgc = RVColor(fg);
      bgc = RVColor(bg);
      px = col *FONT_WIDTH;
      py = row *FONT_HEIGHT;
      glyph = (&sys_font_std[ch])(U8 *);
      for (gy = 0; gy < FONT_HEIGHT; gy++) {
        U8 bits = glyph[gy];
        I64 dy = (py + gy) * stride + px;
        for (gx = 0; gx < FONT_WIDTH; gx++) {
          if (bits & (0x80 >> gx))
            pix[dy + gx] = fgc;
          else
            pix[dy + gx] = bgc;
        }
      }
    }
  }
  // Clear any leftover FB margin beyond the text grid.
  for (py = rows *FONT_HEIGHT; py < rv_fb.height; py++)
    for (px = 0; px < rv_fb.width; px++)
      pix[py *stride + px] = RVColor(BLUE);
  for (py = 0; py < rows *FONT_HEIGHT; py++)
    for (px = cols *FONT_WIDTH; px < rv_fb.width; px++)
      pix[py *stride + px] = RVColor(BLUE);
}

U0 RVWinMgrDrawIts()
{
  //Run optional draw_it callbacks with a DC clipped conceptually to client pixels.
  I64 i;
  CRVWin *w;
  CRVDC *dc = rv_gr.dc;
  if (!dc)
    return;
  for (i = 0; i < RV_WIN_MAX; i++) {
    w = &rv_winmgr.wins[i];
    if (!w->used || !w->show || !w->draw_it)
      continue;
    // draw_it receives the window; callers use win pixel origin via left/top*FONT_*.
    (*w->draw_it)(w, dc);
  }
}

U0 RVWinMgrRefresh()
{
  //Full frame: wallpaper → windows → blit text_base → draw_it → present.
  if (!rv_winmgr.ready || !rv_fb.pixels)
    return;
  RVWinMgrWallPaper;
  RVWinMgrComposeWins;
  RVWinMgrBlitTextBase;
  RVWinMgrDrawIts;
  RVFbPresent;
  rv_winmgr.updates++;
}

I64 RVWinNew(I64 left, I64 right, I64 top, I64 bottom, U8 *title = NULL, U8 *body = NULL, Bool focus = FALSE)
{
  //Convenience: alloc + geometry + chrome. Returns window index or -1.
  I64 idx = RVWinAlloc;
  CRVWin *w;
  if (idx < 0)
    return -1;
  w = &rv_winmgr.wins[idx];
  // Client must leave room for a 1-cell border (TempleOS convention).
  if (left < 1)
    left = 1;
  if (top < 1)
    top = 1;
  if (right > rv_winmgr.cols - 2)
    right = rv_winmgr.cols - 2;
  if (bottom > rv_winmgr.rows - 2)
    bottom = rv_winmgr.rows - 2;
  RVWinHorz(idx, left, right);
  RVWinVert(idx, top, bottom);
  if (title)
    RVWinSetTitle(idx, title);
  if (body)
    RVWinSetBody(idx, body);
  if (focus)
    RVWinFocus(idx);
  return idx;
}

U0 RVWinDrawItDemo(CRVWin *w, CRVDC *dc)
{
  //Sample draw_it: colored bars inside the client pixel rect.
  I64 x0 = w->left *FONT_WIDTH;
  I64 y0 = w->top *FONT_HEIGHT;
  I64 ww = (w->right - w->left + 1) * FONT_WIDTH;
  I64 hh = (w->bottom - w->top + 1) * FONT_HEIGHT;
  // Leave room for a couple of text lines at the top of the client.
  y0 += FONT_HEIGHT * 3;
  hh -= FONT_HEIGHT * 3;
  if (hh < 8 || ww < 8)
    return;
  dc->color = RVColor(RED);
  GrRect(dc, x0 + 4, y0, ww / 3, hh / 2);
  dc->color = RVColor(GREEN);
  GrRect(dc, x0 + 4 + ww / 3, y0 + hh / 4, ww / 3, hh / 2);
  dc->color = RVColor(LTBLUE);
  GrRect(dc, x0 + 4 + 2 * ww / 3, y0 + hh / 2, ww / 3 - 8, hh / 2 - 4);
}

Bool RVWinMgrDemoDesktop()
{
  //Two recognizably TempleOS windows on the wallpaper. Call after RVWinMgrInit.
  I64 a, b;
  if (!rv_winmgr.ready)
    return FALSE;
  a = RVWinNew(2, 38, 2, 16, "Adam", "HolyC ready.\n\n> Dir;\n> Ed(\"Demo\");\n", TRUE);
  if (a >= 0) {
    rv_winmgr.wins[a].border_attr = RED;
    rv_winmgr.wins[a].text_attr = BLUE << 4 + WHITE;
  }
  b = RVWinNew(42, rv_winmgr.cols - 3, 4, 22, "Demo/Graphics", "draw_it() client\n", FALSE);
  if (b >= 0) {
    rv_winmgr.wins[b].border_attr = BLUE;
    rv_winmgr.wins[b].text_attr = BLACK << 4 + WHITE;
    rv_winmgr.wins[b].draw_it = &RVWinDrawItDemo;
  }
  RVWinFocus(a);
  return a >= 0 && b >= 0;
}

Bool RVSysWinInit()
{
  //Boot helper: Gr + WinMgr + demo desktop when a present backend exists.
  // Returns FALSE under UART-only -nographic (same gate as RVSysGrInit).
  if (!RVSysGrInit())
    return FALSE;
  // RVSysGrInit already painted soft term; replace with windowed desktop.
  if (!RVWinMgrInit())
    return FALSE;
  RVWinMgrDemoDesktop;
  RVWinMgrRefresh;
  Print("RVSysWinInit: WinMgr desktop wins=%d focus=%d %dx%d text=%dx%d\n", rv_winmgr.n_wins, rv_winmgr.focus, rv_fb.width, rv_fb.height, rv_winmgr.cols, rv_winmgr.rows);
  return TRUE;
}
