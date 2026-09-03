// TempleOS-style window manager on native 32-bpp FB (Phase F).
//
// Faithful subset of Adam WinMgr / GrScrn text path — NOT VGA:
//   - U32 text_base cells (ASCII + 4-bit FG/BG, same layout as Doc/TextBase.DD)
//   - TextBorder / TextRect / TextPrint into text_base (portable HolyC, no x86 asm)
//   - Z-ordered task windows with borders + titles
//   - Render text_base → rv_fb (XRGB8888) then RVFbPresent
//
// Gaps vs full Adam: no full DolDoc entries/ODE, no 8-bit CDC blot /
// GrUpdateVGAGraphics. DocTerm-lite (P4): DocTermNew → Term + Put/Display/Border
// docs + HOME.DD; WinMgrTask pumps input/refresh (Spawn via RVKSpawn when live).
// Input: VirtioInput → click-to-focus + type into focused body (Phase F.1).
// UART dig-down: RVWinSerial (included after this file) — forward decls for pump.
U0 RVWinSerialPoll();
Bool RVWinSerialInit();
#define RV_WIN_MAX       8
#define RV_WIN_TITLE_MAX 48
#define RV_WIN_BODY_MAX  1024
#define EV_SYN  0
#define EV_KEY  1
#define EV_REL  2
#define EV_ABS  3
#define KEY_LEFTSHIFT  42
#define KEY_RIGHTSHIFT 54
#define KEY_LEFTCTRL   29
#define KEY_ESC        1
#define KEY_TAB        15
#define BTN_LEFT       0x110
#define ABS_X          0
#define ABS_Y          1
#define REL_X          0
#define REL_Y          1
#define RV_CURSOR_W    17
#define RV_CURSOR_H    17
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
  // Doc-lite text; $$0-$$F FG, $$Bn BG, $$FG,/$$BG,/$$TX,"…"$$ (not full DolDoc)
  U0 (*draw_it)(CRVWin *w, CRVDC *dc);
  // optional pixel draw in client
};

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
  // BG<<4|FG (text cells)
  U32 wallpaper_bg;
  // XRGB desktop fill beyond text grid + margin bands
  U8 wallpaper_line[96];
  I64 n_wins;
  CRVWin wins[RV_WIN_MAX];
  I64 focus;
  // index into wins[], or -1
  I64 term_idx;
  // DocTermNew window, or -1
  I64 home_idx;
  // HOME.DD / Doc-lite file window, or -1
  I64 updates;
  // Pointer in text cells (from virtio ABS tablet or REL mouse)
  I64 ptr_x;
  I64 ptr_y;
  I64 ptr_ox;
  // last cursor hot-spot in pixels (save-under)
  I64 ptr_oy;
  U32 ptr_save[RV_CURSOR_W *RV_CURSOR_H];
  Bool ptr_save_valid;
  Bool shift;
  Bool input_ok;
  // VirtioInputInit succeeded
  I64 input_events;
  Bool want_quit;
  // ESC sets this for interactive run loops
};
CRVWinMgrGlbls rv_winmgr;
// Static fallback text_base (800×600 = 100×75 cells). Larger FBs use MAlloc in RVWinMgrInit.
#define RV_TEXT_BASE_STORE_CELLS (100 * 75)
U32 rv_text_base_store[RV_TEXT_BASE_STORE_CELLS];
// DocTerm-lite Put/Display/Border (TempleOS DocDblBuf names; not full DolDoc).
CDoc rv_doc_put;
CDoc rv_doc_display;
CDoc rv_doc_border;
I64 rv_winmgr_task_iters;
I64 RVWinBodyLen(U8 *body)
{
  //Bounded StrLen for window bodies — stale/corrupt data must not walk past body[].
  I64 i;
  if (!body)
    return 0;
  for (i = 0; i < RV_WIN_BODY_MAX && body[i]; i++)
    ;
  return i;
}

I64 RVWinBodyLineLen(U8 *body, I64 end)
{
  //Plain-text chars since the previous '\n' (doc-lite escapes are not expanded here).
  I64 i = end;
  while (i > 0 && body[i - 1] != '\n')
    i--;
  return end - i;
}

U0 RVWinMgrBorderCharsInit()
{
  //Match Kernel/KMain.HC SysGrInit graphics-mode border_chars.
  rv_winmgr.border_chars[2](I64) = 0x0908070605040302;
  rv_winmgr.border_chars[10](U32) = 0x0D0C0B0A;
}

U0 RVDocLiteInitOne(CDoc *doc, U64 desc)
{
  //Stamp DOC_SIGNATURE_VAL so DocPut/DocDisplay/DocBorder succeed.
  if (!doc)
    return;
  MemSet(doc, 0, sizeof(CDoc));
  doc->doc_signature = DOC_SIGNATURE_VAL;
  doc->desc = desc;
  doc->win_task = Fs;
  doc->mem_task = Fs;
  doc->owning_task = Fs;
  doc->max_entries = 4096;
}

U0 RVDocTermDocsInit()
{
  //Wire Fs put/display/border docs (Adam DocTermNew shape, Doc-lite bodies).
  RVDocLiteInitOne(&rv_doc_put, 'Term');
  RVDocLiteInitOne(&rv_doc_display, 'Term');
  RVDocLiteInitOne(&rv_doc_border, 'Border');
  rv_doc_border.flags = DOCF_BORDER_DOC;
  if (Fs) {
    Fs->put_doc = &rv_doc_put;
    Fs->display_doc = &rv_doc_display;
    Fs->border_doc = &rv_doc_border;
    Fs->border_src = BDS_CUR_DRV;
  }
}

public CDoc *DocPut(CTask *task = NULL)
{
  //Current StdOut Put doc (Doc-lite). Matches Adam/DolDoc/DocDblBuf.HC.
  CDoc *res;
  if (!task)
    task = Fs;
  if (!task)
    return NULL;
  if ((res = task->put_doc) && res->doc_signature == DOC_SIGNATURE_VAL)
    return res;
  return NULL;
}

public CDoc *DocDisplay(CTask *task = NULL)
{
  //Displayed StdOut doc (Doc-lite; same as Put until double-buffer lands).
  CDoc *res;
  if (!task)
    task = Fs;
  if (!task)
    return NULL;
  if ((res = task->display_doc) && res->doc_signature == DOC_SIGNATURE_VAL)
    return res;
  return NULL;
}

public CDoc *DocBorder(CTask *task = NULL)
{
  //Border chrome doc (Doc-lite).
  CDoc *res;
  if (!task)
    task = Fs;
  if (!task)
    return NULL;
  if ((res = task->border_doc) && res->doc_signature == DOC_SIGNATURE_VAL)
    return res;
  return NULL;
}

U0 RVDocPutS(U8 *st)
{
  //Append plain text into the focused Term body (DocPrint / typing path).
  I64 idx, len, i, n;
  CRVWin *w;
  if (!st || !rv_winmgr.ready)
    return;
  idx = rv_winmgr.term_idx;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    idx = rv_winmgr.focus;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    return;
  w = &rv_winmgr.wins[idx];
  len = RVWinBodyLen(w->body);
  n = StrLen(st);
  for (i = 0; i < n && len < RV_WIN_BODY_MAX - 1; i++) {
    w->body[len] = st[i];
    len++;
  }
  w->body[len] = 0;
}

Bool RVWinMgrInit()
{
  //Requires RVGrInit / live rv_fb. Sets up text grid + empty window list.
  I64 cols, rows;
  if (!rv_fb.pixels || !rv_gr.dc)
    return FALSE;
  cols = rv_fb.width / FONT_WIDTH;
  rows = rv_fb.height / FONT_HEIGHT;
  I64 cells;
  if (cols < 20 || rows < 10)
    return FALSE;
  cells = cols *rows;
  MemSet(&rv_winmgr, 0, sizeof(CRVWinMgrGlbls));
  rv_winmgr.cols = cols;
  rv_winmgr.rows = rows;
  if (cells <= RV_TEXT_BASE_STORE_CELLS)
    rv_winmgr.text_base = rv_text_base_store;
  else {
    rv_winmgr.text_base = MAlloc(cells *sizeof(U32));
    if (!rv_winmgr.text_base)
      return FALSE;
  }
  MemSet(rv_winmgr.text_base, 0, cells *sizeof(U32));
  RVWinMgrBorderCharsInit;
  rv_winmgr.wallpaper_attr = BLUE << 4 + WHITE;
  rv_winmgr.wallpaper_bg = RV_RGB(32, 64, 128);
  StrCpy(rv_winmgr.wallpaper_line, "TempleOS/RISC-V  WinMgr on 32-bpp FB");
  rv_winmgr.focus = -1;
  rv_winmgr.term_idx = -1;
  rv_winmgr.home_idx = -1;
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
  RVTextPrint(1, rv_winmgr.rows - 1, BLUE << 4 + LTGRAY, "RVWinMgr  DocTerm Put/Border  $$0-F $$Bn $$FG, $$TX,\"\"$$");
}

U0 RVWinDrawTitle(CRVWin *w)
{
  //Stamp title onto the top border row (classic TempleOS chrome).
  // Focused windows with a border doc get a lite "[X]" closer cue.
  I64 x, i, len, attr, max, extra;
  U8 title_buf[RV_WIN_TITLE_MAX];
  if (!w->title[0] || w->no_border)
    return;
  StrCpy(title_buf, w->title);
  if (w->focused && DocBorder()) {
    extra = StrLen(title_buf);
    if (extra + 4 < RV_WIN_TITLE_MAX)
      StrCpy(title_buf + extra, " [X]");
  }
  len = StrLen(title_buf);
  max = w->right - w->left + 1;
  if (max < 1)
    return;
  if (len > max)
    len = max;
  x = w->left + (max - len) / 2;
  attr = w->border_attr << 4 + YELLOW;
  for (i = 0; i < len; i++)
    RVTextChar(x + i, w->top - 1, (title_buf[i] & 255) + (attr << 8));
}

I64 RVDocLiteNibble(I64 ch)
{
  //Parse one hex nibble; -1 if not 0-9/A-F/a-f.
  if (ch >= '0' && ch <= '9')
    return ch - '0';
  if (ch >= 'A' && ch <= 'F')
    return 10 + ch - 'A';
  if (ch >= 'a' && ch <= 'f')
    return 10 + ch - 'a';
  return -1;
}

I64 RVDocLiteSkipToDollar(U8 *body, I64 i)
{
  //Skip an unknown $cmd…$ (HolyC $$…$$ → $…$ in memory). Returns index past closer.
  while (i < RV_WIN_BODY_MAX && body[i] && body[i] != '$')
    i++;
  if (i < RV_WIN_BODY_MAX && body[i] == '$')
    i++;
  return i;
}

I64 RVDocLiteParseColor(U8 *body, I64 i, I64 *out)
{
  //After $FG, or $BG, — hex nibble or decimal; consume through closing $.
  I64 v = 0, n, start = i;
  while (i < RV_WIN_BODY_MAX && body[i] == ' ')
    i++;
  n = RVDocLiteNibble(body[i]);
  if (n >= 0 && (body[i + 1] == '$' || body[i + 1] == ' ' || !body[i + 1] || body[i + 1] == ',')) {
    v = n;
    i++;
  } else if (body[i] >= '0' && body[i] <= '9') {
    while (i < RV_WIN_BODY_MAX && body[i] >= '0' && body[i] <= '9') {
      v = v * 10 + body[i] - '0';
      i++;
    }
  } else
    return RVDocLiteSkipToDollar(body, start);
  *out = v & 15;
  return RVDocLiteSkipToDollar(body, i);
}

U0 RVWinDrawBody(CRVWin *w)
{
  //Plot body text. Doc-lite (P4) — HolyC $$ in source → one '$' in memory:
  //  $0-$F / $a-$f   FG nibble (MakeAdam style)
  //  $B0-$BF         BG nibble
  //  $$              literal '$' ($$$$ in HolyC source)
  //  $FG,n$ / $BG,n$ color with closer
  //  $TX,"text"$     emit quoted text; unknown $cmd$ soft-skipped
  I64 x, y, i, attr, ch, fg, bg, n, j;
  if (!w->body[0])
    return;
  attr = w->text_attr;
  fg = attr & 15;
  bg = (attr >> 4) & 15;
  x = 0;
  y = 0;
  for (i = 0; i < RV_WIN_BODY_MAX && w->body[i];) {
    ch = w->body[i];
    if (ch == '$' && i + 1 < RV_WIN_BODY_MAX && w->body[i + 1]) {
      n = w->body[i + 1];
      if (n == '$') {
        i += 2;
        ch = '$';
      } else if ((n == 'F' || n == 'f') && w->body[i + 2] == 'G' && w->body[i + 3] == ',') {
        i = RVDocLiteParseColor(w->body, i + 4, &fg);
        attr = bg << 4 + fg;
        continue;
      } else if ((n == 'B' || n == 'b') && w->body[i + 2] == 'G' && w->body[i + 3] == ',') {
        i = RVDocLiteParseColor(w->body, i + 4, &bg);
        attr = bg << 4 + fg;
        continue;
      } else if ((n == 'T' || n == 't') && (w->body[i + 2] == 'X' || w->body[i + 2] == 'x') && w->body[i + 3] == ',') {
        i += 4;
        while (w->body[i] == ' ')
          i++;
        if (w->body[i] == '"') {
          i++;
          while (i < RV_WIN_BODY_MAX && w->body[i] && w->body[i] != '"') {
            ch = w->body[i++];
            if (ch == '\n') {
              x = 0;
              y++;
            } else {
              if (x > w->right - w->left) {
                x = 0;
                y++;
              }
              if (y <= w->bottom - w->top && x <= w->right - w->left)
                RVTextChar(w->left + x, w->top + y, (ch & 255) + (attr << 8));
              x++;
            }
          }
          if (i < RV_WIN_BODY_MAX && w->body[i] == '"')
            i++;
        }
        i = RVDocLiteSkipToDollar(w->body, i);
        continue;
      } else if ((n == 'B' || n == 'b') && (j = RVDocLiteNibble(w->body[i + 2])) >= 0) {
        bg = j;
        i += 3;
        attr = bg << 4 + fg;
        continue;
      } else if ((j = RVDocLiteNibble(n)) >= 0) {
        fg = j;
        i += 2;
        attr = bg << 4 + fg;
        continue;
      } else if ((n >= 'A' && n <= 'Z') || (n >= 'a' && n <= 'z')) {
        // Unknown $CMD…$ — soft-skip so richer .DD does not dump garbage.
        i = RVDocLiteSkipToDollar(w->body, i + 1);
        continue;
      } else {
        i++;
        continue;
      }
    } else
      i++;
    if (ch == '\n') {
      x = 0;
      y++;
      continue;
    }
    if (y > w->bottom - w->top)
      break;
    if (x > w->right - w->left) {
      x = 0;
      y++;
      if (y > w->bottom - w->top)
        break;
    }
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
          if (bits & (1 << gx))
            pix[dy + gx] = fgc;
          else
            pix[dy + gx] = bgc;
        }
      }
    }
  }
  // Clear any leftover FB margin beyond the text grid.
  U32 margin = rv_winmgr.wallpaper_bg;
  for (py = rows *FONT_HEIGHT; py < rv_fb.height; py++)
    for (px = 0; px < rv_fb.width; px++)
      pix[py *stride + px] = margin;
  for (py = 0; py < rows *FONT_HEIGHT; py++)
    for (px = cols *FONT_WIDTH; px < rv_fb.width; px++)
      pix[py *stride + px] = margin;
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

U0 RVWinMgrPresent(Bool full_frame = FALSE)
{
  //ramfb: configure once (RVFbPresentRamfb); later presents are no-ops so cocoa stays alive.
  no_warn full_frame;
  if (!rv_fb.pixels)
    return;
  RVFbPresent();
}

U0 RVWinMgrCursorErase()
{
  I64 row, col, px, py, stride;
  U32 *pix, *save;
  if (!rv_winmgr.ptr_save_valid || !rv_fb.pixels)
    return;
  stride = RVFbPixStride();
  pix = rv_fb.pixels;
  save = rv_winmgr.ptr_save;
  for (row = 0; row < RV_CURSOR_H; row++) {
    py = rv_winmgr.ptr_oy + row;
    if (py < 0 || py >= rv_fb.height)
      continue;
    for (col = 0; col < RV_CURSOR_W; col++) {
      px = rv_winmgr.ptr_ox + col;
      if (px < 0 || px >= rv_fb.width)
        continue;
      pix[py *stride + px] = save[row *RV_CURSOR_W + col];
    }
  }
  rv_winmgr.ptr_save_valid = FALSE;
}

U0 RVWinMgrCursorSaveUnder(I64 px, I64 py)
{
  I64 row, col, x, y, stride;
  U32 *pix, *save;
  if (!rv_fb.pixels)
    return;
  stride = RVFbPixStride();
  pix = rv_fb.pixels;
  save = rv_winmgr.ptr_save;
  rv_winmgr.ptr_ox = px;
  rv_winmgr.ptr_oy = py;
  for (row = 0; row < RV_CURSOR_H; row++) {
    y = py + row;
    for (col = 0; col < RV_CURSOR_W; col++) {
      x = px + col;
      if (x < 0 || y < 0 || x >= rv_fb.width || y >= rv_fb.height)
        save[row *RV_CURSOR_W + col] = RVColor(BLUE);
      else
        save[row *RV_CURSOR_W + col] = pix[y *stride + x];
    }
  }
  rv_winmgr.ptr_save_valid = TRUE;
}

U0 RVWinMgrDrawCursorAt(I64 px, I64 py)
{
  //16×16 arrow; MSB of each U16 row is the leftmost pixel (TempleOS DrawStdMs / GrArrow tip).
  // 8×8 sys_font_std glyphs use LSB-first — do not mix conventions on the same row width.
  static U16 arrow[16] = {0x4000, 0x6000, 0x7000, 0x7800, 0x7C00, 0x7E00, 0x7F00, 0x7F80, 0x7FC0, 0x7F00, 0x7E00, 0x6C00, 0x6C00, 0x4800, 0x4800, 0x0000};
  I64 row, col, x, y;
  U32 fg, bg, save;
  CRVDC *dc;
  U16 bits;
  if (!rv_winmgr.ready || !rv_winmgr.input_ok || !rv_fb.pixels)
    return;
  dc = rv_gr.dc;
  if (!dc || !dc->body)
    return;
  fg = RVColor(WHITE);
  bg = RVColor(BLACK);
  save = dc->color;
  for (row = 0; row < 16; row++) {
    bits = arrow[row];
    for (col = 0; col < 16; col++) {
      if (!(bits & (0x8000 >> col)))
        continue;
      x = px + col;
      y = py + row;
      if (x < 0 || y < 0 || x >= rv_fb.width || y >= rv_fb.height)
        continue;
      RVFbPutPixel(x, y, fg);
      if (x + 1 < rv_fb.width)
        RVFbPutPixel(x + 1, y, bg);
      if (y + 1 < rv_fb.height)
        RVFbPutPixel(x, y + 1, bg);
    }
  }
  dc->color = save;
}

U0 RVWinMgrDrawCursor()
{
  I64 px, py;
  if (!rv_winmgr.ready || !rv_winmgr.input_ok)
    return;
  px = rv_winmgr.ptr_x *FONT_WIDTH;
  py = rv_winmgr.ptr_y *FONT_HEIGHT;
  RVWinMgrDrawCursorAt(px, py);
}

U0 RVWinMgrCursorUpdate()
{
  //Pointer-only repaint: restore save-under, save, draw cursor (skip full text blit).
  I64 px, py;
  if (!rv_winmgr.ready || !rv_winmgr.input_ok || !rv_fb.pixels)
    return;
  if (rv_winmgr.ptr_x < 0)
    rv_winmgr.ptr_x = 0;
  if (rv_winmgr.ptr_y < 0)
    rv_winmgr.ptr_y = 0;
  if (rv_winmgr.ptr_x >= rv_winmgr.cols)
    rv_winmgr.ptr_x = rv_winmgr.cols - 1;
  if (rv_winmgr.ptr_y >= rv_winmgr.rows)
    rv_winmgr.ptr_y = rv_winmgr.rows - 1;
  px = rv_winmgr.ptr_x *FONT_WIDTH;
  py = rv_winmgr.ptr_y *FONT_HEIGHT;
  RVWinMgrCursorErase;
  RVWinMgrCursorSaveUnder(px, py);
  RVWinMgrDrawCursorAt(px, py);
  RVWinMgrPresent(FALSE);
}

U0 RVWinMgrRefresh()
{
  //Full frame: wallpaper → windows → blit text_base → draw_it → cursor → present.
  I64 px, py;
  if (!rv_winmgr.ready || !rv_fb.pixels)
    return;
  RVWinMgrWallPaper;
  RVWinMgrComposeWins;
  RVWinMgrBlitTextBase;
  RVWinMgrDrawIts;
  rv_winmgr.ptr_save_valid = FALSE;
  if (rv_winmgr.input_ok) {
    px = rv_winmgr.ptr_x *FONT_WIDTH;
    py = rv_winmgr.ptr_y *FONT_HEIGHT;
    RVWinMgrCursorSaveUnder(px, py);
    RVWinMgrDrawCursorAt(px, py);
  }
  RVWinMgrPresent(TRUE);
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
  dc->color = RV_RGB(220, 48, 48);
  GrRect(dc, x0 + 4, y0, ww / 3, hh / 2);
  dc->color = RV_RGB(48, 200, 72);
  GrRect(dc, x0 + 4 + ww / 3, y0 + hh / 4, ww / 3, hh / 2);
  dc->color = RV_RGB(72, 144, 255);
  GrRect(dc, x0 + 4 + 2 * ww / 3, y0 + hh / 2, ww / 3 - 8, hh / 2 - 4);
}

I64 RVDocFindByTitle(U8 *title)
{
  I64 i;
  if (!title)
    return -1;
  for (i = 0; i < RV_WIN_MAX; i++) {
    if (rv_winmgr.wins[i].used && !StrCmp(rv_winmgr.wins[i].title, title))
      return i;
  }
  return -1;
}

Bool RVDocLoadWin(I64 idx, U8 *path)
{
  //FileRead path into window body (Doc-lite). Returns FALSE if missing/empty/no FS.
  U8 *buf;
  I64 sz = 0;
  if (idx < 0 || idx >= RV_WIN_MAX || !path)
    return FALSE;
  if (!rv_winmgr.wins[idx].used)
    return FALSE;
  // Win smokes may paint DocTerm before RedSea/Adam exists — do not FileRead then.
  if (!Fs || !Fs->cur_dv)
    return FALSE;
  buf = FileRead(path, &sz, NULL);
  if (!buf || sz <= 0)
    return FALSE;
  RVWinSetBody(idx, buf);
  return TRUE;
}

I64 RVDocHomeOpen(U8 *fallback = NULL)
{
  //Open/focus HOME.DD window; load A:/Adam/HOME.DD when RedSea has it.
  I64 idx, left, right, top, bottom;
  U8 *body;
  if (!rv_winmgr.ready)
    return -1;
  idx = rv_winmgr.home_idx;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    idx = RVDocFindByTitle("HOME.DD");
  if (idx < 0) {
    left = 2;
    right = rv_winmgr.cols - 3;
    top = rv_winmgr.rows / 2;
    bottom = rv_winmgr.rows - 3;
    if (top < 16)
      top = 16;
    if (bottom <= top)
      bottom = top + 6;
    idx = RVWinNew(left, right, top, bottom, "HOME.DD", "", FALSE);
  }
  if (idx < 0)
    return -1;
  rv_winmgr.home_idx = idx;
  rv_winmgr.wins[idx].border_attr = GREEN;
  rv_winmgr.wins[idx].text_attr = BLACK << 4 + WHITE;
  if (!RVDocLoadWin(idx, "A:/Adam/HOME.DD")) {
    body = fallback;
    if (!body)
      body = "$$EHOME.DD\n$$F(no A:/Adam/HOME.DD yet)\n$$3Run MakeAdam_RV_Core / StartOS\n";
    RVWinSetBody(idx, body);
  }
  RVWinSetTitle(idx, "HOME.DD");
  return idx;
}

public U0 DocTermNew()
{
  //TempleOS-shaped DocTermNew (P4): Term window + Put/Display/Border docs.
  // Full DolDoc entry lists remain open; this is the FB WinMgr path.
  I64 idx, left, right, top, bottom;
  U8 *body;
  if (!rv_winmgr.ready)
    return;
  RVDocTermDocsInit;
  idx = rv_winmgr.term_idx;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    idx = RVDocFindByTitle("Term");
  if (idx < 0) {
    left = 38;
    right = rv_winmgr.cols - 3;
    if (left >= right - 8)
      left = rv_winmgr.cols / 2;
    top = 2;
    bottom = rv_winmgr.rows / 2 - 1;
    if (bottom < top + 6)
      bottom = top + 10;
    body = "$$ETempleOS/RISC-V DocTerm\n" "$$FTab=focus  $$3click=select  $$Atype here\n" "$$FG,14$$$$TX,\"DocTerm Put/Display/Border\"$$$$FG,7$$\n" "> \n";
    idx = RVWinNew(left, right, top, bottom, "Term", body, TRUE);
  }
  if (idx < 0)
    return;
  rv_winmgr.term_idx = idx;
  rv_winmgr.wins[idx].border_attr = LTGREEN;
  rv_winmgr.wins[idx].text_attr = BLUE << 4 + WHITE;
  if (!rv_winmgr.wins[idx].body[0])
    RVWinSetBody(idx, "$$ETempleOS/RISC-V DocTerm\n" "$$Ftype into this window\n" "> \n");
  RVWinSetTitle(idx, "Term");
  RVWinFocus(idx);
  if (rv_doc_put.doc_signature == DOC_SIGNATURE_VAL)
    rv_doc_put.user_data = idx;
}

Bool RVWinMgrDemoDesktop()
{
  //DocTerm-lite desktop: Adam + Term (DocTermNew) + HOME.DD. Call after RVWinMgrInit.
  I64 a, h;
  U8 *home_fallback;
  if (!rv_winmgr.ready)
    return FALSE;
  a = RVWinNew(2, 36, 2, 14, "Adam", "$$ETempleOS/RISC-V StartOS\n" "$$FMakeAdam_RV_Core / DocTerm-lite\n" "$$FG,3$$Tab/click focus$$FG,7$$\n" "$$AType into Term (virtio-kbd)\n" "> Ed(\"A:/Adam/HOME.DD\");\n", FALSE);
  if (a >= 0) {
    rv_winmgr.wins[a].border_attr = RED;
    rv_winmgr.wins[a].text_attr = BLUE << 4 + WHITE;
  }
  DocTermNew;
  home_fallback = "$$ETempleOS/RISC-V Adam\n" "$$FMakeAdam_RV_Core on FB WinMgr\n" "$$BGuest Cmp MakeOS  $$3StartOS_RV\n" "$$TX,\"A:/Adam/HOME.DD\"$$\n" "$$AA:/Adam  $$7A:/MakeOS  $$BA:/Compiler\n";
  h = RVDocHomeOpen(home_fallback);
  if (a >= 0)
    RVWinFocus(a);
  return a >= 0 && rv_winmgr.term_idx >= 0 && h >= 0;
}

I64 RVWinHitTest(I64 cx, I64 cy)
{
  //Topmost window under text cell (cx,cy), including border. -1 if none.
  I64 i, best = -1, best_z = -1;
  CRVWin *w;
  I64 l, r, t, b;
  for (i = 0; i < RV_WIN_MAX; i++) {
    w = &rv_winmgr.wins[i];
    if (!w->used || !w->show)
      continue;
    l = w->left;
    r = w->right;
    t = w->top;
    b = w->bottom;
    if (!w->no_border) {
      l--;
      r++;
      t--;
      b++;
    }
    if (cx < l || cx > r || cy < t || cy > b)
      continue;
    if (w->z >= best_z) {
      best_z = w->z;
      best = i;
    }
  }
  return best;
}

U0 RVWinFocusNext()
{
  //Tab: cycle focus among used windows.
  I64 i, start, n = RV_WIN_MAX;
  if (rv_winmgr.focus < 0)
    start = 0;
  else
    start = rv_winmgr.focus + 1;
  for (i = 0; i < n; i++) {
    I64 idx = (start + i) % n;
    if (rv_winmgr.wins[idx].used && rv_winmgr.wins[idx].show) {
      RVWinFocus(idx);
      return;
    }
  }
}

U0 RVWinBodyPutChar(I64 ch)
{
  //Append/backspace into focused window body (Doc-lite string).
  CRVWin *w;
  I64 len;
  if (rv_winmgr.focus < 0)
    return;
  w = &rv_winmgr.wins[rv_winmgr.focus];
  if (!w->used)
    return;
  len = RVWinBodyLen(w->body);
  if (ch == 8) {
    // backspace
    if (len > 0)
      w->body[len - 1] = 0;
    return;
  }
  if (ch == '\t') {
    RVWinFocusNext;
    return;
  }
  if (len >= RV_WIN_BODY_MAX - 1)
    return;
  if (ch == '\n' || ch >= 32 && ch < 127) {
    I64 wwid = w->right - w->left + 1;
    if (ch >= 32 && ch < 127 && wwid > 0 && RVWinBodyLineLen(w->body, len) >= wwid) {
      if (len + 1 >= RV_WIN_BODY_MAX - 1)
        return;
      w->body[len] = '\n';
      len++;
    }
    w->body[len] = ch;
    w->body[len + 1] = 0;
  }
}

Bool RVWinMgrInputInit()
{
  //Optional: bring up virtio-keyboard / tablet for WinMgr grab.
  if (VirtioInputInit() < 0) {
    rv_winmgr.input_ok = FALSE;
    return FALSE;
  }
  rv_winmgr.input_ok = TRUE;
  rv_winmgr.ptr_x = rv_winmgr.cols / 2;
  rv_winmgr.ptr_y = rv_winmgr.rows / 2;
  return TRUE;
}

I64 RVWinMgrPumpInput(I64 max)
{
  //Drain up to max virtio-input events into focus/typing. Returns events handled.
  CVinEvent ev;
  I64 n = 0, hit, ch, px, py, nx, ny;
  Bool content_dirty = FALSE;
  Bool ptr_dirty = FALSE;
  if (!rv_winmgr.ready || !rv_winmgr.input_ok)
    return 0;
  nx = rv_winmgr.ptr_x;
  ny = rv_winmgr.ptr_y;
  while (n < max && VirtioInputPollOne(&ev)) {
    n++;
    rv_winmgr.input_events++;
    if (ev.type == EV_KEY) {
      if (ev.code == KEY_LEFTSHIFT || ev.code == KEY_RIGHTSHIFT) {
        rv_winmgr.shift = ev.value != 0;
        continue;
      }
      if (ev.value == 0)
        continue;
      // key down only
      if (ev.code == KEY_ESC) {
        rv_winmgr.want_quit = TRUE;
        content_dirty = TRUE;
        continue;
      }
      if (ev.code == KEY_TAB) {
        RVWinFocusNext;
        content_dirty = TRUE;
        continue;
      }
      ch = VirtioInputKeyToChar(ev.code, rv_winmgr.shift);
      if (ch) {
        RVWinBodyPutChar(ch);
        content_dirty = TRUE;
      }
    } else if (ev.type == EV_ABS) {
      if (ev.code == ABS_X) {
        nx = VirtioInputMapAbs(ABS_X, ev.value, rv_winmgr.cols - 1);
      } else if (ev.code == ABS_Y) {
        ny = VirtioInputMapAbs(ABS_Y, ev.value, rv_winmgr.rows - 1);
      }
    } else if (ev.type == EV_REL) {
      if (ev.code == REL_X) {
        // REL_X (pixels): Linux +right is positive (TempleOS MsHard: +dx moves +x).
        px = nx *FONT_WIDTH + ev.value;
        nx = px / FONT_WIDTH;
        if (nx < 0)
          nx = 0;
        if (nx >= rv_winmgr.cols)
          nx = rv_winmgr.cols - 1;
      } else if (ev.code == REL_Y) {
        // REL_Y (pixels): +down is positive (TempleOS MsHard negates PS/2 packet Y).
        py = ny *FONT_HEIGHT + ev.value;
        ny = py / FONT_HEIGHT;
        if (ny < 0)
          ny = 0;
        if (ny >= rv_winmgr.rows)
          ny = rv_winmgr.rows - 1;
      }
    } else if (ev.type == EV_SYN) {
      if (nx != rv_winmgr.ptr_x || ny != rv_winmgr.ptr_y) {
        rv_winmgr.ptr_x = nx;
        rv_winmgr.ptr_y = ny;
        ptr_dirty = TRUE;
      }
    }
    if ((ev.type == EV_ABS || ev.type == EV_REL) && (nx != rv_winmgr.ptr_x || ny != rv_winmgr.ptr_y)) {
      rv_winmgr.ptr_x = nx;
      rv_winmgr.ptr_y = ny;
      ptr_dirty = TRUE;
    }
    // BTN_LEFT is EV_KEY code 0x110
    if (ev.type == EV_KEY && ev.code == BTN_LEFT && ev.value) {
      hit = RVWinHitTest(nx, ny);
      if (hit >= 0) {
        rv_winmgr.ptr_x = nx;
        rv_winmgr.ptr_y = ny;
        RVWinFocus(hit);
        content_dirty = TRUE;
        ptr_dirty = TRUE;
      }
    }
  }
  if (content_dirty)
    RVWinMgrRefresh;
  else if (ptr_dirty)
    RVWinMgrCursorUpdate;
  return n;
}

U0 RVWinMgrRun(I64 max_iters = 0)
{
  //Interactive desktop pump. max_iters=0 → until ESC; else bounded (smokes).
  // UART serial TTY (RVWinSerialPoll) runs each tick alongside VirtioInput.
  I64 i = 0;
  rv_winmgr.want_quit = FALSE;
  if (!rv_winmgr.input_ok)
    RVWinMgrInputInit;
  while (!rv_winmgr.want_quit) {
    RVWinMgrPumpInput(256);
    RVWinSerialPoll;
    // Sleep(1) is a no-op without CTask jiffies; CLINT idle keeps cocoa/SDL responsive.
    RVIdleMs(1);
    rv_winmgr_task_iters++;
    if (max_iters > 0) {
      i++;
      if (i >= max_iters)
        break;
    }
  }
}

public U0 WinMgrTask(I64 unused = 0)
{
  //P4 lite WinMgrTask (Adam/WinMgr.HC role): refresh + VirtioInput pump, no ODE/menus.
  // Spawn with RVKSpawn(&WinMgrTask, "Window Mgr", adam) when the scheduler is live;
  // demos may also call WinMgrTask() / RVWinMgrRun directly on Adam.
  no_warn unused;
  sys_winmgr_task = Fs;
  LBts(&sys_run_level, RLf_WINMGR);
  if (!rv_winmgr.input_ok)
    RVWinMgrInputInit;
  RVWinMgrRun(0);
  LBtr(&sys_run_level, RLf_WINMGR);
}

CTask *RVWinMgrSpawn(CTask *adam = NULL)
{
  //Spawn WinMgrTask via RVKSpawn (RV stack fixup). Returns task or NULL.
  CTask *t;
  if (!rv_winmgr.ready)
    return NULL;
  if (!adam)
    adam = adam_task;
  if (!adam)
    adam = Fs;
  if (!adam)
    return NULL;
  if (sys_winmgr_task)
    return sys_winmgr_task;
  t = RVKSpawn(&WinMgrTask, "Window Mgr", adam);
  sys_winmgr_task = t;
  return t;
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
  RVWinMgrInputInit;
  // best-effort; OK if no virtio-input on this QEMU line
  // DocTermNew runs inside DemoDesktop (wires Put/Display/Border). StartOS/MakeAdam
  // HOME.DD load needs RedSea (RVKMain mount + StartOS_RV / win-interactive).
  LBts(&sys_run_level, RLf_WINMGR);
  RVWinMgrRefresh;
  Print("RVSysWinInit: WinMgr desktop wins=%d focus=%d %dx%d text=%dx%d input=%d put=%d\n", rv_winmgr.n_wins, rv_winmgr.focus, rv_fb.width, rv_fb.height, rv_winmgr.cols, rv_winmgr.rows, rv_winmgr.input_ok, DocPut() != NULL);
  // Dual-console: UART dig-down stays live while FB/WinMgr owns virtio input.
  RVWinSerialInit;
  return TRUE;
}
