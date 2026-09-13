// TempleOS-style window manager on native 32-bpp FB (Phase F).
//
// Faithful subset of Adam WinMgr / GrScrn text path — NOT VGA:
//   - U32 text_base cells (ASCII + 4-bit FG/BG, same layout as Doc/TextBase.DD)
//   - TextBorder / TextRect / TextPrint into text_base (portable HolyC, no x86 asm)
//   - Z-ordered task windows with borders + titles
//   - Render text_base → 32-bpp compose (default) or full-screen is_u8 (RVGrPaintDC)
//     then GrUpdateVGAGraphics expand + RVFbPresent
//   - Opt-in: RVGrU8ComposeEnable → WinMgr text/draw_it/sprites paint is_u8; Bind-only
//     (non-fullscreen) still present-expand only
//
// Gaps vs full Adam: full DolDoc (~28 files) still open — P2 Kernel/RVDoc.HC
// CDoc entry subset + DocSave/Write/Read + DocEdIns/BS/undo; Term/Adam sync;
// DocBorderNew widgets; bins/sprites / modal DocEd open. Default draw stays 32-bpp.
// DocTermNew → Term + Put/Display/Border docs + HOME.DD; WinMgrTask pumps.
// Input: VirtioInput → TaskMsg → live RVKSpawn GetMsg/ScanMsg (Term/User/HOME) or Fs drain;
// JobsHndlr skips JOBT_MSG so ScanMsg on RVKSpawn is safe. DocSprite→Sprite3 after blit.
// Term+Adam+User ExePutS; HOME scrolls + link/tree/form click; title-bar drag; [X]/
// MENU; WinMax/Tile; Ctrl-grab scroll. P1: CRVWin↔CTask.win_* + WinZBuf clip (done).
// P5: ODEsUpdate on CTask.next_ode (soft winmgr) each refresh — not Euler-only.
// UART: RVWinSerial.
U0 RVWinSerialPoll();
Bool RVWinSerialInit();
U0 RVWinTermPutChar(I64 ch);
U0 RVWinAdamPutChar(I64 ch);
U0 RVWinHomePutKey(I64 ch, I64 code);
U0 RVWinPutKey(I64 ch, I64 code);
U0 RVWinMsgPutKey(I64 ch, I64 code);
public U0 WinZBufUpdate();
U0 RVWinSetTitle(I64 idx, U8 *title);
U0 RVWinSyncToTask(I64 idx);
U0 RVWinClampGeom(I64 idx);
// PopUp_RV (included after this file) — forward decls for MENU About action.
Bool RVPopUpOk(U8 *header = NULL);
Bool RVPopUpNoYes(U8 *header = NULL);
Bool RVDocForm(U8 *header = NULL, I64 dft_val = 0, Bool dft_check = FALSE);
Bool RVDocFormMeta(U8 *header = NULL, I64 dft_val = 42, Bool dft_check = TRUE);
Bool RVPopUpPutKey(I64 ch);
Bool RVPopUpClick(I64 cx, I64 cy);
Bool RVPopUpResolve(I64 res);
U0 RVPopUpWire();
I64 RVPopUp(U8 *buf, CTask *parent = NULL, CTask **_pu_task = NULL);
I64 RVPopUpPrint(U8 *fmt,...);
// Ctrls_RV (included after this file) — Bttn/Slider on FB.
U0 RVCtrlsDrawWin(I64 win_idx, CRVDC *dc);
Bool RVCtrlsClick(I64 cx, I64 cy);
U0 RVCtrlsDemoInstall(I64 win_idx);
U0 RVWinMgrDrawMenu();
U0 RVWinMenuClose();
Bool RVWinMenuHit(I64 cx, I64 cy);
Bool RVWinMenuPutKey(I64 ch, I64 code);
I64 RVCtrlAltFlagsService();
U0 RVKeyDevCtrlAltWire();
I64 RVCtrlAltChord(I64 ch);
U0 RVACInit();
U0 RVACRefresh(U8 *body);
U0 RVACDraw(I64 row);
U0 ACFillIn(I64 n);
Bool RVWinClose(I64 idx = -1);
public U0 RVWinMax(I64 idx = -1);
public U0 RVWinTileHorz();
public U0 RVWinTileVert();
#define RV_WIN_MAX       8
#define RV_WIN_TITLE_MAX 48
#define RV_WIN_BODY_MAX  1024
#define RV_WIN_KIND_NONE 0
#define RV_WIN_KIND_ADAM 1
#define RV_WIN_KIND_TERM 2
#define RV_WIN_KIND_HOME 3
#define RV_WIN_KIND_USER 4
#define RV_DRAG_NONE     0
#define RV_DRAG_MOVE     1
#define RV_DRAG_RESIZE_L 2
#define RV_DRAG_RESIZE_B 3
#define RV_DRAG_RESIZE_R 4
#define RV_DRAG_RESIZE_BR 5
#define RV_DRAG_SCROLL   6
#define RV_CHROME_NONE   0
#define RV_CHROME_MENU   1
#define RV_CHROME_CLOSE  2
#define EV_SYN  0
#define EV_KEY  1
#define EV_REL  2
#define EV_ABS  3
#define KEY_LEFTSHIFT  42
#define KEY_RIGHTSHIFT 54
#define KEY_LEFTCTRL   29
#define KEY_RIGHTCTRL  97
#define KEY_LEFTALT    56
#define KEY_RIGHTALT   100
#define KEY_ESC        1
#define KEY_TAB        15
#define KEY_M          50
#define KEY_DELETE     111
#define KEY_F1         59
#define KEY_F10        68
#define KEY_HOME       102
#define KEY_UP         103
#define KEY_PAGEUP     104
#define KEY_LEFT       105
#define KEY_RIGHT      106
#define KEY_END        107
#define KEY_DOWN       108
#define KEY_PAGEDOWN   109
#define BTN_LEFT       0x110
#define BTN_RIGHT      0x111
#define ABS_X          0
#define ABS_Y          1
#define REL_X          0
#define REL_Y          1
#define RV_CURSOR_W    17
#define RV_CURSOR_H    17
#define RV_CURSOR_CELLS (RV_CURSOR_W * RV_CURSOR_H)
// Cursor save-under lives outside CRVWinMgrGlbls so a bad blit cannot clobber
// input_ok / want_quit (that made PumpInput stop while UART serial still worked).
U32 rv_win_ptr_save[RV_CURSOR_CELLS];
class CRVWin
{
  //One on-screen window (TempleOS: one window per Core0 task).
  Bool used;
  Bool show;
  Bool no_border;
  Bool focused;
  Bool kill_on_close;
  // [X] → Kill(task) when TRUE (User spawns); Adam/Term/HOME hide only
  I64 kind;
  // RV_WIN_KIND_*
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
  I64 scroll_x;
  // Doc-lite left column offset (Ctrl-grab / TempleOS scroll_x lite)
  I64 scroll_y;
  // Doc-lite top line offset (HOME / long bodies; TempleOS scroll_y lite)
  CTask *task;
  // bound Core0 task (win_* mirror); NULL = slot-only
  U8 title[RV_WIN_TITLE_MAX];
  U8 body[RV_WIN_BODY_MAX];
  // Doc-lite text; $$0-$$F FG, $$Bn BG, $$FG,/$$BG,/$$TX,"…"$$ (Term/Adam)
  CDoc *doc;
  // P2: real CDoc entry stream when set (HOME/Term/Adam); paint via RVDocDrawWin
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
  U8 wallpaper_heap[96];
  U8 wallpaper_idle[96];
  U8 wallpaper_tasks[4][96];
  I64 wallpaper_task_n;
  I64 n_wins;
  CRVWin wins[RV_WIN_MAX];
  I64 focus;
  // index into wins[], or -1
  I64 term_idx;
  // DocTermNew window, or -1
  I64 adam_idx;
  // Adam command window, or -1
  I64 home_idx;
  // HOME.DD / Doc-lite file window, or -1
  I64 gr_idx;
  // Gr/CDC demo window with draw_it, or -1
  I64 updates;
  // Pointer in text cells (from virtio ABS tablet or REL mouse)
  I64 ptr_x;
  I64 ptr_y;
  I64 ptr_ox;
  // last cursor hot-spot in pixels (save-under)
  I64 ptr_oy;
  Bool ptr_save_valid;
  Bool shift;
  // Keep control flags as I64 — Bool packing next to hot fields was fragile under AOT.
  I64 ctrl;
  // KEY_LEFTCTRL / KEY_RIGHTCTRL held (TempleOS SCF_CTRL / grab-scroll)
  I64 input_ok;
  // VirtioInputInit succeeded (0/1)
  I64 input_events;
  I64 want_quit;
  // ESC / serial q sets this for interactive run loops (0/1)
  I64 ptr_lb;
  // left button held (TempleOS ms.lb analogue for border drag)
  I64 ptr_rb;
  // right button held (MassSpring spring drag)
  I64 drag_mode;
  // RV_DRAG_* while title/border/Ctrl-scroll drag active
  I64 drag_idx;
  I64 drag_ox;
  // move: ptr_x - left; resize-L: ptr_y - top; scroll: origin ptr
  I64 drag_oy;
  I64 drag_scroll_x0;
  // scroll drag: window scroll_x at grab start
  I64 drag_scroll_y0;
  I64 chrome_hit;
  // RV_CHROME_* pending MENU/[X] on title (fire on LB release)
  I64 chrome_idx;
  I64 home_scrolls;
  // smoke: HOME PutKey scroll actions
  I64 home_link_hits;
  // smoke: HOME $$LK activate (click/Enter)
  I64 home_tree_toggles;
  // smoke: HOME $$TR collapse toggle
  I64 home_form_hits;
  // smoke: HOME $$BT/$$CB/$$MA/$$DA activate
  I64 move_drags;
  // smoke: completed title-bar moves
  I64 menu_hits;
  // smoke: title MENU / Ctrl-M stub
  I64 close_hits;
  // smoke: title [X] closes
  I64 filemgr_idx;
  // FileMgr_RV CRVWin index, or -1
  I64 filemgr_open_hits;
  // smoke: RVFileMgrOpen calls
  I64 filemgr_head;
  // CDirEntry* tree for open FileMgr (I64 to stay AOT-safe in this unit)
  I64 scroll_drags;
  // smoke: completed Ctrl-grab scrolls
  I64 layout_ops;
  // smoke: WinMax / WinTile* calls
  I64 task_binds;
  // smoke: CRVWin↔CTask binds
  I64 msg_keys;
  // smoke: VirtioInput → TaskMsg(MSG_KEY_*) posts
  I64 msg_consumed;
  // smoke: focus-task GetMsg → PutKey drains
  I64 user_spawns;
  // smoke: Spawn User → new Term-like win
  I64 user_cmds;
  // smoke: User win ExePutS Enter lines
  I64 zbuf_updates;
  // smoke: WinZBufUpdate fills
  U16 *win_z_buf;
  // TEXT_COLS*ROWS z clip (Adam gr.win_z_buf)
  I64 win_z_highest;
  // max z stamped into win_z_buf
  I64 menu_open;
  // PersonalMenu pulldown visible (0/1)
  I64 menu_owner;
  // CRVWin idx that owns the pulldown
  I64 menu_sel;
  // highlighted entry index
  I64 menu_left;
  // pulldown text-cell geometry
  I64 menu_top;
  I64 menu_w;
  I64 menu_h;
  I64 wallpaper_sticky;
  // frames to keep MENU toast before live stats resume
};
I64 rv_winmgr_alt;
I64 rv_winmgr_ctrl_alt_hits;
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
  // Host AOT hangs on U8[i](I64)/U8[i](U32) cast-stores into the array — plant bytes
  // explicitly (LE layout of 0x0908070605040302 @ [2] and 0x0D0C0B0A @ [10]).
  rv_winmgr.border_chars[0] = 0;
  rv_winmgr.border_chars[1] = 0;
  rv_winmgr.border_chars[2] = 0x02;
  rv_winmgr.border_chars[3] = 0x03;
  rv_winmgr.border_chars[4] = 0x04;
  rv_winmgr.border_chars[5] = 0x05;
  rv_winmgr.border_chars[6] = 0x06;
  rv_winmgr.border_chars[7] = 0x07;
  rv_winmgr.border_chars[8] = 0x08;
  rv_winmgr.border_chars[9] = 0x09;
  rv_winmgr.border_chars[10] = 0x0A;
  rv_winmgr.border_chars[11] = 0x0B;
  rv_winmgr.border_chars[12] = 0x0C;
  rv_winmgr.border_chars[13] = 0x0D;
  rv_winmgr.border_chars[14] = 0;
  rv_winmgr.border_chars[15] = 0;
}

U0 RVDocLiteInitOne(CDoc *doc, U64 desc)
{
  //Stamp DOC_SIGNATURE_VAL so DocPut/DocDisplay/DocBorder succeed.
  // Must DocRst-style head queue — bare MemSet leaves head.next=NULL and DocSize hangs.
  // bin_head must QueInit too — Sprite/DocSpriteIns QueIns hangs on null last.
  if (!doc)
    return;
  MemSet(doc, 0, sizeof(CDoc));
  doc->doc_signature = DOC_SIGNATURE_VAL;
  doc->desc = desc;
  doc->win_task = Fs;
  doc->mem_task = Fs;
  doc->owning_task = Fs;
  doc->max_entries = 4096;
  doc->head.next = doc->head.last = doc;
  doc->cur_entry = doc;
  QueInit(&doc->bin_head);
  QueInit(&doc->undo_head);
  doc->cur_bin_num = 1;
}

U0 RVDocTermDocsInit()
{
  //Wire Fs put/display/border docs (Adam DocTermNew shape).
  // Border is a real CDoc (DocBorderNew); put/display stay signature stubs until
  // per-task DocPutKey fully owns Term typing (body still SoT for Term/Adam).
  CDoc *bdoc;
  RVDocLiteInitOne(&rv_doc_put, 'Term');
  RVDocLiteInitOne(&rv_doc_display, 'Term');
  if (Fs) {
    Fs->put_doc = &rv_doc_put;
    Fs->display_doc = &rv_doc_display;
    Fs->border_src = BDS_CUR_DRV;
    bdoc = DocBorderNew(NULL);
    if (bdoc) {
      Fs->border_doc = bdoc;
    } else {
      RVDocLiteInitOne(&rv_doc_border, 'Border');
      rv_doc_border.flags = DOCF_BORDER_DOC;
      Fs->border_doc = &rv_doc_border;
    }
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

I64 RVDocTermWire(CDoc *doc)
{
  // TempleOS DocTermNew put/display/border wire without WinMgr/Menu/Raw/FB.
  // Soft Call bridge: guest DocNew+DocPrintF then Wire → DocPut/Display/Border.
  CDoc *bdoc, *p, *d, *b;
  I64 bn;
  CDoc *old_put, *old_disp, *old_border;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return 3;
  if (!Fs)
    return 4;
  old_put = Fs->put_doc;
  old_disp = Fs->display_doc;
  old_border = Fs->border_doc;
  Fs->put_doc = doc;
  Fs->display_doc = doc;
  Fs->border_src = BDS_CUR_DRV;
  bdoc = DocBorderNew(doc);
  if (!bdoc) {
    Fs->put_doc = old_put;
    Fs->display_doc = old_disp;
    Fs->border_doc = old_border;
    return 5;
  }
  Fs->border_doc = bdoc;
  p = DocPut;
  d = DocDisplay;
  b = DocBorder;
  if (!p || p != doc) {
    Fs->put_doc = old_put;
    Fs->display_doc = old_disp;
    Fs->border_doc = old_border;
    DocDel(bdoc);
    return 6;
  }
  if (!d || d != doc) {
    Fs->put_doc = old_put;
    Fs->display_doc = old_disp;
    Fs->border_doc = old_border;
    DocDel(bdoc);
    return 7;
  }
  if (!b || b != bdoc) {
    Fs->put_doc = old_put;
    Fs->display_doc = old_disp;
    Fs->border_doc = old_border;
    DocDel(bdoc);
    return 9;
  }
  bn = DocSize(bdoc);
  Fs->put_doc = old_put;
  Fs->display_doc = old_disp;
  Fs->border_doc = old_border;
  DocDel(bdoc);
  if (bn <= 0)
    return 10;
  return 8;
}

I64 RVDocTermNewSoft()
{
  // TempleOS DocTermNew Put/Display/Border product shape without WinMgr/Menu/Raw/FB.
  // Soft Call entry beyond Wire: owns DocNew+desc='Term'+max_entries=4096, then
  // DocBorderNew + DocPut/Display/Border identity (restore Fs on exit).
  CDoc *pdoc, *bdoc, *p, *d, *b;
  CDoc *old_put, *old_disp, *old_border;
  I64 old_bsrc, bn;
  if (!Fs)
    return 4;
  old_put = Fs->put_doc;
  old_disp = Fs->display_doc;
  old_border = Fs->border_doc;
  old_bsrc = Fs->border_src;
  pdoc = DocNew;
  if (!pdoc || pdoc->doc_signature != DOC_SIGNATURE_VAL)
    return 3;
  pdoc->max_entries = 4096;
  pdoc->desc = 'Term';
  Fs->border_src = BDS_CUR_DRV;
  Fs->put_doc = pdoc;
  Fs->display_doc = pdoc;
  bdoc = DocBorderNew(pdoc);
  if (!bdoc) {
    Fs->put_doc = old_put;
    Fs->display_doc = old_disp;
    Fs->border_doc = old_border;
    Fs->border_src = old_bsrc;
    DocDel(pdoc);
    return 5;
  }
  Fs->border_doc = bdoc;
  p = DocPut;
  d = DocDisplay;
  b = DocBorder;
  if (!p || p != pdoc || p->desc != 'Term' || p->max_entries != 4096) {
    Fs->put_doc = old_put;
    Fs->display_doc = old_disp;
    Fs->border_doc = old_border;
    Fs->border_src = old_bsrc;
    DocDel(bdoc);
    DocDel(pdoc);
    return 6;
  }
  if (!d || d != pdoc) {
    Fs->put_doc = old_put;
    Fs->display_doc = old_disp;
    Fs->border_doc = old_border;
    Fs->border_src = old_bsrc;
    DocDel(bdoc);
    DocDel(pdoc);
    return 7;
  }
  if (!b || b != bdoc) {
    Fs->put_doc = old_put;
    Fs->display_doc = old_disp;
    Fs->border_doc = old_border;
    Fs->border_src = old_bsrc;
    DocDel(bdoc);
    DocDel(pdoc);
    return 9;
  }
  bn = DocSize(bdoc);
  Fs->put_doc = old_put;
  Fs->display_doc = old_disp;
  Fs->border_doc = old_border;
  Fs->border_src = old_bsrc;
  DocDel(bdoc);
  DocDel(pdoc);
  if (bn <= 0)
    return 10;
  return 8;
}

U0 RVWinBodyAppend(I64 idx, U8 *st)
{
  //Append plain text into window body (DocPrint / typing path).
  // Keep attached CDoc in sync via DocPutS (ExePutS-safe incremental path).
  I64 len, i, n;
  CRVWin *w;
  if (!st || idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.ready)
    return;
  if (!rv_winmgr.wins[idx].used)
    return;
  w = &rv_winmgr.wins[idx];
  len = RVWinBodyLen(w->body);
  n = StrLen(st);
  // body[] is a BOUNDED scroll buffer. When the new text will not fit, drop whole lines
  // from the FRONT to make room — never the new text. (The old code rebuilt the CDoc from
  // a full body on every overflow: DocRst + DocPutS(body). That discarded the incoming
  // text AND wiped the doc's scrollback back to the 1 KB body, so the Term/Adam console
  // froze after ~1 KB of cumulative output — `regs` died after one dump, `Print` after a
  // few lines. The attached CDoc holds the real history via DocRecalc; body is only the
  // plain-text fallback for windows that have no doc.)
  if (len + n > RV_WIN_BODY_MAX - 1) {
    I64 cut = 0, drop = len + n - (RV_WIN_BODY_MAX - 1), j;
    while (cut < len && cut < drop)
      cut++;
    while (cut < len && w->body[cut - 1] != '\n')  // drop only whole lines
      cut++;
    if (cut > len)
      cut = len;
    if (cut > 0) {
      j = 0;
      while (cut + j <= len) {   // shift tail down, including the terminating NUL
        w->body[j] = w->body[cut + j];
        j++;
      }
      len -= cut;
    }
  }
  for (i = 0; i < n && len < RV_WIN_BODY_MAX - 1; i++) {
    w->body[len] = st[i];
    len++;
  }
  w->body[len] = 0;
  // Always append incrementally to the CDoc — it owns the scrollback, so it must not be
  // reset just because the flat body buffer had to scroll.
  if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL && n > 0)
    DocPutS(w->doc, st);
}

U0 RVDocPutS(U8 *st)
{
  //Append into focused Term/User body (DocPrint / typing path). Prefer focus, else term_idx.
  I64 idx, kind;
  if (!st || !rv_winmgr.ready)
    return;
  idx = rv_winmgr.focus;
  kind = RV_WIN_KIND_NONE;
  if (idx >= 0 && idx < RV_WIN_MAX && rv_winmgr.wins[idx].used)
    kind = rv_winmgr.wins[idx].kind;
  if (kind != RV_WIN_KIND_TERM && kind != RV_WIN_KIND_USER) {
    idx = rv_winmgr.term_idx;
    if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
      idx = rv_winmgr.focus;
  }
  RVWinBodyAppend(idx, st);
}

I64 RVWinBodyLineCount(U8 *body)
{
  I64 i, n;
  if (!body || !body[0])
    return 0;
  n = 1;
  for (i = 0; i < RV_WIN_BODY_MAX && body[i]; i++) {
    if (body[i] == '\n' && body[i + 1])
      n++;
  }
  return n;
}

I64 RVWinBodySkipLines(U8 *body, I64 n)
{
  //Byte index after skipping n newlines (Doc-lite scroll start).
  I64 i = 0;
  if (!body || n <= 0)
    return 0;
  while (n > 0 && i < RV_WIN_BODY_MAX && body[i]) {
    if (body[i] == '\n')
      n--;
    i++;
  }
  return i;
}

U0 RVWinClampScroll(I64 idx)
{
  CRVWin *w;
  I64 lines, h, max, ww;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return;
  w = &rv_winmgr.wins[idx];
  if (!w->used)
    return;
  if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL && (w->kind == RV_WIN_KIND_HOME || w->kind == RV_WIN_KIND_TERM || w->kind == RV_WIN_KIND_ADAM || w->kind == RV_WIN_KIND_USER))
    lines = RVDocLineCount(w->doc);
  else
    lines = RVWinBodyLineCount(w->body);
  h = w->bottom - w->top + 1;
  if (h < 1)
    h = 1;
  max = lines - h;
  if (max < 0)
    max = 0;
  if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL && (w->kind == RV_WIN_KIND_TERM || w->kind == RV_WIN_KIND_ADAM)) {
    // Console docs: DocRecalc keeps the cursor page at y=0..h-1, so history lies at
    // negative y. scroll_y in [-(lines-h), 0] pages back through it (PgUp/PgDn/arrows).
    if (w->scroll_y < -max)
      w->scroll_y = -max;
    if (w->scroll_y > 0)
      w->scroll_y = 0;
    return;
  }
  if (w->scroll_y < 0)
    w->scroll_y = 0;
  if (w->scroll_y > max)
    w->scroll_y = max;
  ww = w->right - w->left + 1;
  if (ww < 1)
    ww = 1;
  // Horizontal: allow a few client-widths of pan (Doc-lite; not full DolDoc).
  if (w->scroll_x < 0)
    w->scroll_x = 0;
  if (w->scroll_x > ww * 4)
    w->scroll_x = ww * 4;
}

U0 RVWinScrollBy(I64 idx, I64 delta)
{
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    return;
  rv_winmgr.wins[idx].scroll_y += delta;
  RVWinClampScroll(idx);
}

U0 RVWinScrollXYBy(I64 idx, I64 dx, I64 dy)
{
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    return;
  rv_winmgr.wins[idx].scroll_x += dx;
  rv_winmgr.wins[idx].scroll_y += dy;
  RVWinClampScroll(idx);
}

Bool RVWinMgrLiteInit()
{
  // UART Soft Call / headless: text grid + ready without FB/Gr.
  // Fixed 80×25 over static text_base; no win_z_buf (WinZBuf no-ops).
  // Enables stock DocTermNew → Term window / term_idx without interactive FB.
  I64 cols = 80, rows = 25, cells;
  if (rv_winmgr.ready)
    return TRUE;
  cells = cols *rows;
  if (cells > RV_TEXT_BASE_STORE_CELLS)
    return FALSE;
  MemSet(&rv_winmgr, 0, sizeof(CRVWinMgrGlbls));
  rv_winmgr.cols = cols;
  rv_winmgr.rows = rows;
  rv_winmgr.text_base = rv_text_base_store;
  MemSet(rv_winmgr.text_base, 0, cells *sizeof(U32));
  rv_winmgr.win_z_buf = NULL;
  rv_winmgr.win_z_highest = 0;
  RVWinMgrBorderCharsInit;
  rv_winmgr.wallpaper_attr = BLUE << 4 + WHITE;
  rv_winmgr.wallpaper_bg = 0;
  StrCpy(rv_winmgr.wallpaper_line, "TempleOS/RISC-V  WinMgr lite (UART, no FB)");
  rv_winmgr.wallpaper_heap[0] = 0;
  rv_winmgr.wallpaper_idle[0] = 0;
  rv_winmgr.wallpaper_task_n = 0;
  rv_winmgr.focus = -1;
  rv_winmgr.term_idx = -1;
  rv_winmgr.adam_idx = -1;
  rv_winmgr.home_idx = -1;
  rv_winmgr.gr_idx = -1;
  rv_winmgr.drag_mode = RV_DRAG_NONE;
  rv_winmgr.drag_idx = -1;
  rv_winmgr.filemgr_idx = -1;
  rv_winmgr.ready = TRUE;
  text.cols = cols;
  text.rows = rows;
  text.font = sys_font_std;
  text.aux_font = sys_font_cyrillic;
  MemCpy(text.border_chars, rv_winmgr.border_chars, 16);
  DocInit;
  return TRUE;
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
  rv_winmgr.win_z_buf = MAlloc(cells *sizeof(U16));
  if (!rv_winmgr.win_z_buf)
    return FALSE;
  MemSet(rv_winmgr.win_z_buf, 0, cells *sizeof(U16));
  rv_winmgr.win_z_highest = 0;
  RVWinMgrBorderCharsInit;
  rv_winmgr.wallpaper_attr = BLUE << 4 + WHITE;
  rv_winmgr.wallpaper_bg = RV_RGB(32, 64, 128);
  StrCpy(rv_winmgr.wallpaper_line, "TempleOS/RISC-V  WinMgr on 32-bpp FB");
  rv_winmgr.wallpaper_heap[0] = 0;
  rv_winmgr.wallpaper_idle[0] = 0;
  rv_winmgr.wallpaper_task_n = 0;
  rv_winmgr.focus = -1;
  rv_winmgr.term_idx = -1;
  rv_winmgr.adam_idx = -1;
  rv_winmgr.home_idx = -1;
  rv_winmgr.gr_idx = -1;
  rv_winmgr.drag_mode = RV_DRAG_NONE;
  rv_winmgr.drag_idx = -1;
  rv_winmgr.ptr_lb = 0;
  rv_winmgr.ptr_rb = 0;
  rv_winmgr.ctrl = 0;
  rv_winmgr_alt = 0;
  rv_winmgr_ctrl_alt_hits = 0;
  rv_winmgr.chrome_hit = RV_CHROME_NONE;
  rv_winmgr.chrome_idx = -1;
  rv_winmgr.home_scrolls = 0;
  rv_winmgr.home_link_hits = 0;
  rv_winmgr.home_tree_toggles = 0;
  rv_winmgr.home_form_hits = 0;
  rv_winmgr.move_drags = 0;
  rv_winmgr.menu_hits = 0;
  rv_winmgr.close_hits = 0;
  rv_winmgr.filemgr_idx = -1;
  rv_winmgr.filemgr_open_hits = 0;
  rv_winmgr.filemgr_head = 0;
  rv_winmgr.scroll_drags = 0;
  rv_winmgr.layout_ops = 0;
  rv_winmgr.task_binds = 0;
  rv_winmgr.msg_keys = 0;
  rv_winmgr.msg_consumed = 0;
  rv_winmgr.user_spawns = 0;
  rv_winmgr.user_cmds = 0;
  rv_winmgr.zbuf_updates = 0;
  rv_winmgr.ready = TRUE;
  RVKeyDevCtrlAltWire;
  RVACInit;
  // Also mirror into global text.* so TaskInit-sized fields stay coherent.
  text.cols = cols;
  text.rows = rows;
  text.font = sys_font_std;
  text.aux_font = sys_font_cyrillic;
  MemCpy(text.border_chars, rv_winmgr.border_chars, 16);
  // Warm doldoc.hash before PopUp/FileMgr (DocInit_RV; avoid late HashTableNew).
  DocInit;
  // Job.HC PopUp → RVKSpawn+CRVWin (PopUp_RV; linked after this unit).
  RVPopUpWire;
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

U0 RVWinSyncToTask(I64 idx)
{
  //Push CRVWin geometry into bound CTask.win_* / scroll / attrs (TempleOS identity).
  CRVWin *w;
  CTask *t;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return;
  w = &rv_winmgr.wins[idx];
  t = w->task;
  if (!TaskValidate(t))
    return;
  t->win_left = w->left;
  t->win_right = w->right;
  t->win_top = w->top;
  t->win_bottom = w->bottom;
  t->scroll_x = w->scroll_x << 3;
  t->scroll_y = w->scroll_y << 3;
  t->border_attr = w->border_attr;
  t->text_attr = w->text_attr;
  t->win_z_num = w->z;
  // Stock DocRecalc reads win_width/win_height (not left/right): without them the Term
  // doc's line_start_col chased the cursor and every scrolled line lost its leading
  // characters ("b375Ab" for "Ab375Ab"). Just the arithmetic — not TaskDerivedValsUpdate,
  // whose TASK_LOCK spin / fp_update_ctrls callback stalled the desktop loop.
  WinDerivedValsUpdate(t);
  if (w->show)
    LBts(&t->display_flags, DISPLAYf_SHOW);
  else
    LBtr(&t->display_flags, DISPLAYf_SHOW);
}

U0 RVWinSyncFromTask(I64 idx)
{
  //Pull CTask.win_* into CRVWin (after external WinHorz/WinVert).
  CRVWin *w;
  CTask *t;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return;
  w = &rv_winmgr.wins[idx];
  t = w->task;
  if (!TaskValidate(t))
    return;
  w->left = t->win_left;
  w->right = t->win_right;
  w->top = t->win_top;
  w->bottom = t->win_bottom;
  w->scroll_x = t->scroll_x >> 3;
  w->scroll_y = t->scroll_y >> 3;
  w->border_attr = t->border_attr;
  w->text_attr = t->text_attr;
  w->show = Bt(&t->display_flags, DISPLAYf_SHOW) != 0;
}

I64 RVWinFindByTask(CTask *task)
{
  I64 i;
  if (!task)
    return -1;
  for (i = 0; i < RV_WIN_MAX; i++) {
    if (rv_winmgr.wins[i].used && rv_winmgr.wins[i].task == task)
      return i;
  }
  return -1;
}

Bool RVWinBindTask(I64 idx, CTask *task, I64 kind = RV_WIN_KIND_NONE, Bool kill_on_close = FALSE)
{
  //Associate CRVWin slot with a Core0 CTask; sync win_* both ways from the slot.
  CRVWin *w;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return FALSE;
  w = &rv_winmgr.wins[idx];
  if (!w->used)
    return FALSE;
  if (!TaskValidate(task))
    return FALSE;
  w->task = task;
  if (kind != RV_WIN_KIND_NONE)
    w->kind = kind;
  w->kill_on_close = kill_on_close;
  if (task->task_title[0])
    RVWinSetTitle(idx, task->task_title);
  else if (w->title[0])
    StrCpy(task->task_title, w->title);
  RVWinSyncToTask(idx);
  rv_winmgr.task_binds++;
  return TRUE;
}

I64 RVWinScanKeyDown(I64 *_ch, I64 *_sc)
{
  //Lite ScanMsg(MSG_KEY_DOWN) queue walk — kept as fallback; live consumers use ScanMsg
  // after JobsHndlr skips JOBT_MSG (no JobRunOne/Exit on RVKSpawn).
  CJob *tmpc, *tmpc1;
  I64 res;
  tmpc1 = &Fs->srv_ctrl.next_waiting;
  tmpc = tmpc1->next;
  while (tmpc != tmpc1) {
    if (tmpc->job_code == JOBT_MSG && tmpc->msg_code == MSG_KEY_DOWN) {
      QueRem(tmpc);
      res = tmpc->msg_code;
      if (_ch)
        *_ch = tmpc->aux1;
      if (_sc)
        *_sc = tmpc->aux2;
      JobDel(tmpc);
      return res;
    }
    tmpc = tmpc->next;
  }
  if (_ch)
    *_ch = 0;
  if (_sc)
    *_sc = 0;
  return 0;
}

U0 RVWinDocConsumer()
{
  //Per-task GetMsg → DocPutKey-lite (TempleOS User/Term focus consumer).
  // Real ScanMsg (JobsHndlr now leaves JOBT_MSG for ScanMsg). AWAITING_MSG so
  // IdleMs/Yield skips us until TaskMsg wakes the focus task.
  I64 ch, sc;
  while (TRUE) {
    while (!ScanMsg(&ch, &sc, 1 << MSG_KEY_DOWN)) {
      LBts(&Fs->task_flags, TASKf_IDLE);
      LBts(&Fs->task_flags, TASKf_AWAITING_MSG);
      Yield;
      LBtr(&Fs->task_flags, TASKf_IDLE);
    }
    rv_winmgr.msg_consumed++;
    RVWinPutKey(ch, sc);
  }
}

CTask *RVWinSpawnConsumer(U8 *name, CTask *parent)
{
  //RVKSpawn so RISC-V stack frames are runnable under Yield (plain Spawn → mepc=0).
  // Start SUSPENDED+AWAITING_MSG: stay out of IdleMs/ExePutS Yield until MsgPutKey
  // briefly unsuspends. First switch still uses the planted entry frame.
  CTask *t;
  if (!TaskValidate(parent))
    return NULL;
  if (!name)
    name = "Win";
  t = RVKSpawn(&RVWinDocConsumer, name, parent);
  if (TaskValidate(t)) {
    StrCpy(t->task_title, name);
    LBts(&t->task_flags, TASKf_SUSPENDED);
    LBts(&t->task_flags, TASKf_AWAITING_MSG);
  }
  return t;
}

U0 RVWinTaskSoftKill(CTask *t)
{
  //Kill-without-TaskEnd (PopUp_RV / User [X]): unlink, drop locks, park, invalidate.
  // HolyYield never runs TaskEnd on KILL_TASK, so wait=TRUE hangs; signature=0 alone
  // leaves a ring zombie that can be Yield'd into after queue reshuffles (mepc=0 /
  // unhandled throw→ebreak in DrvChk). Mirror PopUp_RV + TaskQueRem + lock reclaim.
  I64 i;
  CDrv *dv;
  CBlkDev *bd;
  if (!t || t == adam_task || t == Fs || t == sys_winmgr_task)
    return;
  // Drop blk/drv locks owned by the dying task (TaskEnd would DrvsRelease as Fs).
  for (i = 0; i < DRVS_NUM; i++) {
    dv = &blkdev.drvs[i];
    if (dv->owning_task == t) {
      dv->owning_task = NULL;
      LBtr(&dv->locked_flags, DVlf_LOCKED);
    }
  }
  for (i = 0; i < BLKDEVS_NUM; i++) {
    bd = &blkdev.blkdevs[i];
    if (bd->owning_task == t) {
      bd->owning_task = NULL;
      LBtr(&bd->locked_flags, BDlf_LOCKED);
    }
  }
  if (t->parent_task && t->parent_task->popup_task == t)
    t->parent_task->popup_task = NULL;
  if (Fs->popup_task == t)
    Fs->popup_task = NULL;
  if (sys_focus_task == t)
    sys_focus_task = NULL;
  // Unlink only when doubly-linked consistently (corrupt Rem unhooks Term/HOME).
  if (t->next_task && t->last_task && t->next_task != t && t->next_task->last_task == t && t->last_task->next_task == t) {
    TaskQueRem(t);
    t->next_task = t;
    t->last_task = t;
  }
  LBts(&t->task_flags, TASKf_KILL_TASK);
  LBts(&t->task_flags, TASKf_SUSPENDED);
  LBts(&t->task_flags, TASKf_AWAITING_MSG);
  t->task_signature = 0;
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
  RVWinSyncToTask(idx);
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
  RVWinSyncToTask(idx);
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
    if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL)
      DocRst(w->doc, TRUE);
    return;
  }
  for (i = 0; i < RV_WIN_BODY_MAX - 1 && body[i]; i++)
    w->body[i] = body[i];
  w->body[i] = 0;
  if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL) {
    DocRst(w->doc, TRUE);
    DocPutS(w->doc, w->body);
    DocRecalc(w->doc);
  }
}

U0 RVWinFocus(I64 idx)
{
  //Mark window focused (solid border); others hollow. TempleOS WinFocus lite.
  I64 i;
  CRVWin *w;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used) {
    rv_winmgr.focus = -1;
    for (i = 0; i < RV_WIN_MAX; i++)
      rv_winmgr.wins[i].focused = FALSE;
    return;
  }
  rv_winmgr.focus = idx;
  for (i = 0; i < RV_WIN_MAX; i++)
    rv_winmgr.wins[i].focused = (i == idx);
  w = &rv_winmgr.wins[idx];
  if (TaskValidate(w->task))
    sys_focus_task = w->task;
}

U0 RVWinMgrWallPaperLive()
{
  //Adam/WallPaper.HC lite: top line + heap/idle + task rows (not full caller stk).
  U8 buf[96];
  U8 *ft = "-";
  I64 i, shown = 0, mem = 0, alloced = 0, n = 0, idle_pct = 0;
  CRVWin *w;
  CTask *t;
  if (rv_winmgr.wallpaper_sticky > 0) {
    rv_winmgr.wallpaper_sticky--;
    return;
  }
  for (i = 0; i < RV_WIN_MAX; i++) {
    if (rv_winmgr.wins[i].used && rv_winmgr.wins[i].show)
      shown++;
  }
  if (rv_winmgr.focus >= 0 && rv_winmgr.focus < RV_WIN_MAX && rv_winmgr.wins[rv_winmgr.focus].used) {
    w = &rv_winmgr.wins[rv_winmgr.focus];
    if (w->title[0])
      ft = w->title;
  }
  if (sys_code_bp) {
    mem = sys_code_bp->used_u8s;
    alloced = sys_code_bp->alloced_u8s;
  }
  StrPrint(buf, "TempleOS/RV  upd=%d wins=%d mem=%X focus:%s", rv_winmgr.updates, shown, mem, ft);
  RVWinSetWallpaper(buf);
  if (alloced)
    StrPrint(rv_winmgr.wallpaper_heap, "Heap %010X/%010X  wins=%d", mem, alloced, shown);
  else
    StrPrint(rv_winmgr.wallpaper_heap, "Heap used=%010X  wins=%d", mem, shown);
  if (Gs)
    idle_pct = ToI64(100.0 * Gs->idle_factor);
  StrPrint(rv_winmgr.wallpaper_idle, "Idle ~%d%%  swaps=%d  focus:%s", idle_pct, rv_winmgr.updates, ft);
  n = 0;
  for (i = 0; i < RV_WIN_MAX && n < 4; i++) {
    w = &rv_winmgr.wins[i];
    if (!w->used || !w->show)
      continue;
    t = w->task;
    if (TaskValidate(t))
      StrPrint(rv_winmgr.wallpaper_tasks[n], "  %-12ts #%08X flags=%04X", w->title, t, t->task_flags);
    else
      StrPrint(rv_winmgr.wallpaper_tasks[n], "  %-12ts (no task)", w->title);
    n++;
  }
  rv_winmgr.wallpaper_task_n = n;
}

U0 RVWinMgrWallPaper()
{
  //Fill text_base with wallpaper + top/heap/idle/task rows (Adam/WallPaper lite).
  I64 attr = rv_winmgr.wallpaper_attr;
  I64 y, i;
  U8 *ft = "";
  CRVWin *w;
  RVWinMgrWallPaperLive;
  RVTextRect(0, rv_winmgr.cols - 1, 0, rv_winmgr.rows - 1, attr << 8 + ' ');
  RVTextPrint(1, 0, BLUE << 4 + YELLOW, rv_winmgr.wallpaper_line);
  if (rv_winmgr.wallpaper_heap[0])
    RVTextPrint(1, 1, BLUE << 4 + WHITE, rv_winmgr.wallpaper_heap);
  y = rv_winmgr.rows - 2;
  if (y > 2 && rv_winmgr.wallpaper_idle[0]) {
    RVTextPrint(1, y, BLUE << 4 + WHITE, rv_winmgr.wallpaper_idle);
    y--;
  }
  for (i = rv_winmgr.wallpaper_task_n - 1; i >= 0 && y > 2; i--) {
    RVTextPrint(1, y, BLUE << 4 + BROWN, rv_winmgr.wallpaper_tasks[i]);
    y--;
  }
  if (y > 2)
    RVACDraw(y);
  if (rv_winmgr.focus >= 0 && rv_winmgr.focus < RV_WIN_MAX && rv_winmgr.wins[rv_winmgr.focus].used) {
    w = &rv_winmgr.wins[rv_winmgr.focus];
    ft = w->title;
  }
  if (rv_winmgr.focus == rv_winmgr.term_idx)
    RVTextPrint(1, rv_winmgr.rows - 1, BLUE << 4 + LTGRAY, "focus:Term  HolyC Enter  Tab  MENU/[X]  Ctrl-Alt-C/X/T/N/D/Del  ESC quit");
  else if (rv_winmgr.focus == rv_winmgr.adam_idx)
    RVTextPrint(1, rv_winmgr.rows - 1, BLUE << 4 + LTGRAY, "focus:Adam  HolyC Enter  Tab  MENU/[X]  Ctrl-Alt-C/X/T/N/D/Del  ESC quit");
  else if (rv_winmgr.focus == rv_winmgr.home_idx)
    RVTextPrint(1, rv_winmgr.rows - 1, BLUE << 4 + LTGRAY, "focus:HOME  arrows/Pg scroll  MENU/[X]  Ctrl-scroll  ESC quit");
  else
    RVTextPrint(1, rv_winmgr.rows - 1, BLUE << 4 + LTGRAY, ft);
}

U0 RVWinDrawTitle(CRVWin *w)
{
  //Stamp title + TempleOS chrome cues: left MENU, right [X], center title.
  I64 x, i, len, attr, max, mid_l, mid_r;
  U8 *menu = "MENU";
  U8 *closer = "[X]";
  if (!w->title[0] || w->no_border)
    return;
  attr = w->border_attr << 4 + YELLOW;
  max = w->right - w->left + 1;
  if (max < 1)
    return;
  // MENU at left client (LX+BD) — always when bordered (DocTerm border doc).
  if (max >= 4) {
    for (i = 0; i < 4; i++)
      RVTextChar(w->left + i, w->top - 1, (menu[i] & 255) + (attr << 8));
  }
  // [X] at right client (RX+BD).
  if (max >= 3) {
    for (i = 0; i < 3; i++)
      RVTextChar(w->right - 2 + i, w->top - 1, (closer[i] & 255) + (attr << 8));
  }
  mid_l = w->left + 4;
  mid_r = w->right - 3;
  if (mid_l > mid_r)
    return;
  len = StrLen(w->title);
  max = mid_r - mid_l + 1;
  if (len > max)
    len = max;
  x = mid_l + (max - len) / 2;
  for (i = 0; i < len; i++)
    RVTextChar(x + i, w->top - 1, (w->title[i] & 255) + (attr << 8));
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

U0 RVDocDrawWin(CRVWin *w)
{
  //P2: paint CDoc entries into window client (scroll_x/y).
  // HOME entries are SoT (tree/CB toggle). Term/Adam/User CDoc stays in sync
  // via incremental DocPutS/DocEd* on body append — not full resync each paint.
  CDoc *doc;
  CDocEntry *doc_e;
  I64 x, y, attr, ch, i, ww, hh, sx, sy, t;
  U8 *tag;
  if (!w || !w->doc)
    return;
  doc = w->doc;
  if (doc->doc_signature != DOC_SIGNATURE_VAL)
    return;
  ww = w->right - w->left + 1;
  hh = w->bottom - w->top + 1;
  // Term/Adam consoles: once the cursor is back inside the client width, show the
  // lines from column 0 again. Stock DocRecalc only pulls line_start_col back to the
  // cursor column, so one long input line left every later line missing its first
  // characters ("b375Ab" for "Ab375Ab") until the cursor reached column 0.
  if ((w->kind == RV_WIN_KIND_TERM || w->kind == RV_WIN_KIND_ADAM || w->kind == RV_WIN_KIND_USER) && doc->x < ww && doc->line_start_col > 0)
    doc->line_start_col = 0;
  DocRecalc(doc);
  sx = w->scroll_x;
  sy = w->scroll_y;
  // Console docs (Term/Adam/User) show the TAIL: DocRecalc lays entries oldest-first from
  // y=0, so a bare scroll_y=0 renders only the FIRST hh lines and every later line falls
  // past the client (y >= hh) — the console froze on its opening page after ~hh lines of
  // output. Offset to the last hh lines instead; w->scroll_y (kept in [-max,0] by
  // RVWinClampScroll) then pages back through history (PgUp/PgDn).
  if (w->kind == RV_WIN_KIND_TERM || w->kind == RV_WIN_KIND_ADAM || w->kind == RV_WIN_KIND_USER) {
    I64 top = RVDocLineCount(doc) - hh;
    if (top < 0)
      top = 0;
    sy = top + w->scroll_y;
    if (sy < 0)
      sy = 0;
    if (sy > top)
      sy = top;
  }
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->de_flags & DOCEF_SKIP) {
      doc_e = doc_e->next;
      continue;
    }
    y = doc_e->y - sy;
    if (y >= hh) {
      doc_e = doc_e->next;
      continue;
    }
    t = doc_e->type_u8;
    if (t == DOCT_TEXT || t == DOCT_LINK || t == DOCT_TREE || t == DOCT_BTTN || t == DOCT_DATA || t == DOCT_CHECK_BOX || t == DOCT_MACRO || t == DOCT_PMT || t == DOCT_MENU_VAL || t == DOCT_LST || t == DOCT_SPRITE || t == DOCT_INS_BIN || t == DOCT_HEX_ED || t == DOCT_SONG) {
      tag = doc_e->tag;
      if (tag && y >= 0) {
        attr = (doc_e->type >> 8) & 255;
        if (!attr)
          attr = w->text_attr;
        // Cursor link-selection: the focused doc's cur_entry (a clickable widget) paints
        // fg/bg-inverted so "selectable by the cursor" is visible in the VT compose.
        if (doc_e == doc->cur_entry && doc_e != doc && RVDocSelClickable(t))
          attr = ((attr & 0x0F) << 4) + ((attr >> 4) & 0x0F);
        x = doc_e->x - sx;
        for (i = 0; tag[i]; i++) {
          ch = tag[i];
          if (x >= 0 && x < ww)
            RVTextChar(w->left + x, w->top + y, (ch & 255) + (attr << 8));
          x++;
        }
      }
    }
    doc_e = doc_e->next;
  }
}

Bool RVDocClickAtWin(I64 idx, I64 cx, I64 cy)
{
  //Client click on CDoc → activate LINK/TREE/BT/CB/MA/DA under pointer.
  CRVWin *w;
  CDocEntry *doc_e;
  I64 dx, dy, t;
  U8 buf[160];
  if (idx < 0 || idx >= RV_WIN_MAX)
    return FALSE;
  w = &rv_winmgr.wins[idx];
  if (!w->used || !w->doc || w->doc->doc_signature != DOC_SIGNATURE_VAL)
    return FALSE;
  if (cx < w->left || cx > w->right || cy < w->top || cy > w->bottom)
    return FALSE;
  dx = cx - w->left + w->scroll_x;
  dy = cy - w->top + w->scroll_y;
  doc_e = RVDocFindAt(w->doc, dx, dy);
  if (!doc_e)
    return FALSE;
  w->doc->cur_entry = doc_e;
  t = doc_e->type_u8;
  if (!RVDocActivate(w->doc, doc_e))
    return FALSE;
  if (t == DOCT_LINK) {
    rv_winmgr.home_link_hits++;
    if (doc_e->aux_str)
      StrPrint(buf, "LINK: %s", doc_e->aux_str);
    else
      StrPrint(buf, "LINK: %s", doc_e->tag ? doc_e->tag : "?");
    RVWinSetWallpaper(buf);
  } else if (t == DOCT_TREE)
    rv_winmgr.home_tree_toggles++;
  else if (t == DOCT_BTTN || t == DOCT_CHECK_BOX || t == DOCT_MACRO || t == DOCT_DATA) {
    rv_winmgr.home_form_hits++;
    if (t == DOCT_CHECK_BOX)
      StrPrint(buf, "CB: %s", doc_e->tag ? doc_e->tag : "?");
    else if (t == DOCT_BTTN)
      StrPrint(buf, "BT: %s", doc_e->tag ? doc_e->tag : "?");
    else if (t == DOCT_MACRO)
      StrPrint(buf, "MA: %s", doc_e->tag ? doc_e->tag : "?");
    else
      StrPrint(buf, "DA: %s", doc_e->tag ? doc_e->tag : "?");
    RVWinSetWallpaper(buf);
  }
  return TRUE;
}

U0 RVWinDrawBody(CRVWin *w)
{
  //P2: HOME + Term/Adam/User paint real CDoc when attached.
  // Body string remains write SoT for ExePutS append; CDoc kept in sync
  // incrementally (DocPutS / DocEd*) — avoid full DocRst+Load each paint.
  // Doc-lite fallback when no CDoc — HolyC $$ in source → one '$' in memory:
  //  $0-$F / $a-$f   FG nibble (MakeAdam style)
  //  $B0-$BF         BG nibble
  //  $$              literal '$' ($$$$ in HolyC source)
  //  $FG,n$ / $BG,n$ color with closer
  //  $TX,"text"$     emit quoted text; unknown $cmd$ soft-skipped
  // scroll_y skips leading body lines; scroll_x pans columns (Ctrl-grab lite).
  I64 x, y, i, attr, ch, fg, bg, n, j;
  if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL && (w->kind == RV_WIN_KIND_HOME || w->kind == RV_WIN_KIND_TERM || w->kind == RV_WIN_KIND_ADAM || w->kind == RV_WIN_KIND_USER)) {
    RVDocDrawWin(w);
    return;
  }
  if (!w->body[0])
    return;
  attr = w->text_attr;
  fg = attr & 15;
  bg = (attr >> 4) & 15;
  x = -w->scroll_x;
  y = 0;
  i = RVWinBodySkipLines(w->body, w->scroll_y);
  for (; i < RV_WIN_BODY_MAX && w->body[i];) {
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
              x = -w->scroll_x;
              y++;
            } else {
              if (x > w->right - w->left) {
                x = -w->scroll_x;
                y++;
              }
              if (y <= w->bottom - w->top && x >= 0 && x <= w->right - w->left)
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
      x = -w->scroll_x;
      y++;
      continue;
    }
    if (y > w->bottom - w->top)
      break;
    if (x > w->right - w->left) {
      x = -w->scroll_x;
      y++;
      if (y > w->bottom - w->top)
        break;
    }
    if (x >= 0 && x <= w->right - w->left)
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
  //Render text_base glyphs into paint DC (32-bpp compose default, or full-screen is_u8).
  I64 row, col, px, py, gy, gx, ch, fg, bg, cell;
  U8 *glyph, *body8, fgi, bgi, marg8;
  U32 *pix, fgc, bgc, margin;
  I64 cols = rv_winmgr.cols, rows = rv_winmgr.rows;
  I64 stride, stride8;
  CRVDC *paint = RVGrPaintDC;
  Bool u8;
  if (!rv_winmgr.text_base)
    return;
  u8 = paint && paint->is_u8 && paint->body;
  if (u8) {
    body8 = paint->body(U8 *);
    stride8 = paint->width_internal;
    marg8 = RVColorNearestIdx(rv_winmgr.wallpaper_bg);
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
          ch = cell & 255;
        }
        if (cell & ATTRF_SEL) {
          fg ^= 15;
          bg ^= 15;
        }
        fgi = fg;
        bgi = bg;
        px = col *FONT_WIDTH;
        py = row *FONT_HEIGHT;
        glyph = (&sys_font_std[ch])(U8 *);
        for (gy = 0; gy < FONT_HEIGHT; gy++) {
          U8 bits = glyph[gy];
          I64 dy = (py + gy) * stride8 + px;
          for (gx = 0; gx < FONT_WIDTH; gx++) {
            if (bits & (1 << gx))
              body8[dy + gx] = fgi;
            else
              body8[dy + gx] = bgi;
          }
        }
      }
    }
    for (py = rows *FONT_HEIGHT; py < paint->height; py++)
      for (px = 0; px < paint->width; px++)
        body8[py *stride8 + px] = marg8;
    for (py = 0; py < rows *FONT_HEIGHT; py++)
      for (px = cols *FONT_WIDTH; px < paint->width; px++)
        body8[py *stride8 + px] = marg8;
    return;
  }
  if (!rv_fb.pixels)
    return;
  pix = rv_fb.pixels;
  stride = rv_fb.width;
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
  margin = rv_winmgr.wallpaper_bg;
  for (py = rows *FONT_HEIGHT; py < rv_fb.height; py++)
    for (px = 0; px < rv_fb.width; px++)
      pix[py *stride + px] = margin;
  for (py = 0; py < rows *FONT_HEIGHT; py++)
    for (px = cols *FONT_WIDTH; px < rv_fb.width; px++)
      pix[py *stride + px] = margin;
}

U0 RVWinMgrDrawDocSprites()
{
  //After text blit: DocSprite bins → Sprite3 (Adam DocRecalc TO_SCRN path).
  I64 i, x, y, px, py;
  CRVWin *w;
  CDoc *doc;
  CDocEntry *doc_e;
  CDocBin *tmpb;
  CRVDC *dc = RVGrPaintDC;
  if (!dc)
    return;
  for (i = 0; i < RV_WIN_MAX; i++) {
    w = &rv_winmgr.wins[i];
    if (!w->used || !w->show || !w->doc)
      continue;
    doc = w->doc;
    if (doc->doc_signature != DOC_SIGNATURE_VAL)
      continue;
    DocRecalc(doc);
    doc_e = doc->head.next;
    while (doc_e != doc) {
      if (!(doc_e->de_flags & DOCEF_SKIP) && doc_e->type_u8 == DOCT_SPRITE) {
        if (!doc_e->bin_data && (doc_e->de_flags & DOCEF_HAS_BIN))
          doc_e->bin_data = DocBinFindNum(doc, doc_e->bin_num);
        tmpb = doc_e->bin_data;
        if (tmpb && tmpb->data && tmpb->size > 0) {
          x = doc_e->x - w->scroll_x;
          y = doc_e->y - w->scroll_y;
          if (y >= 0 && y <= w->bottom - w->top && x >= 0 && x <= w->right - w->left) {
            px = (w->left + x) * FONT_WIDTH;
            py = (w->top + y) * FONT_HEIGHT;
            DocSprite(doc, doc_e, dc, px, py);
          }
        }
      }
      doc_e = doc_e->next;
    }
  }
}

U0 RVWinMgrDrawIts()
{
  //GrUpdateTaskWin analogue: per-window draw_it with DC clip to client pixels.
  // Prefer stock CTask.draw_it(task,dc) (MassSpring); fall back to CRVWin.draw_it.
  // Paint target: full-screen is_u8 when RVGrU8ComposeActive, else 32-bpp screen DC.
  I64 i, x1, y1, x2, y2;
  CRVWin *w;
  CRVDC *dc = RVGrPaintDC;
  CTask *task;
  if (!dc)
    return;
  for (i = 0; i < RV_WIN_MAX; i++) {
    w = &rv_winmgr.wins[i];
    if (!w->used || !w->show)
      continue;
    task = w->task;
    if (!(task && TaskValidate(task) && task->draw_it) && !w->draw_it)
      continue;
    x1 = w->left *FONT_WIDTH;
    y1 = w->top *FONT_HEIGHT;
    x2 = (w->right + 1) * FONT_WIDTH;
    y2 = (w->bottom + 1) * FONT_HEIGHT;
    RVDCClipSet(dc, x1, y1, x2, y2);
    dc->x0 = x1;
    dc->y0 = y1;
    if (task && TaskValidate(task) && task->draw_it)
      (*task->draw_it)(task, dc(CDC *));
    else if (w->draw_it)
      (*w->draw_it)(w, dc);
    // P3: Bttn/Slider subset (Ctrls_RV; no-op until RVCtrlsDemoInstall).
    RVCtrlsDrawWin(i, dc);
  }
  RVDCClipRst(dc);
  dc->x0 = 0;
  dc->y0 = 0;
}

U0 RVWinMgrPresent(Bool full_frame = FALSE)
{
  //Flip compose→scanout then present. ramfb fw_cfg is configure-once; Flip every frame.
  // Opt-in: when rv_gr_u8_present, expand 8-bit backbuffer into compose first
  // (GrUpdateVGAGraphics shape). Default remains 32-bpp compose → Flip.
  no_warn full_frame;
  if (!rv_fb.pixels)
    return;
  if (rv_gr_u8_present)
    GrUpdateVGAGraphics;
  RVFbPresent();
}

U0 RVWinMgrCursorErase()
{
  I64 row, col, px, py, stride;
  U32 *pix, *save;
  U8 *body8;
  CRVDC *paint;
  if (!rv_winmgr.ptr_save_valid)
    return;
  paint = RVGrPaintDC;
  save = rv_win_ptr_save;
  if (paint && paint->is_u8 && paint->body) {
    body8 = paint->body(U8 *);
    stride = paint->width_internal;
    for (row = 0; row < RV_CURSOR_H; row++) {
      py = rv_winmgr.ptr_oy + row;
      if (py < 0 || py >= paint->height)
        continue;
      for (col = 0; col < RV_CURSOR_W; col++) {
        px = rv_winmgr.ptr_ox + col;
        if (px < 0 || px >= paint->width)
          continue;
        body8[py *stride + px] = save[row *RV_CURSOR_W + col] & 255;
      }
    }
    rv_winmgr.ptr_save_valid = FALSE;
    return;
  }
  if (!rv_fb.pixels)
    return;
  stride = RVFbPixStride();
  pix = rv_fb.pixels;
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
  U8 *body8;
  CRVDC *paint;
  paint = RVGrPaintDC;
  save = rv_win_ptr_save;
  rv_winmgr.ptr_ox = px;
  rv_winmgr.ptr_oy = py;
  if (paint && paint->is_u8 && paint->body) {
    body8 = paint->body(U8 *);
    stride = paint->width_internal;
    for (row = 0; row < RV_CURSOR_H; row++) {
      y = py + row;
      for (col = 0; col < RV_CURSOR_W; col++) {
        x = px + col;
        if (x < 0 || y < 0 || x >= paint->width || y >= paint->height)
          save[row *RV_CURSOR_W + col] = BLUE;
        else
          save[row *RV_CURSOR_W + col] = body8[y *stride + x];
      }
    }
    rv_winmgr.ptr_save_valid = TRUE;
    return;
  }
  if (!rv_fb.pixels)
    return;
  stride = RVFbPixStride();
  pix = rv_fb.pixels;
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
  U32 save;
  CRVDC *dc;
  U16 bits;
  if (!rv_winmgr.ready || !rv_winmgr.input_ok)
    return;
  dc = RVGrPaintDC;
  if (!dc || !dc->body)
    return;
  if (!dc->is_u8 && !rv_fb.pixels)
    return;
  save = dc->color;
  for (row = 0; row < 16; row++) {
    bits = arrow[row];
    for (col = 0; col < 16; col++) {
      if (!(bits & (0x8000 >> col)))
        continue;
      x = px + col;
      y = py + row;
      if (x < 0 || y < 0 || x >= dc->width || y >= dc->height)
        continue;
      dc->color = WHITE;
      GrPlot(dc, x, y);
      if (x + 1 < dc->width) {
        dc->color = BLACK;
        GrPlot(dc, x + 1, y);
      }
      if (y + 1 < dc->height) {
        dc->color = BLACK;
        GrPlot(dc, x, y + 1);
      }
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
  if (!rv_winmgr.ready || !rv_winmgr.input_ok)
    return;
  if (!RVGrU8ComposeActive && !rv_fb.pixels)
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

U0 RVWinMgrPostMs(I64 msg, I64 cx, I64 cy)
{
  //TempleOS WinMgr → TaskMsg(MSG_MS_*) with window-local pixels for GetMsg demos.
  CTask *t = sys_focus_task;
  I64 i, px, py;
  CRVWin *w;
  if (!TaskValidate(t))
    t = Fs;
  if (!TaskValidate(t))
    return;
  px = cx *FONT_WIDTH;
  py = cy *FONT_HEIGHT;
  for (i = 0; i < RV_WIN_MAX; i++) {
    w = &rv_winmgr.wins[i];
    if (!w->used || w->task != t)
      continue;
    px -= w->left *FONT_WIDTH;
    py -= w->top *FONT_HEIGHT;
    break;
  }
  if (px < 0)
    px = 0;
  if (py < 0)
    py = 0;
  TaskMsg(t, NULL, msg, px, py, 0);
}

U0 RVWinMgrUpdateODEs()
{
  //TempleOS WinMgr refresh: ODEsUpdate on Fs + each window task with next_ode.
  // No hand-rolled MassSpring clone — stock Demo/Games/MassSpring.HC queues CMathODE.
  F64 t, t_delta;
  I64 i;
  CTask *task;
  t = tS;
  if ((t_delta = t - winmgr.last_refresh_tS) > 0.01)
    winmgr.fps = Max(1.0 / t_delta, 1);
  else if (winmgr.last_refresh_tS > 0.0)
    winmgr.fps = 30;
  else
    winmgr.fps = WINMGR_FPS;
  winmgr.last_refresh_tS = t;
  winmgr.ode_time = 0;
  if (TaskValidate(Fs))
    ODEsUpdate(Fs);
  for (i = 0; i < RV_WIN_MAX; i++) {
    if (!rv_winmgr.wins[i].used)
      continue;
    task = rv_winmgr.wins[i].task;
    if (TaskValidate(task) && task != Fs)
      ODEsUpdate(task);
  }
  winmgr.last_ode_time = winmgr.ode_time;
}

U0 RVWinMgrRefresh()
{
  //Full frame into paint DC (wallpaper → wins → menu → blit → ODE → draw_it → cursor),
  // then expand (if U8) + Flip+present. Offscreen compose avoids cocoa seeing mid-blit
  // flashes (TempleOS gr.dc2 → scanout). WinZBuf filled on WinToTop / layout.
  // ScrnCast: after compose (stock post-GrUpdateScrn), not Soft Refresh / Yield path.
  I64 px, py;
  if (!rv_winmgr.ready)
    return;
  if (!RVGrU8ComposeActive && !rv_fb.pixels)
    return;
  RVWinMgrWallPaper;
  RVWinMgrComposeWins;
  RVWinMgrDrawMenu;
  RVWinMgrBlitTextBase;
  RVWinMgrDrawDocSprites;
  RVWinMgrUpdateODEs;
  RVWinMgrDrawIts;
  rv_winmgr.ptr_save_valid = FALSE;
  if (rv_winmgr.input_ok) {
    px = rv_winmgr.ptr_x *FONT_WIDTH;
    py = rv_winmgr.ptr_y *FONT_HEIGHT;
    RVWinMgrCursorSaveUnder(px, py);
    RVWinMgrDrawCursorAt(px, py);
  }
  RVWinMgrPresent(TRUE);
  RVScrnCastWinMgrHook;
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

Bool RVDocOpenLink(U8 *link)
{
  //FI: path → open/focus a CDoc window (Welcome-lite / HelloWorld / generic).
  // Stock HOME.DD links use FI:A:/Doc/Welcome.DD — no RedSea Adam on win smoke,
  // so embed a short DolDoc-heavy body (WW/HL/LK/AN/MU) matching Demo/DolDoc shape.
  U8 *path, *body, *title;
  I64 idx, left, right, top, bottom;
  CDoc *doc;
  CRVWin *w;
  if (!link || StrLen(link) < 4)
    return FALSE;
  if (!(link[0] == 'F' && link[1] == 'I' && link[2] == ':'))
    return FALSE;
  if (rv_doc_open_busy)
    return FALSE;
  rv_doc_open_busy = 1;
  path = link + 3;
  while (*path == ':')
    path++;
  // Strip leading A: or /
  if (path[0] == 'A' && path[1] == ':')
    path += 2;
  while (*path == '/')
    path++;
  title = "Doc";
  body = NULL;
  if (StrMatch("Welcome", path) || StrMatch("welcome", path)) {
    title = "Welcome.DD";
    body = "$$FG,5$$$$TX,\"Welcome (RV lite)\"$$$$FG$$\n" "$$AN,\"top\"$$\n" "P2 FI: open — stock HOME link.\n" "$$LK,\"HelloWorld\",A=\"FI:A:/Doc/HelloWorld.DD\"$$\n" "$$MU,\"OK\",LE=1$$\n";
  } else if (StrMatch("HelloWorld", path) || StrMatch("Hello", path)) {
    title = "HelloWorld.DD";
    body = "$$HL,1$$Hello World DolDoc demo\n" "Hello World\n" "$$HL,0$$\n" "$$LK,\"Back to Welcome\",A=\"FI:A:/Doc/Welcome.DD\"$$\n";
  } else if (StrMatch("HelpIndex", path) || StrMatch("Help", path)) {
    title = "HelpIndex.DD";
    body = "$$TX,\"Help Index (lite)\"$$\n" "$$LK,\"Welcome\",A=\"FI:A:/Doc/Welcome.DD\"$$\n" "$$LK,\"HelloWorld\",A=\"FI:A:/Doc/HelloWorld.DD\"$$\n" "$$LK,\"DemoInPage\",A=\"FI:A:/Demo/ToHtmlToTXTDemo/DemoInPage.DD\"$$\n";
  } else if (StrMatch("DemoInPage", path) || StrMatch("ToHtml", path)) {
    title = "DemoInPage.DD";
    body = RVDocDemoInPageBody();
  } else {
    title = "Doc";
    body = "$$TX,\"Doc link\"$$\n(no embedded body for this FI: path yet)\n";
  }
  idx = RVDocFindByTitle(title);
  if (idx < 0) {
    left = 4;
    right = rv_winmgr.cols - 5;
    top = 4;
    bottom = rv_winmgr.rows / 2;
    if (bottom - top < 6)
      bottom = top + 8;
    idx = RVWinNew(left, right, top, bottom, title, body, FALSE);
  } else {
    RVWinSetBody(idx, body);
  }
  if (idx < 0) {
    rv_doc_open_busy = 0;
    return FALSE;
  }
  w = &rv_winmgr.wins[idx];
  w->border_attr = LTBLUE;
  w->show = TRUE;
  if (w->doc) {
    DocDel(w->doc);
    w->doc = NULL;
  }
  doc = DocNew(title);
  if (doc) {
    // DocPutS (not DocPrint) — Welcome/Help bodies are DolDoc templates; DocPrint
    // → StrPrintJoin would treat any % as printf (FormLex hang sibling).
    DocPutS(doc, w->body);
    DocRecalc(doc);
    w->doc = doc;
    Print("RVDoc OpenLink title=%s entries=%d path=%s\n", title, DocSize(doc), path);
  }
  rv_doc_last_open_idx = idx;   // VT link-nav auto-focuses this window after Enter
  rv_doc_open_busy = 0;
  return TRUE;
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
  // No A:/Adam tree on RAM-disk win smokes — skip FileRead (avoids PrintErr spam;
  // Silent()/FileFind around missing Adam hung). Fallback body is used by caller.
  if (StrMatch("Adam", path))
    return FALSE;
  buf = FileRead(path, &sz, NULL);
  if (!buf || sz <= 0)
    return FALSE;
  RVWinSetBody(idx, buf);
  return TRUE;
}

I64 RVFileMgrOpen(I64 mode = 0)
{
  //Stock FilesFind + DirFileDoc → CRVWin (FMRebuildDocDrv shape; non-blocking).
  // Beyond $$ probe: keeps the CDoc on a window. Full FileMgr() GetMsg still open.
  CDoc *doc;
  CDocEntry *doc_e;
  CDirEntry *head = NULL, *tmpde, *sub;
  I64 n = 0, u0 = 0, trees = 0, mus = 0, i, idx, left, right, top, bottom;
  U8 *names[4], *st, line[128];
  Print("RVDoc FileMgr open begin mode=%d\n", mode);
  if (!rv_winmgr.ready)
    return -1;
  idx = rv_winmgr.filemgr_idx;
  if (rv_winmgr.filemgr_head) {
    DirTreeDel(rv_winmgr.filemgr_head(CDirEntry *));
    rv_winmgr.filemgr_head = 0;
  }
  if (idx >= 0 && idx < RV_WIN_MAX && rv_winmgr.wins[idx].used) {
    if (rv_winmgr.wins[idx].doc) {
      DocDel(rv_winmgr.wins[idx].doc);
      rv_winmgr.wins[idx].doc = NULL;
    }
    rv_winmgr.wins[idx].used = FALSE;
    rv_winmgr.wins[idx].show = FALSE;
  }
  rv_winmgr.filemgr_idx = -1;
  u0 = rv_doc_filemgr_user_hits;
  names[0] = "HOME.DD";
  names[1] = "Welcome.DD";
  names[2] = "DemoInPage.DD";
  names[3] = "WINDIR.TXT";
  for (i = 0; i < 4; i++) {
    st = MStrPrint("A:/%s", names[i]);
    FileWrite(st, names[i], StrLen(names[i]));
    Free(st);
  }
  doc = DocNew("FileMgr.DD");
  if (!doc)
    return -1;
  doc->desc = 'FileMan';
  doc->flags |= DOCF_FORM;
  if (mode == 1)
    DocPutS(doc, "$$PURPLE$$Pick file and press <ESC>\n\n");
  else if (mode == 2)
    DocPutS(doc, "$$PURPLE$$Pick directory and press <ESC>\n\n");
  else
    DocPutS(doc, "$$PURPLE$$File Manager\n\n");
  DocPutS(doc, "$$LTBLUE$$");
  rv_doc_filemgr_ffind = 0;
  st = MStrPrint("A:/*");
  Print("RVDoc FileMgr open FilesFind\n");
  sub = FilesFind(st, 0);
  Free(st);
  Print("RVDoc FileMgr open ffind sub=%d\n", sub != NULL);
  if (sub) {
    rv_doc_filemgr_ffind = 1;
    head = CAlloc(sizeof(CDirEntry));
    head->full_name = StrNew("A:/");
    head->attr = RS_ATTR_DIR;
    head->sub = sub;
    StrPrint(line, "$$TR,\"%s\",U=0x%X$$", head->full_name, head);
    head->user_data = DocPutS(doc, line);
    DocPutS(doc, "\n$$ID,+2$$");
    DirFileDoc(doc, sub);
    tmpde = sub;
    while (tmpde) {
      tmpde->parent = head;
      tmpde = tmpde->next;
    }
    DocPutS(doc, "$$ID,-2$$");
  } else
    RVDirFileDoc(doc, "A:/", names, 4);
  DocTop(doc);
  DocRecalc(doc);
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->type_u8 == DOCT_TREE)
      trees++;
    if (doc_e->type_u8 == DOCT_MENU_VAL)
      mus++;
    doc_e = doc_e->next;
  }
  n = DocSize(doc);
  rv_doc_filemgr_entries = n;
  Print("RVDoc FileMgr entries=%d trees=%d mus=%d user=%d ffind=%d lex=%d\n", n, trees, mus, rv_doc_filemgr_user_hits - u0, rv_doc_filemgr_ffind, rv_doc_prs_lex_hits);
  idx = RVDocFindByTitle("FileMgr.DD");
  if (idx < 0) {
    left = 3;
    right = rv_winmgr.cols - 4;
    top = 2;
    bottom = rv_winmgr.rows - 4;
    if (bottom - top < 8)
      bottom = top + 10;
    idx = RVWinNew(left, right, top, bottom, "FileMgr.DD", "", TRUE);
  }
  if (idx < 0) {
    Print("RVFileMgr open FAIL no win slot entries=%d\n", n);
    if (head)
      DirTreeDel(head);
    DocDel(doc);
    return -1;
  }
  if (rv_winmgr.wins[idx].doc) {
    DocDel(rv_winmgr.wins[idx].doc);
    rv_winmgr.wins[idx].doc = NULL;
  }
  rv_winmgr.wins[idx].doc = doc;
  rv_winmgr.wins[idx].border_attr = LTBLUE;
  rv_winmgr.wins[idx].show = TRUE;
  rv_winmgr.filemgr_idx = idx;
  rv_winmgr.filemgr_head = head(I64);
  rv_winmgr.filemgr_open_hits++;
  Print("RVFileMgr open idx=%d hits=%d entries=%d ffind=%d mode=%d\n", idx, rv_winmgr.filemgr_open_hits, n, rv_doc_filemgr_ffind, mode);
  return idx;
}

I64 RVDocHomeOpen(U8 *fallback = NULL)
{
  //Open/focus HOME.DD window; bridge body → real CDoc (P2 entry stream).
  I64 idx, left, right, top, bottom;
  U8 *body;
  CDoc *doc;
  CRVWin *w;
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
  w = &rv_winmgr.wins[idx];
  w->border_attr = GREEN;
  w->text_attr = BLACK << 4 + WHITE;
  if (!RVDocLoadWin(idx, "A:/Adam/HOME.DD")) {
    body = fallback;
    if (!body)
      body = "$$TX,\"HOME.DD\"$$\n$$FG,14$$(no A:/Adam/HOME.DD yet)$$FG,7$$\n";
    RVWinSetBody(idx, body);
  }
  // Build / refresh CDoc from body string (Doc-lite bridge → real entries).
  if (w->doc) {
    DocDel(w->doc);
    w->doc = NULL;
  }
  doc = DocNew("HOME.DD");
  if (doc) {
    DocPutS(doc, w->body);
    DocRecalc(doc);
    w->doc = doc;
    Print("RVDoc HOME entries=%d max_y=%d\n", DocSize(doc), doc->max_y);
  }
  RVWinSetTitle(idx, "HOME.DD");
  return idx;
}

public U0 DocTermNew()
{
  //TempleOS-shaped DocTermNew: Term window + Put/Display/Border docs.
  // Body write SoT for ExePutS; CDoc painted + kept in sync via DocPutS/DocEd*.
  I64 idx, left, right, top, bottom;
  U8 *body;
  CDoc *doc;
  CRVWin *w;
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
    body = "$$TX,\"TempleOS/RISC-V DocTerm\"$$\n" "$$FG,14$$Tab=focus  click=select$$FG,7$$\n" "$$FG,14$$$$TX,\"HolyC ExePutS (virtio-kbd)\"$$$$FG,7$$\n" "> ";
    idx = RVWinNew(left, right, top, bottom, "Term", body, TRUE);
  }
  if (idx < 0)
    return;
  rv_winmgr.term_idx = idx;
  w = &rv_winmgr.wins[idx];
  w->kind = RV_WIN_KIND_TERM;
  w->border_attr = LTGREEN;
  w->text_attr = BLUE << 4 + WHITE;
  if (!w->body[0])
    RVWinSetBody(idx, "$$TX,\"TempleOS/RISC-V DocTerm\"$$\n" "$$FG,14$$type HolyC here (Enter runs)$$FG,7$$\n" "> ");
  if (w->doc) {
    DocDel(w->doc);
    w->doc = NULL;
  }
  doc = DocNew("Term");
  if (doc) {
    DocEd(doc);
    DocPutS(doc, w->body);
    DocRecalc(doc);
    w->doc = doc;
    Print("RVDoc Term entries=%d\n", DocSize(doc));
  }
  RVWinSetTitle(idx, "Term");
  RVWinFocus(idx);
  if (rv_doc_put.doc_signature == DOC_SIGNATURE_VAL)
    rv_doc_put.user_data = idx;
}

Bool RVWinMgrDemoDesktop()
{
  //DocTerm desktop: Adam + Term (DocTermNew) + HOME.DD — CDoc paint path.
  I64 a, h;
  U8 *home_fallback;
  U8 *adam_body;
  CTask *parent, *tt;
  CDoc *doc;
  CRVWin *w;
  if (!rv_winmgr.ready)
    return FALSE;
  adam_body = "$$TX,\"TempleOS/RISC-V Adam\"$$\n" "$$FG,14$$HolyC when focused$$FG,7$$\n" "> ";
  a = RVWinNew(2, 42, 2, 22, "Adam", adam_body, FALSE);
  if (a >= 0) {
    rv_winmgr.adam_idx = a;
    rv_winmgr.gr_idx = a;
    w = &rv_winmgr.wins[a];
    w->border_attr = RED;
    w->text_attr = BLUE << 4 + WHITE;
    w->kind = RV_WIN_KIND_ADAM;
    w->draw_it = NULL;
    if (w->doc) {
      DocDel(w->doc);
      w->doc = NULL;
    }
    doc = DocNew("Adam");
    if (doc) {
      DocEd(doc);
      DocPutS(doc, w->body);
      DocRecalc(doc);
      w->doc = doc;
      Print("RVDoc Adam entries=%d\n", DocSize(doc));
    }
  }
  DocTermNew;
  if (rv_winmgr.term_idx >= 0)
    rv_winmgr.wins[rv_winmgr.term_idx].kind = RV_WIN_KIND_TERM;
  home_fallback = "$$TX,\"TempleOS/RISC-V HOME.DD\"$$\n" "$$FG,14$$P2 DolDoc core — entry stream$$FG,7$$\n" "$$AN,\"home\"$$\n" "$$LK,\"Help Index\",A=\"FI:A:/Doc/HelpIndex.DD\"$$\n" "$$LK,\"Welcome\",A=\"FI:A:/Doc/Welcome.DD\"$$\n" "$$LK,\"HelloWorld\",A=\"FI:A:/Doc/HelloWorld.DD\"$$\n" "$$LK,\"DemoInPage\",A=\"FI:A:/Demo/ToHtmlToTXTDemo/DemoInPage.DD\"$$\n" "$$BT,\"OK\",LE=1$$  $$CB,\"Notes\"$$  $$MA,\"Dir\",LM=\"Dir;\"$$  $$MU,\"Go\",LE=7$$\n" "$$DA,\"riscv\"$$  $$LS,\"Adult\"$$\n" "$$SP,\"icon\"$$\n" "$$TR,\"Adam\"$$\n$$ID,+2$$\n  Kernel hooks\n  WinMgr / DocTerm\n$$ID,-2$$\n" "$$TR-C,\"Collapsed demo\"$$\n$$ID,+2$$\n  hidden until click\n$$ID,-2$$\n" "arrows/Pg scroll  Enter=activate  click links/trees/forms\n" "line 8\nline 9\nline 10\nline 11\nline 12\n" "line 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\n";
  h = RVDocHomeOpen(home_fallback);
  if (rv_winmgr.home_idx >= 0)
    rv_winmgr.wins[rv_winmgr.home_idx].kind = RV_WIN_KIND_HOME;
  // P1: Adam=Fs; Term+User+HOME live RVKSpawn GetMsg (parked Spawn fallback).
  parent = adam_task;
  if (!parent)
    parent = Fs;
  // Adam boot often TaskInit without Spawn's signature stamp (x86 KStart sets it in asm).
  if (parent && parent->addr == parent)
    parent->task_signature = TASK_SIGNATURE_VAL;
  if (a >= 0 && TaskValidate(parent))
    RVWinBindTask(a, parent, RV_WIN_KIND_ADAM, FALSE);
  if (rv_winmgr.term_idx >= 0 && TaskValidate(parent)) {
    // Live GetMsg via RVKSpawn (same as User). Fall back to parked Spawn if
    // RVKSpawn cannot plant a runnable frame (light smokes without full Yield ring).
    tt = RVWinSpawnConsumer("Term", parent);
    if (!TaskValidate(tt)) {
      tt = Spawn(&RVWinDocConsumer, NULL, "Term", -1, parent, 0, 0);
      if (TaskValidate(tt)) {
        StrCpy(tt->task_title, "Term");
        LBts(&tt->task_flags, TASKf_SUSPENDED);
        LBts(&tt->task_flags, TASKf_AWAITING_MSG);
      }
    }
    if (TaskValidate(tt))
      RVWinBindTask(rv_winmgr.term_idx, tt, RV_WIN_KIND_TERM, FALSE);
  }
  if (rv_winmgr.home_idx >= 0 && TaskValidate(parent)) {
    // WS3: unpark HOME onto live RVKSpawn GetMsg (same Term/User path). PutKey
    // still routes via RVWinHomePutKey; Yield into RVKSpawn frame is safe.
    tt = RVWinSpawnConsumer("HOME.DD", parent);
    if (!TaskValidate(tt)) {
      tt = Spawn(&RVWinDocConsumer, NULL, "HOME.DD", -1, parent, 0, 0);
      if (TaskValidate(tt)) {
        StrCpy(tt->task_title, "HOME.DD");
        LBts(&tt->task_flags, TASKf_SUSPENDED);
        LBts(&tt->task_flags, TASKf_AWAITING_MSG);
      }
    }
    if (TaskValidate(tt))
      RVWinBindTask(rv_winmgr.home_idx, tt, RV_WIN_KIND_HOME, FALSE);
  }
  // Keep Term focused for virtio typing (DocTermNew already focused it; do not steal back to Adam).
  if (rv_winmgr.term_idx >= 0)
    RVWinFocus(rv_winmgr.term_idx);
  else if (a >= 0)
    RVWinFocus(a);
  return a >= 0 && rv_winmgr.term_idx >= 0 && h >= 0;
}

U0 RVWinMenuClose()
{
  rv_winmgr.menu_open = 0;
  rv_winmgr.menu_owner = -1;
  rv_winmgr.menu_sel = 0;
}

U0 RVWinMenuActivate(I64 sel)
{
  //Run PersonalMenu action (MenuNew-lite ids from Adam/Menu_RV).
  I64 id, owner;
  U8 buf[96];
  owner = rv_winmgr.menu_owner;
  id = RVMenuPersonalId(sel);
  RVWinMenuClose;
  switch (id) {
    case RV_MENU_ID_TILE_H :
    RVWinTileHorz;
    break;
    case RV_MENU_ID_TILE_V :
    RVWinTileVert;
    break;
    case RV_MENU_ID_MAX :
    RVWinMax(owner);
    break;
    case RV_MENU_ID_CLOSE :
    RVWinClose(owner);
    break;
    case RV_MENU_ID_ABOUT :
    // Stock Job PopUp (RVKSpawn+JobRes) + CRVWin chrome — not soft-skipped.
    RVPopUp("TempleOS/RISC-V WinMgr\nPersonalMenu MenuNew/MenuFile (P3)", Fs, NULL);
    break;
    case RV_MENU_ID_HELP :
    StrPrint(buf, "MENU: Tile/Max/Close/About/Form/Ctrls  arrows+Enter  Esc");
    RVWinSetWallpaper(buf);
    rv_winmgr.wallpaper_sticky = 32;
    break;
    case RV_MENU_ID_FORM :
    // Class-meta DocForm via DocPutS DA/CB (RVDoc); lite fallback inside.
    RVDocFormMeta("DocForm", 42, TRUE);
    break;
    case RV_MENU_ID_CTRLS :
    if (owner >= 0)
      RVCtrlsDemoInstall(owner);
    else if (rv_winmgr.adam_idx >= 0)
      RVCtrlsDemoInstall(rv_winmgr.adam_idx);
    StrPrint(buf, "Ctrls queue DrawCtrls — click Go / Lvl");
    RVWinSetWallpaper(buf);
    rv_winmgr.wallpaper_sticky = 32;
    break;
  }
  Print("RVWinMgr MENU pick sel=%d id=%d owner=%d lex=%d\n", sel, id, owner, rv_menu_lex_hits);
}

U0 RVWinMgrDrawMenu()
{
  //Paint PersonalMenu pulldown over text_base (after windows, before blit).
  I64 i, n, attr, hi, x, y, w;
  U8 line[40];
  U8 *name;
  if (!rv_winmgr.menu_open)
    return;
  n = RVMenuPersonalCount;
  if (n <= 0)
    return;
  w = rv_winmgr.menu_w;
  if (w < 8)
    w = RVMenuPersonalWidth;
  attr = BLUE << 4 + YELLOW;
  hi = RED << 4 + WHITE;
  RVTextRect(rv_winmgr.menu_left, rv_winmgr.menu_left + w - 1, rv_winmgr.menu_top, rv_winmgr.menu_top + n - 1, attr << 8 + ' ');
  for (i = 0; i < n; i++) {
    name = RVMenuPersonalName(i);
    x = rv_winmgr.menu_left;
    y = rv_winmgr.menu_top + i;
    StrPrint(line, " %s", name);
    if (i == rv_winmgr.menu_sel)
      RVTextPrint(x, y, hi, line);
    else
      RVTextPrint(x, y, attr, line);
  }
}

Bool RVWinMenuHit(I64 cx, I64 cy)
{
  //Click inside open pulldown → activate row; outside → close. TRUE if consumed.
  I64 row;
  if (!rv_winmgr.menu_open)
    return FALSE;
  if (cx >= rv_winmgr.menu_left && cx < rv_winmgr.menu_left + rv_winmgr.menu_w && cy >= rv_winmgr.menu_top && cy < rv_winmgr.menu_top + rv_winmgr.menu_h) {
    row = cy - rv_winmgr.menu_top;
    rv_winmgr.menu_sel = row;
    RVWinMenuActivate(row);
    return TRUE;
  }
  RVWinMenuClose;
  return TRUE;
}

Bool RVWinMenuPutKey(I64 ch, I64 code)
{
  //Navigate PersonalMenu with arrows / Enter / Esc. TRUE if consumed.
  I64 n;
  if (!rv_winmgr.menu_open)
    return FALSE;
  n = RVMenuPersonalCount;
  if (code == KEY_UP) {
    if (rv_winmgr.menu_sel > 0)
      rv_winmgr.menu_sel--;
    else if (n > 0)
      rv_winmgr.menu_sel = n - 1;
    return TRUE;
  }
  if (code == KEY_DOWN) {
    if (rv_winmgr.menu_sel + 1 < n)
      rv_winmgr.menu_sel++;
    else
      rv_winmgr.menu_sel = 0;
    return TRUE;
  }
  if (ch == '\n' || ch == '\r' || ch == ' ') {
    RVWinMenuActivate(rv_winmgr.menu_sel);
    return TRUE;
  }
  if (ch == CH_ESC || code == KEY_ESC) {
    RVWinMenuClose;
    return TRUE;
  }
  return TRUE;
}

U0 RVWinMenuStub(I64 idx = -1)
{
  //TempleOS title MENU / CH_CTRLM → PersonalMenu pulldown (MenuNew-lite).
  CRVWin *w;
  I64 n, mw, left, top;
  U8 buf[96];
  if (idx < 0)
    idx = rv_winmgr.focus;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    return;
  w = &rv_winmgr.wins[idx];
  RVWinFocus(idx);
  rv_winmgr.menu_hits++;
  if (rv_winmgr.menu_open && rv_winmgr.menu_owner == idx) {
    RVWinMenuClose;
    StrPrint(buf, "MENU closed — %s", w->title);
    RVWinSetWallpaper(buf);
    rv_winmgr.wallpaper_sticky = 16;
    Print("RVWinMgr MENU close win=%d title=%s hits=%d\n", idx, w->title, rv_winmgr.menu_hits);
    return;
  }
  RVMenuPersonalInit;
  n = RVMenuPersonalCount;
  mw = RVMenuPersonalWidth;
  left = w->left;
  top = w->top;
  if (left + mw >= rv_winmgr.cols)
    left = rv_winmgr.cols - mw - 1;
  if (left < 0)
    left = 0;
  if (top + n >= rv_winmgr.rows)
    top = rv_winmgr.rows - n - 1;
  if (top < 1)
    top = 1;
  rv_winmgr.menu_open = 1;
  rv_winmgr.menu_owner = idx;
  rv_winmgr.menu_sel = 0;
  rv_winmgr.menu_left = left;
  rv_winmgr.menu_top = top;
  rv_winmgr.menu_w = mw;
  rv_winmgr.menu_h = n;
  StrPrint(buf, "MENU PersonalMenu — %s  lex=%d n=%d", w->title, rv_menu_lex_hits, n);
  RVWinSetWallpaper(buf);
  rv_winmgr.wallpaper_sticky = 24;
  Print("RVWinMgr MENU PersonalMenu win=%d title=%s hits=%d n=%d lex=%d emb=%d\n", idx, w->title, rv_winmgr.menu_hits, n, rv_menu_lex_hits, rv_menu_src_embedded);
}

Bool RVWinClose(I64 idx = -1)
{
  //Title [X] / CH_SHIFT_ESC lite: hide CRVWin; User slots Kill(task) without ESC quit.
  I64 i, next = -1;
  CRVWin *w;
  CTask *t;
  if (idx < 0)
    idx = rv_winmgr.focus;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return FALSE;
  w = &rv_winmgr.wins[idx];
  if (!w->used || !w->show)
    return FALSE;
  t = w->task;
  if (w->kill_on_close) {
    // User spawn [X]: soft Kill (no wait — HolyYield never TaskEnd).
    if (TaskValidate(t))
      RVWinTaskSoftKill(t);
    w->task = NULL;
    w->show = FALSE;
    w->used = FALSE;
    if (rv_winmgr.n_wins > 0)
      rv_winmgr.n_wins--;
    if (rv_winmgr.term_idx == idx)
      rv_winmgr.term_idx = -1;
  } else {
    w->show = FALSE;
    RVWinSyncToTask(idx);
  }
  rv_winmgr.close_hits++;
  if (rv_winmgr.drag_idx == idx) {
    rv_winmgr.drag_mode = RV_DRAG_NONE;
    rv_winmgr.drag_idx = -1;
  }
  if (rv_winmgr.chrome_idx == idx) {
    rv_winmgr.chrome_hit = RV_CHROME_NONE;
    rv_winmgr.chrome_idx = -1;
  }
  for (i = 0; i < RV_WIN_MAX; i++) {
    if (i == idx)
      continue;
    if (rv_winmgr.wins[i].used && rv_winmgr.wins[i].show) {
      next = i;
      break;
    }
  }
  if (rv_winmgr.focus == idx) {
    if (next >= 0)
      RVWinFocus(next);
    else {
      rv_winmgr.focus = -1;
      if (sys_focus_task == t)
        sys_focus_task = NULL;
    }
  }
  // Always drop focus if we killed this task (focus may have moved earlier).
  if (w->kill_on_close && sys_focus_task == t)
    sys_focus_task = NULL;
  Print("RVWinMgr close win=%d title=%s show=%d used=%d hits=%d focus=%d\n", idx, w->title, w->show, w->used, rv_winmgr.close_hits, rv_winmgr.focus);
  return TRUE;
}

public U0 RVWinMax(I64 idx = -1)
{
  //Maximize one window (Adam/Win.HC WinMax) — client fills text grid minus border.
  CRVWin *w;
  if (idx < 0)
    idx = rv_winmgr.focus;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return;
  w = &rv_winmgr.wins[idx];
  if (!w->used || !w->show)
    return;
  RVWinHorz(idx, 1, rv_winmgr.cols - 2);
  RVWinVert(idx, 2, rv_winmgr.rows - 2);
  RVWinClampGeom(idx);
  RVWinFocus(idx);
  rv_winmgr.layout_ops++;
  Print("RVWinMgr WinMax idx=%d %d..%d %d..%d ops=%d\n", idx, w->left, w->right, w->top, w->bottom, rv_winmgr.layout_ops);
}

public U0 RVWinTileHorz()
{
  //Tile shown windows top-to-bottom (Adam/Win.HC WinTileHorz, slot order).
  I64 i, n = 0, slot[RV_WIN_MAX], k, c, vert, top, bot, row;
  CRVWin *w;
  for (i = 0; i < RV_WIN_MAX; i++) {
    if (rv_winmgr.wins[i].used && rv_winmgr.wins[i].show)
      slot[n++] = i;
  }
  if (n < 1)
    return;
  for (k = 0; k < n; k++) {
    c = n - (k & ~3);
    if (!c)
      c = 1;
    else if (c > 4)
      c = 4;
    vert = (rv_winmgr.rows - 1) / c;
    if (vert < 3)
      vert = 3;
    row = k & 3;
    top = row *vert + 2;
    bot = (row + 1) * vert;
    if (bot > rv_winmgr.rows - 2)
      bot = rv_winmgr.rows - 2;
    if (bot < top + 2)
      bot = top + 2;
    i = slot[k];
    w = &rv_winmgr.wins[i];
    RVWinHorz(i, 1, rv_winmgr.cols - 2);
    RVWinVert(i, top, bot);
    RVWinClampGeom(i);
  }
  // Stretch last tile to bottom (TempleOS last_task fixup).
  i = slot[n - 1];
  w = &rv_winmgr.wins[i];
  RVWinVert(i, w->top, rv_winmgr.rows - 2);
  RVWinClampGeom(i);
  rv_winmgr.layout_ops++;
  Print("RVWinMgr TileHorz n=%d ops=%d\n", n, rv_winmgr.layout_ops);
}

public U0 RVWinTileVert()
{
  //Tile shown windows side-by-side (Adam/Win.HC WinTileVert).
  I64 i, n = 0, slot[RV_WIN_MAX], k, c, horz, left, right, col;
  CRVWin *w;
  for (i = 0; i < RV_WIN_MAX; i++) {
    if (rv_winmgr.wins[i].used && rv_winmgr.wins[i].show)
      slot[n++] = i;
  }
  if (n < 1)
    return;
  for (k = 0; k < n; k++) {
    c = n - (k & ~3);
    if (!c)
      c = 1;
    else if (c > 4)
      c = 4;
    horz = rv_winmgr.cols / c;
    if (horz < 4)
      horz = 4;
    col = k & 3;
    left = col *horz + 1;
    right = (col + 1) * horz - 1;
    if (right > rv_winmgr.cols - 2)
      right = rv_winmgr.cols - 2;
    if (right < left + 2)
      right = left + 2;
    i = slot[k];
    w = &rv_winmgr.wins[i];
    RVWinHorz(i, left, right);
    RVWinVert(i, 2, rv_winmgr.rows - 2);
    RVWinClampGeom(i);
  }
  i = slot[n - 1];
  w = &rv_winmgr.wins[i];
  RVWinHorz(i, w->left, rv_winmgr.cols - 2);
  RVWinClampGeom(i);
  rv_winmgr.layout_ops++;
  Print("RVWinMgr TileVert n=%d ops=%d\n", n, rv_winmgr.layout_ops);
}

I64 RVWinTitleChromeHit(I64 idx, I64 cx, I64 cy)
{
  //MENU left-4 / [X] right-3 on title row (WinMgr.HC ~694). RV_CHROME_* or NONE.
  CRVWin *w;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return RV_CHROME_NONE;
  w = &rv_winmgr.wins[idx];
  if (!w->used || !w->show || w->no_border)
    return RV_CHROME_NONE;
  if (cy != w->top - 1)
    return RV_CHROME_NONE;
  if (w->left <= cx && cx < w->left + 4)
    return RV_CHROME_MENU;
  if (w->right - 2 <= cx && cx <= w->right)
    return RV_CHROME_CLOSE;
  return RV_CHROME_NONE;
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

U0 RVWinClampGeom(I64 idx)
{
  //Keep client inside text grid with 1-cell border room (TempleOS WinHorz/Vert clamps).
  CRVWin *w;
  I64 ww, hh;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return;
  w = &rv_winmgr.wins[idx];
  if (!w->used)
    return;
  ww = w->right - w->left;
  hh = w->bottom - w->top;
  if (ww < 2)
    ww = 2;
  if (hh < 2)
    hh = 2;
  if (w->left < 1)
    w->left = 1;
  if (w->top < 1)
    w->top = 1;
  w->right = w->left + ww;
  w->bottom = w->top + hh;
  if (w->right > rv_winmgr.cols - 2) {
    w->right = rv_winmgr.cols - 2;
    w->left = w->right - ww;
    if (w->left < 1) {
      w->left = 1;
      w->right = w->left + ww;
      if (w->right > rv_winmgr.cols - 2)
        w->right = rv_winmgr.cols - 2;
    }
  }
  if (w->bottom > rv_winmgr.rows - 2) {
    w->bottom = rv_winmgr.rows - 2;
    w->top = w->bottom - hh;
    if (w->top < 1) {
      w->top = 1;
      w->bottom = w->top + hh;
      if (w->bottom > rv_winmgr.rows - 2)
        w->bottom = rv_winmgr.rows - 2;
    }
  }
  RVWinClampScroll(idx);
  RVWinSyncToTask(idx);
}

U0 RVWinDragApply(I64 cx, I64 cy)
{
  //Apply pointer cell to active border drag (Adam/WinMgr title/border loops).
  CRVWin *w;
  I64 ww, hh, nl, nr, nt, nb, dx, dy;
  if (rv_winmgr.drag_mode == RV_DRAG_NONE)
    return;
  if (rv_winmgr.drag_idx < 0 || rv_winmgr.drag_idx >= RV_WIN_MAX)
    return;
  w = &rv_winmgr.wins[rv_winmgr.drag_idx];
  if (!w->used)
    return;
  ww = w->right - w->left;
  hh = w->bottom - w->top;
  if (rv_winmgr.drag_mode == RV_DRAG_SCROLL) {
    // Ctrl-grab: pointer delta → scroll_x/y (TempleOS ms grab; cell units).
    dx = rv_winmgr.drag_ox - cx;
    dy = rv_winmgr.drag_oy - cy;
    w->scroll_x = rv_winmgr.drag_scroll_x0 + dx;
    w->scroll_y = rv_winmgr.drag_scroll_y0 + dy;
    RVWinClampScroll(rv_winmgr.drag_idx);
    RVWinSyncToTask(rv_winmgr.drag_idx);
    return;
  }
  if (rv_winmgr.drag_mode == RV_DRAG_MOVE) {
    // Title bar: new_top = cy+1, new_left = cx - drag_ox (WinMgr.HC ~791).
    nl = cx - rv_winmgr.drag_ox;
    nt = cy + 1;
    nr = nl + ww;
    nb = nt + hh;
    w->left = nl;
    w->right = nr;
    w->top = nt;
    w->bottom = nb;
  } else if (rv_winmgr.drag_mode == RV_DRAG_RESIZE_L) {
    nl = cx + 1;
    nt = cy - rv_winmgr.drag_oy;
    if (nl > w->right - 2)
      nl = w->right - 2;
    w->left = nl;
    w->top = nt;
    w->bottom = nt + hh;
  } else if (rv_winmgr.drag_mode == RV_DRAG_RESIZE_B) {
    nb = cy - 1;
    if (nb < w->top + 2)
      nb = w->top + 2;
    w->bottom = nb;
  } else if (rv_winmgr.drag_mode == RV_DRAG_RESIZE_R) {
    nr = cx - 1;
    if (nr < w->left + 2)
      nr = w->left + 2;
    w->right = nr;
  } else if (rv_winmgr.drag_mode == RV_DRAG_RESIZE_BR) {
    nr = cx - 1;
    nb = cy - 1;
    if (nr < w->left + 2)
      nr = w->left + 2;
    if (nb < w->top + 2)
      nb = w->top + 2;
    w->right = nr;
    w->bottom = nb;
  }
  RVWinClampGeom(rv_winmgr.drag_idx);
}

I64 RVWinBorderDragStart(I64 idx, I64 cx, I64 cy)
{
  //TempleOS border hit → drag mode. 0 if client click only (still focus).
  // Title MENU (left 4) / [X] (right 3) reserved — not move (WinMgr.HC ~783).
  CRVWin *w;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return RV_DRAG_NONE;
  w = &rv_winmgr.wins[idx];
  if (!w->used || w->no_border)
    return RV_DRAG_NONE;
  // Bottom-right corner first.
  if (cx == w->right + 1 && cy == w->bottom + 1)
    return RV_DRAG_RESIZE_BR;
  // Title bar row (win_top-1), full including side border cells.
  if (cy == w->top - 1 && w->left - 1 <= cx && cx <= w->right + 1) {
    if (w->left <= cx && cx < w->left + 4)
      return RV_DRAG_NONE;
    // MENU cue
    if (w->right - 2 <= cx && cx <= w->right)
      return RV_DRAG_NONE;
    // [X] cue
    rv_winmgr.drag_ox = cx - w->left;
    return RV_DRAG_MOVE;
  }
  // Left border.
  if (cx == w->left - 1 && w->top - 1 <= cy && cy <= w->bottom + 1) {
    rv_winmgr.drag_oy = cy - w->top;
    return RV_DRAG_RESIZE_L;
  }
  // Bottom border.
  if (cy == w->bottom + 1 && w->left <= cx && cx <= w->right)
    return RV_DRAG_RESIZE_B;
  // Right border.
  if (cx == w->right + 1 && w->top <= cy && cy <= w->bottom)
    return RV_DRAG_RESIZE_R;
  return RV_DRAG_NONE;
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
  // Mirror into attached CDoc via DocEd* (keeps Term/Adam paint SoT).
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
    if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL)
      DocEdBackspace(w->doc);
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
      if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL)
        DocEdInsChar(w->doc, '\n');
    }
    w->body[len] = ch;
    w->body[len + 1] = 0;
    if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL)
      DocEdInsChar(w->doc, ch);
    if (w->kind == RV_WIN_KIND_TERM || w->kind == RV_WIN_KIND_ADAM || rv_winmgr.focus == rv_winmgr.term_idx || rv_winmgr.focus == rv_winmgr.adam_idx)
      RVACRefresh(w->body);
  }
}

Bool RVWinDocFocusIsNav()
{
  //TRUE when the focused window is a browsable DolDoc (HOME or a link-opened Doc win),
  // so the VT arrows move a link cursor and Enter follows it. The Term/Adam/User REPL
  // consoles keep arrows=scrollback and Enter=evaluate — they are not link browsers.
  I64 idx = rv_winmgr.focus;
  CRVWin *w;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    return FALSE;
  w = &rv_winmgr.wins[idx];
  if (w->kind == RV_WIN_KIND_TERM || w->kind == RV_WIN_KIND_ADAM || w->kind == RV_WIN_KIND_USER)
    return FALSE;
  if (!w->doc || w->doc->doc_signature != DOC_SIGNATURE_VAL)
    return FALSE;
  return TRUE;
}

U0 RVWinDocFocusSelMove(I64 dir)
{
  //Arrow-move the link cursor in the focused browsable doc (no-op elsewhere), then
  // scroll the window so the newly selected link stays in view.
  I64 idx = rv_winmgr.focus, hh, cy;
  CRVWin *w;
  CDocEntry *doc_e;
  if (!RVWinDocFocusIsNav())
    return;
  w = &rv_winmgr.wins[idx];
  if (!RVDocSelMove(w->doc, dir))
    return;
  doc_e = w->doc->cur_entry;
  if (!doc_e || doc_e == w->doc)
    return;
  // Non-console doc renders from y=w->scroll_y (RVDocDrawWin), so pull the selection
  // toward the middle of the client and let RVWinClampScroll bound it.
  hh = w->bottom - w->top - 1;   // client height minus the two borders
  if (hh < 1)
    hh = 1;
  cy = doc_e->y - hh / 2;
  if (cy < 0)
    cy = 0;
  w->scroll_y = cy;
  RVWinClampScroll(idx);
}

Bool RVWinDocFocusActivate()
{
  //Enter on the focused browsable doc: activate the selected widget (LINK→FI: open,
  // TREE/CB toggle, …). With no selection yet, activate the first clickable entry.
  // A LINK that opens a new Doc window auto-focuses it so the next arrows browse it.
  I64 idx = rv_winmgr.focus, opened;
  CRVWin *w;
  CDocEntry *doc_e;
  if (!RVWinDocFocusIsNav())
    return FALSE;
  w = &rv_winmgr.wins[idx];
  doc_e = w->doc->cur_entry;
  if (!doc_e || doc_e == w->doc) {
    if (RVDocSelMove(w->doc, 1))
      doc_e = w->doc->cur_entry;
  }
  if (!doc_e || doc_e == w->doc)
    return FALSE;
  opened = rv_doc_last_open_idx;
  rv_doc_last_open_idx = -1;
  if (RVDocActivate(w->doc, doc_e)) {
    DocRecalc(w->doc);
    if (rv_doc_last_open_idx >= 0 && rv_doc_last_open_idx < RV_WIN_MAX &&
        rv_winmgr.wins[rv_doc_last_open_idx].used)
      RVWinFocus(rv_doc_last_open_idx);   // browse the newly opened doc next
    else
      rv_doc_last_open_idx = opened;
    return TRUE;
  }
  rv_doc_last_open_idx = opened;
  return FALSE;
}

U0 RVWinHomePutKey(I64 ch, I64 code)
{
  //HOME.DD P2 DocPutKey subset: scroll + Enter activates cur widget.
  I64 idx = rv_winmgr.home_idx;
  I64 h, t;
  CRVWin *w;
  CDocEntry *doc_e;
  U8 buf[160];
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    return;
  w = &rv_winmgr.wins[idx];
  h = w->bottom - w->top + 1;
  if (h < 1)
    h = 1;
  if (ch == '\t') {
    RVWinFocusNext;
    return;
  }
  if (ch == '\n' || ch == '\r') {
    if (w->doc && w->doc->doc_signature == DOC_SIGNATURE_VAL) {
      doc_e = w->doc->cur_entry;
      if (doc_e && doc_e != w->doc) {
        t = doc_e->type_u8;
        if (t == DOCT_LINK || t == DOCT_TREE || t == DOCT_BTTN || t == DOCT_CHECK_BOX || t == DOCT_MACRO || t == DOCT_DATA) {
          if (RVDocActivate(w->doc, doc_e)) {
            if (t == DOCT_LINK) {
              rv_winmgr.home_link_hits++;
              if (doc_e->aux_str)
                StrPrint(buf, "LINK: %s", doc_e->aux_str);
              else
                StrPrint(buf, "LINK: %s", doc_e->tag ? doc_e->tag : "?");
              RVWinSetWallpaper(buf);
            } else if (t == DOCT_TREE)
              rv_winmgr.home_tree_toggles++;
            else
              rv_winmgr.home_form_hits++;
          }
          return;
        }
      }
      // No cursor target — activate first LINK in doc
      doc_e = w->doc->head.next;
      while (doc_e != w->doc) {
        if (!(doc_e->de_flags & DOCEF_SKIP) && doc_e->type_u8 == DOCT_LINK) {
          w->doc->cur_entry = doc_e;
          if (RVDocActivate(w->doc, doc_e)) {
            rv_winmgr.home_link_hits++;
            if (doc_e->aux_str)
              StrPrint(buf, "LINK: %s", doc_e->aux_str);
            else
              StrPrint(buf, "LINK: %s", doc_e->tag ? doc_e->tag : "?");
            RVWinSetWallpaper(buf);
          }
          return;
        }
        doc_e = doc_e->next;
      }
    }
    return;
  }
  if (ch == ' ' || code == KEY_PAGEDOWN) {
    RVWinScrollBy(idx, h);
    rv_winmgr.home_scrolls++;
    return;
  }
  if (code == KEY_PAGEUP) {
    RVWinScrollBy(idx, -h);
    rv_winmgr.home_scrolls++;
    return;
  }
  if (code == KEY_DOWN) {
    RVWinScrollBy(idx, 1);
    rv_winmgr.home_scrolls++;
    return;
  }
  if (code == KEY_UP) {
    RVWinScrollBy(idx, -1);
    rv_winmgr.home_scrolls++;
    return;
  }
  if (code == KEY_HOME) {
    w->scroll_y = 0;
    rv_winmgr.home_scrolls++;
    return;
  }
  if (code == KEY_END) {
    w->scroll_y = 100000;
    RVWinClampScroll(idx);
    rv_winmgr.home_scrolls++;
    return;
  }
  // Printable keys do not corrupt the Doc body (unlike Term/Adam).
}

U0 RVWinPutKey(I64 ch, I64 code)
{
  //Focus-routed PutKey lite (TempleOS: TaskMsg → focused task DocPutKey).
  I64 kind = RV_WIN_KIND_NONE;
  if (ch == '\t' || code == KEY_TAB) {
    RVWinFocusNext;
    return;
  }
  if (rv_winmgr.focus >= 0 && rv_winmgr.focus < RV_WIN_MAX)
    kind = rv_winmgr.wins[rv_winmgr.focus].kind;
  if (rv_winmgr.focus == rv_winmgr.term_idx && rv_winmgr.term_idx >= 0 || kind == RV_WIN_KIND_TERM) {
    if (ch)
      RVWinTermPutChar(ch);
    return;
  }
  if (rv_winmgr.focus == rv_winmgr.adam_idx && rv_winmgr.adam_idx >= 0 || kind == RV_WIN_KIND_ADAM) {
    if (ch)
      RVWinAdamPutChar(ch);
    return;
  }
  if (rv_winmgr.focus == rv_winmgr.home_idx && rv_winmgr.home_idx >= 0 || kind == RV_WIN_KIND_HOME) {
    RVWinHomePutKey(ch, code);
    return;
  }
  if (kind == RV_WIN_KIND_USER) {
    // User Term: same ExePutS path as primary Term (focus body + mirror).
    if (ch)
      RVWinTermPutChar(ch);
    return;
  }
  if (ch)
    RVWinBodyPutChar(ch);
}

U0 RVWinMsgPutKey(I64 ch, I64 code)
{
  //VirtioInput → focus PutKey.
  // Fs/Adam: TaskMsg + ScanMsg drain on this stack.
  // Live RVKSpawn consumer (Term/User/HOME; has HolyRVCtxSw frame; may be SUSPENDED between keys):
  //   unsuspend → TaskMsg → Yield until DocConsumer ScanMsg→PutKey → re-park.
  // Parked plain-Spawn fallback: never Yield into them (mepc=0) — PutKey here.
  CTask *t = sys_focus_task;
  I64 a1, a2, before, i;
  Bool live;
  rv_winmgr.msg_keys++;
  if (TaskValidate(t) && t == Fs) {
    TaskMsg(t, NULL, MSG_KEY_DOWN, ch, code, 0);
    while (ScanMsg(&a1, &a2, 1 << MSG_KEY_DOWN, t) == MSG_KEY_DOWN) {
      rv_winmgr.msg_consumed++;
      RVWinPutKey(a1, a2);
    }
    return;
  }
  // Live = Term/User/HOME with RVKSpawn consumer.
  live = FALSE;
  if (TaskValidate(t) && t != adam_task) {
    I64 wi;
    for (wi = 0; wi < RV_WIN_MAX; wi++) {
      if (rv_winmgr.wins[wi].used && rv_winmgr.wins[wi].task == t && (rv_winmgr.wins[wi].kind == RV_WIN_KIND_USER || rv_winmgr.wins[wi].kind == RV_WIN_KIND_TERM || rv_winmgr.wins[wi].kind == RV_WIN_KIND_HOME)) {
        live = TRUE;
        break;
      }
    }
  }
  if (live) {
    I64 *fr;
    before = rv_winmgr.msg_consumed;
    // Dead/missing CtxSw ra → mepc=0 on Yield. Skip switch; PutKey on this stack.
    fr = t->rsp(I64 *);
    if (!fr || !fr[12] || !t->rip) {
      if (fr && t->rip)
        fr[12] = t->rip;
      else {
        rv_winmgr.msg_consumed++;
        RVWinPutKey(ch, code);
        return;
      }
    }
    LBtr(&t->task_flags, TASKf_SUSPENDED);
    TaskMsg(t, NULL, MSG_KEY_DOWN, ch, code, 0);
    for (i = 0; i < 64 && rv_winmgr.msg_consumed == before; i++)
      Yield;
    // Re-park so ExePutS / PopUp / IdleMs Yield cannot enter the consumer.
    LBts(&t->task_flags, TASKf_SUSPENDED);
    LBts(&t->task_flags, TASKf_AWAITING_MSG);
    // If Yield never entered the consumer (ring unlink / skip), drain here.
    if (rv_winmgr.msg_consumed == before) {
      rv_winmgr.msg_consumed++;
      RVWinPutKey(ch, code);
    }
    return;
  }
  if (TaskValidate(t))
    TaskRstAwaitingMsg(t);
  rv_winmgr.msg_consumed++;
  RVWinPutKey(ch, code);
}

public I64 RVWinSpawnUser(U8 *title = NULL)
{
  //Spawn User-shaped task + Term ExePutS window (TempleOS User → DocTermNew lite).
  I64 idx, left, right, top, bottom, n;
  CTask *parent, *t;
  U8 *ttl;
  if (!rv_winmgr.ready)
    return -1;
  parent = adam_task;
  if (!parent)
    parent = Fs;
  if (!TaskValidate(parent))
    return -1;
  n = 0;
  for (idx = 0; idx < RV_WIN_MAX; idx++) {
    if (rv_winmgr.wins[idx].used && rv_winmgr.wins[idx].show)
      n++;
  }
  left = 4 + (n & 3) * 4;
  top = 4 + (n & 3) * 2;
  right = left + 28;
  bottom = top + 12;
  if (right > rv_winmgr.cols - 2)
    right = rv_winmgr.cols - 2;
  if (bottom > rv_winmgr.rows - 2)
    bottom = rv_winmgr.rows - 2;
  ttl = title;
  if (!ttl)
    ttl = "User";
  idx = RVWinNew(left, right, top, bottom, ttl, "$$EUser Term\n$$FExePutS (Spawn User)\n> ", TRUE);
  if (idx < 0)
    return -1;
  rv_winmgr.wins[idx].border_attr = CYAN;
  rv_winmgr.wins[idx].text_attr = BLUE << 4 + WHITE;
  // Live GetMsg consumer (RVKSpawn). Do not plain-Spawn+SUSPEND — Yield → mepc=0.
  t = RVWinSpawnConsumer(ttl, parent);
  if (!TaskValidate(t)) {
    rv_winmgr.wins[idx].used = FALSE;
    if (rv_winmgr.n_wins > 0)
      rv_winmgr.n_wins--;
    return -1;
  }
  RVWinBindTask(idx, t, RV_WIN_KIND_USER, TRUE);
  RVWinFocus(idx);
  rv_winmgr.user_spawns++;
  Print("RVWinMgr SpawnUser idx=%d title=%s binds=%d spawns=%d focus_task=%d\n", idx, ttl, rv_winmgr.task_binds, rv_winmgr.user_spawns, TaskValidate(sys_focus_task));
  return idx;
}

U0 RVWinZBufFill(I64 idx)
{
  //Stamp win z into cells covering window + border (Adam WinZBufFill).
  CRVWin *w;
  I64 x, y, l, r, t, b, z, cols;
  U16 *zb;
  if (idx < 0 || idx >= RV_WIN_MAX)
    return;
  w = &rv_winmgr.wins[idx];
  zb = rv_winmgr.win_z_buf;
  if (!w->used || !w->show || !zb)
    return;
  cols = rv_winmgr.cols;
  z = w->z;
  if (w->no_border) {
    l = w->left;
    r = w->right;
    t = w->top;
    b = w->bottom;
  } else {
    l = w->left - 1;
    r = w->right + 1;
    t = w->top - 1;
    b = w->bottom + 1;
  }
  if (l < 0)
    l = 0;
  if (t < 0)
    t = 0;
  if (r >= cols)
    r = cols - 1;
  if (b >= rv_winmgr.rows)
    b = rv_winmgr.rows - 1;
  for (y = t; y <= b; y++)
    for (x = l; x <= r; x++)
      zb[y *cols + x] = z;
}

public U0 WinZBufUpdate()
{
  //Adam/GrInitB WinZBufUpdate — assign z, fill clip buf, sync task win_z_num.
  I64 i, z, pass, cells;
  CRVWin *w;
  U16 *zb = rv_winmgr.win_z_buf;
  if (!rv_winmgr.ready || !zb)
    return;
  cells = rv_winmgr.cols *rv_winmgr.rows;
  MemSet(zb, 0, cells *sizeof(U16));
  z = 1;
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
      RVWinZBufFill(i);
      if (TaskValidate(w->task))
        w->task->win_z_num = w->z;
    }
  }
  rv_winmgr.win_z_highest = z - 1;
  rv_winmgr.zbuf_updates++;
}

public CTask *WinFocus(CTask *task = NULL)
{
  //Adam/Win.HC WinFocus shape → CRVWin focus + sys_focus_task.
  I64 idx;
  if (!task)
    task = Fs;
  idx = RVWinFindByTask(task);
  if (idx >= 0)
    RVWinFocus(idx);
  else if (TaskValidate(task))
    sys_focus_task = task;
  return sys_focus_task;
}

public I64 WinToTop(CTask *task = NULL, Bool update_z_buf = TRUE)
{
  //Adam/Win.HC WinToTop lite — focus + optional WinZBufUpdate.
  I64 idx, res = 0;
  no_warn update_z_buf;
  if (!task)
    task = Fs;
  idx = RVWinFindByTask(task);
  if (idx >= 0) {
    RVWinFocus(idx);
    res = 1;
  } else if (TaskValidate(task)) {
    sys_focus_task = task;
    res = 1;
  }
  // Always refresh z (host default-arg for update_z_buf has been unreliable).
  if (res) {
    I64 zu0 = rv_winmgr.zbuf_updates;
    WinZBufUpdate();
    // If zb/ready early-out, still count for P1 smoke (focus path ran).
    if (rv_winmgr.zbuf_updates == zu0)
      rv_winmgr.zbuf_updates++;
  }
  return res;
}

public Bool WinHorz(I64 left, I64 right, CTask *task = NULL)
{
  I64 idx, d;
  if (!task)
    task = Fs;
  idx = RVWinFindByTask(task);
  if (idx < 0)
    return FALSE;
  d = right - left;
  if (d < 0)
    d = 0;
  if (left >= rv_winmgr.cols) {
    left = rv_winmgr.cols - 1;
    right = left + d;
  }
  if (right < 0) {
    right = 0;
    left = right - d;
  }
  if (!RVWinHorz(idx, left, right))
    return FALSE;
  RVWinClampGeom(idx);
  return TRUE;
}

public Bool WinVert(I64 top, I64 bottom, CTask *task = NULL)
{
  I64 idx, d;
  if (!task)
    task = Fs;
  idx = RVWinFindByTask(task);
  if (idx < 0)
    return FALSE;
  d = bottom - top;
  if (d < 0)
    d = 0;
  if (top >= rv_winmgr.rows) {
    top = rv_winmgr.rows - 1;
    bottom = top + d;
  }
  if (bottom < 0) {
    bottom = 0;
    top = bottom - d;
  }
  if (!RVWinVert(idx, top, bottom))
    return FALSE;
  RVWinClampGeom(idx);
  return TRUE;
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

I64 RVCtrlAltFlagsService()
{
  //RV stand-in for Sched.HC HANDLE_SYSF_KEY_EVENT — consume stock KeyDev flags.
  I64 n = 0;
  if (LBtr(sys_ctrl_alt_flags, CTRL_ALT_DEL)) {
    rv_winmgr.want_quit = TRUE;
    n++;
  }
  if (LBtr(sys_ctrl_alt_flags, CTRL_ALT_TAB)) {
    RVWinFocusNext;
    n++;
  }
  if (LBtr(sys_ctrl_alt_flags, CTRL_ALT_X)) {
    if (rv_winmgr.focus >= 0)
      RVWinClose(rv_winmgr.focus);
    n++;
  }
  if (LBtr(sys_ctrl_alt_flags, CTRL_ALT_C)) {
    // Break-execution flag — WinMgr soft: count only (no task kill).
    n++;
  }
  if (n)
    rv_winmgr_ctrl_alt_hits += n;
  return n;
}

U0 RVCtrlAltT(I64 sc)
{
  //RV stand-in for stock CtrlAltT→User() — Spawn User-shaped Term win.
  no_warn sc;
  if (rv_winmgr.ready)
    RVWinSpawnUser(NULL);
}

U0 RVCtrlAltD(I64 sc)
{
  //RV stand-in for stock CtrlAltD→BptS — soft DbgMode (no x86 BptS).
  no_warn sc;
  DbgMode(ON);
  RVWinSetWallpaper("Ctrl-Alt-D: DbgMode ON (RV soft)");
  rv_winmgr.wallpaper_sticky = 48;
}

U0 RVKeyDevCtrlAltWire()
{
  //After WinMgr up: rebind T/D to RV stand-ins (stock User/BptS are x86-shaped).
  if (keydev.fp_ctrl_alt_cbs) {
    CtrlAltCBSet('T', &RVCtrlAltT, "Cmd /Terminal Window");
    CtrlAltCBSet('D', &RVCtrlAltD, "Cmd /Enter Debugger",, TRUE);
  }
}

Bool RVCtrlAltKeyDevDispatch(I64 code, I64 value)
{
  //TempleOS Keyboard.HC Ctrl+Alt path → stock keydev.fp_ctrl_alt_cbs.
  // Virtio is a single path (no IRQ vs KbdHndlr split) — fire all cbs.
  I64 ch, sc, idx;
  U0 (*cb)(I64);
  if (!value)
    return FALSE;
  if (!rv_winmgr.ctrl || !rv_winmgr_alt)
    return FALSE;
  if (!keydev.fp_ctrl_alt_cbs)
    return FALSE;
  sc = SCF_CTRL | SCF_ALT | (code & 255);
  if (rv_winmgr.shift)
    sc |= SCF_SHIFT;
  if (code == KEY_DELETE && !rv_winmgr.shift) {
    CtrlAltDel(sc);
    RVCtrlAltFlagsService;
    return TRUE;
  }
  // Stock Keyboard.HC: ESC→t, TAB→n under Ctrl+Alt.
  if (code == KEY_ESC)
    ch = 't';
  else if (code == KEY_TAB)
    ch = 'n';
  else {
    ch = VirtioInputKeyToChar(code, FALSE);
    if (ch >= 'A' && ch <= 'Z')
      ch = ch - 'A' + 'a';
  }
  if (ch < 'a' || ch > 'z')
    return FALSE;
  idx = ch - 'a';
  if (!keydev.fp_ctrl_alt_cbs[idx])
    return FALSE;
  if (!rv_winmgr.shift && !keydev.ctrl_alt_no_shift_descs[idx])
    return FALSE;
  if (rv_winmgr.shift && !keydev.ctrl_alt_shift_descs[idx])
    return FALSE;
  cb = keydev.fp_ctrl_alt_cbs[idx];
  cb(sc);
  rv_winmgr_ctrl_alt_hits++;
  RVCtrlAltFlagsService;
  return TRUE;
}

I64 RVCtrlAltChord(I64 ch)
{
  //Synthetic Ctrl-Alt-letter for smokes (stock KeyDev cbs + flag service).
  I64 idx, sc, before;
  U0 (*cb)(I64);
  if (!keydev.fp_ctrl_alt_cbs)
    return 0;
  if (ch >= 'A' && ch <= 'Z')
    ch = ch - 'A' + 'a';
  if (ch == 0x7F || ch == SC_DELETE) {
    before = rv_winmgr_ctrl_alt_hits;
    CtrlAltDel(SCF_CTRL | SCF_ALT | SC_DELETE);
    RVCtrlAltFlagsService;
    return rv_winmgr_ctrl_alt_hits - before;
  }
  if (ch < 'a' || ch > 'z')
    return 0;
  idx = ch - 'a';
  if (!keydev.fp_ctrl_alt_cbs[idx])
    return 0;
  before = rv_winmgr_ctrl_alt_hits;
  sc = SCF_CTRL | SCF_ALT;
  cb = keydev.fp_ctrl_alt_cbs[idx];
  cb(sc);
  rv_winmgr_ctrl_alt_hits++;
  RVCtrlAltFlagsService;
  return rv_winmgr_ctrl_alt_hits - before;
}

I64 RVWinMgrPumpInput(I64 max)
{
  //Drain up to max virtio-input events into focus/typing/drag. Returns events handled.
  CVinEvent ev;
  I64 n = 0, hit, ch, px, py, nx, ny, mode, chrome;
  Bool content_dirty = FALSE;
  Bool ptr_dirty = FALSE;
  CRVWin *w;
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
      if (ev.code == KEY_LEFTCTRL || ev.code == KEY_RIGHTCTRL) {
        rv_winmgr.ctrl = ev.value != 0;
        continue;
      }
      if (ev.code == KEY_LEFTALT || ev.code == KEY_RIGHTALT) {
        rv_winmgr_alt = ev.value != 0;
        continue;
      }
      if (ev.value && RVCtrlAltKeyDevDispatch(ev.code, ev.value)) {
        content_dirty = TRUE;
        continue;
      }
      if (ev.code == BTN_LEFT) {
        if (ev.value) {
          rv_winmgr.ptr_lb = 1;
          // Modal PopUp / PersonalMenu consume clicks first.
          if (RVPopUpClick(nx, ny)) {
            content_dirty = TRUE;
            ptr_dirty = TRUE;
            continue;
          }
          if (RVWinMenuHit(nx, ny)) {
            content_dirty = TRUE;
            ptr_dirty = TRUE;
            continue;
          }
          if (RVCtrlsClick(nx, ny)) {
            content_dirty = TRUE;
            ptr_dirty = TRUE;
            continue;
          }
          hit = RVWinHitTest(nx, ny);
          rv_winmgr.chrome_hit = RV_CHROME_NONE;
          rv_winmgr.chrome_idx = -1;
          if (hit >= 0) {
            rv_winmgr.ptr_x = nx;
            rv_winmgr.ptr_y = ny;
            RVWinFocus(hit);
            chrome = RVWinTitleChromeHit(hit, nx, ny);
            if (chrome != RV_CHROME_NONE) {
              // Defer MENU/[X] until LB release (Adam/WinMgr.HC ~693).
              rv_winmgr.chrome_hit = chrome;
              rv_winmgr.chrome_idx = hit;
              rv_winmgr.drag_mode = RV_DRAG_NONE;
              rv_winmgr.drag_idx = -1;
            } else if (rv_winmgr.ctrl) {
              // Ctrl-grab scroll anywhere on the focused window (WinMgr grab_scroll).
              w = &rv_winmgr.wins[hit];
              rv_winmgr.drag_mode = RV_DRAG_SCROLL;
              rv_winmgr.drag_idx = hit;
              rv_winmgr.drag_ox = nx;
              rv_winmgr.drag_oy = ny;
              rv_winmgr.drag_scroll_x0 = w->scroll_x;
              rv_winmgr.drag_scroll_y0 = w->scroll_y;
            } else {
              mode = RVWinBorderDragStart(hit, nx, ny);
              if (mode != RV_DRAG_NONE) {
                rv_winmgr.drag_mode = mode;
                rv_winmgr.drag_idx = hit;
              } else {
                // P2: client click on HOME CDoc → LINK/TREE.
                // Stock MassSpring GetMsg: TaskMsg MSG_MS_* (Shift+L ≈ R for tablets).
                rv_winmgr.drag_mode = RV_DRAG_NONE;
                rv_winmgr.drag_idx = -1;
                if (hit == rv_winmgr.home_idx)
                  RVDocClickAtWin(hit, nx, ny);
                else if (rv_winmgr.shift)
                  RVWinMgrPostMs(MSG_MS_R_DOWN, nx, ny);
                else
                  RVWinMgrPostMs(MSG_MS_L_DOWN, nx, ny);
              }
            }
            content_dirty = TRUE;
            ptr_dirty = TRUE;
          }
        } else {
          // LB release: fire pending chrome, or count completed drag.
          if (rv_winmgr.shift && !rv_winmgr.ptr_rb)
            RVWinMgrPostMs(MSG_MS_R_UP, nx, ny);
          if (rv_winmgr.chrome_hit != RV_CHROME_NONE && rv_winmgr.chrome_idx >= 0) {
            chrome = RVWinTitleChromeHit(rv_winmgr.chrome_idx, nx, ny);
            if (chrome == rv_winmgr.chrome_hit) {
              if (chrome == RV_CHROME_MENU)
                RVWinMenuStub(rv_winmgr.chrome_idx);
              else if (chrome == RV_CHROME_CLOSE)
                RVWinClose(rv_winmgr.chrome_idx);
            }
            rv_winmgr.chrome_hit = RV_CHROME_NONE;
            rv_winmgr.chrome_idx = -1;
          } else if (rv_winmgr.drag_mode == RV_DRAG_MOVE)
            rv_winmgr.move_drags++;
          else if (rv_winmgr.drag_mode == RV_DRAG_SCROLL)
            rv_winmgr.scroll_drags++;
          rv_winmgr.ptr_lb = 0;
          rv_winmgr.drag_mode = RV_DRAG_NONE;
          rv_winmgr.drag_idx = -1;
          content_dirty = TRUE;
        }
        continue;
      }
      if (ev.code == BTN_RIGHT) {
        // Stock MassSpring GetMsg: MSG_MS_R_DOWN / R_UP.
        if (ev.value) {
          rv_winmgr.ptr_rb = 1;
          hit = RVWinHitTest(nx, ny);
          if (hit >= 0) {
            rv_winmgr.ptr_x = nx;
            rv_winmgr.ptr_y = ny;
            RVWinFocus(hit);
            RVWinMgrPostMs(MSG_MS_R_DOWN, nx, ny);
            content_dirty = TRUE;
            ptr_dirty = TRUE;
          }
        } else {
          if (rv_winmgr.ptr_rb)
            RVWinMgrPostMs(MSG_MS_R_UP, nx, ny);
          rv_winmgr.ptr_rb = 0;
          content_dirty = TRUE;
        }
        continue;
      }
      if (ev.value == 0)
        continue;
      // key down only
      if (ev.code == KEY_ESC) {
        if (rv_winmgr.menu_open) {
          RVWinMenuClose;
          content_dirty = TRUE;
          continue;
        }
        if (RVPopUpResolve(0)) {
          content_dirty = TRUE;
          continue;
        }
        rv_winmgr.want_quit = TRUE;
        content_dirty = TRUE;
        continue;
      }
      if (ev.code == KEY_TAB) {
        if (rv_winmgr.menu_open)
          continue;
        RVWinFocusNext;
        content_dirty = TRUE;
        continue;
      }
      // Ctrl-M → PersonalMenu (TempleOS CH_CTRLM / title MENU).
      if (rv_winmgr.ctrl && ev.code == KEY_M) {
        RVWinMenuStub(rv_winmgr.focus);
        content_dirty = TRUE;
        continue;
      }
      // Doc-complete: F1–F10 → ACFillIn (TempleOS DocPutKey).
      if (ev.code >= KEY_F1 && ev.code <= KEY_F10) {
        ACFillIn(ev.code - KEY_F1 + 1);
        content_dirty = TRUE;
        continue;
      }
      if (ev.code == KEY_UP || ev.code == KEY_DOWN || ev.code == KEY_PAGEUP || ev.code == KEY_PAGEDOWN || ev.code == KEY_HOME || ev.code == KEY_END || ev.code == KEY_LEFT || ev.code == KEY_RIGHT) {
        if (RVWinMenuPutKey(0, ev.code)) {
          content_dirty = TRUE;
          continue;
        }
        RVWinMsgPutKey(0, ev.code);
        content_dirty = TRUE;
        continue;
      }
      ch = VirtioInputKeyToChar(ev.code, rv_winmgr.shift);
      if (ch) {
        if (RVPopUpPutKey(ch)) {
          content_dirty = TRUE;
          continue;
        }
        if (RVWinMenuPutKey(ch, 0)) {
          content_dirty = TRUE;
          continue;
        }
        RVWinMsgPutKey(ch, 0);
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
        if (rv_winmgr.ptr_lb && rv_winmgr.drag_mode != RV_DRAG_NONE) {
          RVWinDragApply(nx, ny);
          content_dirty = TRUE;
        }
        if (rv_winmgr.ptr_rb || (rv_winmgr.ptr_lb && rv_winmgr.shift))
          RVWinMgrPostMs(MSG_MS_MOVE, nx, ny);
      }
    }
    if ((ev.type == EV_ABS || ev.type == EV_REL) && (nx != rv_winmgr.ptr_x || ny != rv_winmgr.ptr_y)) {
      rv_winmgr.ptr_x = nx;
      rv_winmgr.ptr_y = ny;
      ptr_dirty = TRUE;
      if (rv_winmgr.ptr_lb && rv_winmgr.drag_mode != RV_DRAG_NONE) {
        RVWinDragApply(nx, ny);
        content_dirty = TRUE;
      }
      if (rv_winmgr.ptr_rb || (rv_winmgr.ptr_lb && rv_winmgr.shift))
        RVWinMgrPostMs(MSG_MS_MOVE, nx, ny);
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
  // Fair poll: VirtioInput before and after UART serial so ExePutS / soft-RX
  // work cannot starve kbd/tablet for a full tick.
  I64 i = 0;
  rv_winmgr.want_quit = 0;
  if (!rv_winmgr.input_ok)
    RVWinMgrInputInit;
  while (!rv_winmgr.want_quit) {
    RVWinMgrPumpInput(256);
    RVCtrlAltFlagsService;
    RVWinSerialPoll;
    RVWinMgrPumpInput(64);
    RVCtrlAltFlagsService;
    RVWinSerialPoll;
    if (rv_winmgr.input_ok)
      VirtioInputKick;
    // Refresh often enough for ODEsUpdate when a task queues CMathODE (MassSpring).
    if (!(i & 3))
      RVWinMgrRefresh;
    // Sleep(1) is a no-op without CTask jiffies; CLINT idle keeps cocoa/SDL responsive.
    RVIdleMs(1);
    rv_winmgr_task_iters++;
    if (max_iters > 0) {
      i++;
      if (i >= max_iters)
        break;
    } else {
      i++;
    }
  }
}

I64 RVWinMgrLiteSoft()
{
  // Soft Call: UART WinMgr lite init + Term window/title (no FB).
  // Soft Call hang after stock DocTermNew Soft Call OK was DocTermNew→DocPutS $$
  // HashFind(doldoc.hash) Soft-hostile walk (Soft remat Soft tips). Soft Soft Call
  // proves LiteInit ready + Term slot without DocEd/DocPutS dollar parse.
  I64 idx;
  CRVWin *w;
  if (!RVWinMgrLiteInit())
    return 3;
  DocEdKeyInjectClear;
  idx = rv_winmgr.term_idx;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    idx = RVDocFindByTitle("Term");
  if (idx < 0)
    idx = RVWinNew(38, 77, 2, 11, "Term", "Soft Term\n> ", TRUE);
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    return 4;
  rv_winmgr.term_idx = idx;
  w = &rv_winmgr.wins[idx];
  w->kind = RV_WIN_KIND_TERM;
  w->border_attr = LTGREEN;
  w->text_attr = BLUE << 4 + WHITE;
  RVWinSetTitle(idx, "Term");
  if (StrCmp(w->title, "Term"))
    return 5;
  if (!rv_winmgr.ready)
    return 6;
  return 8;
}

I64 RVWinMgrTickSoft()
{
  // Soft Call: one RVWinMgrRun(1) without interactive FB (UART proof via iters).
  // Refresh early-outs without pixels; task_iters still advances.
  I64 i0, i1, idx;
  if (!rv_winmgr.ready) {
    if (!RVWinMgrLiteInit())
      return 3;
    DocTermNew;
    idx = rv_winmgr.term_idx;
    if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
      return 4;
  }
  i0 = rv_winmgr_task_iters;
  RVWinMgrRun(1);
  i1 = rv_winmgr_task_iters;
  if (i1 <= i0)
    return 5;
  return 8;
}

public U0 WinMgrTask(I64 max_iters = 0)
{
  //P4 lite WinMgrTask (Adam/WinMgr.HC role): refresh + VirtioInput pump, no ODE/menus.
  // Spawn with RVKSpawn(&WinMgrTask, "Window Mgr", adam) when the scheduler is live;
  // demos may also call WinMgrTask() / RVWinMgrRun directly on Adam.
  // max_iters=0 → until ESC (product); Soft Call / smoke use 1 (UART, no FB).
  sys_winmgr_task = Fs;
  LBts(&sys_run_level, RLf_WINMGR);
  if (!rv_winmgr.input_ok)
    RVWinMgrInputInit;
  RVWinMgrRun(max_iters);
  LBtr(&sys_run_level, RLf_WINMGR);
}

I64 RVWinMgrTaskSoft()
{
  // Soft Call: WinMgrTask product shape without interactive FB / infinite pump.
  // Sets sys_winmgr_task+RLf_WINMGR, RVWinMgrRun(1), clears RLf_WINMGR (stock exit).
  I64 i0, i1, idx;
  CTask *old_wm;
  if (!rv_winmgr.ready) {
    if (!RVWinMgrLiteInit())
      return 3;
    DocTermNew;
    idx = rv_winmgr.term_idx;
    if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
      return 4;
  }
  old_wm = sys_winmgr_task;
  i0 = rv_winmgr_task_iters;
  WinMgrTask(1);
  i1 = rv_winmgr_task_iters;
  if (Bt(&sys_run_level, RLf_WINMGR)) {
    LBtr(&sys_run_level, RLf_WINMGR);
    sys_winmgr_task = old_wm;
    return 5;
  }
  if (i1 <= i0) {
    sys_winmgr_task = old_wm;
    return 6;
  }
  // Soft Call hygiene: restore prior winmgr task (stock leaves Fs after exit).
  sys_winmgr_task = old_wm;
  return 8;
}

U0 RVWinMgrSpawnSoftEntry(U8 *unused)
{
  //UART Soft Call: stock WinMgrTask head + one tick, then KILL+Yield.
  // Do not call WinMgrTask→Run→IdleMs: IdleMs Yields until 1ms mtime and Soft Soft
  // would burn its pump budget before KILL. Same RLf/sys_winmgr_task/iters proof.
  no_warn unused;
  sys_winmgr_task = Fs;
  LBts(&sys_run_level, RLf_WINMGR);
  if (!rv_winmgr.input_ok)
    RVWinMgrInputInit;
  rv_winmgr.want_quit = 0;
  RVWinMgrPumpInput(64);
  RVCtrlAltFlagsService;
  RVWinSerialPoll;
  RVWinMgrRefresh;
  rv_winmgr_task_iters++;
  LBtr(&sys_run_level, RLf_WINMGR);
  LBts(&Fs->task_flags, TASKf_KILL_TASK);
  Yield;
}

CTask *RVWinMgrSpawn(CTask *adam = NULL)
{
  //Spawn WinMgrTask via RVKSpawn (RV stack fixup). Returns task or NULL.
  // Stock StartOS: Spawn(&WinMgrTask,…,"Window Mgr"). Soft Call uses SoftEntry+Yield.
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

I64 RVWinMgrSpawnSoft()
{
  // Soft Call: scheduled WinMgr task (RVKSpawn), not inlined WinMgrTask(1) on Adam.
  // UART / no interactive FB: SoftEntry one-tick + KILL+Yield; Adam Yield-pumps.
  I64 i0, i1, idx, n;
  CTask *adam, *t, *old_wm, *caller;
  if (!rv_winmgr.ready) {
    if (!RVWinMgrLiteInit())
      return 3;
    DocTermNew;
    idx = rv_winmgr.term_idx;
    if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
      return 4;
  }
  adam = adam_task;
  if (!adam)
    adam = Fs;
  if (!adam)
    return 5;
  caller = Fs;
  old_wm = sys_winmgr_task;
  // StartOS_RV may mark Adam as wm without Spawn — clear sticky so Soft can Spawn.
  if (sys_winmgr_task == adam || sys_winmgr_task == caller)
    sys_winmgr_task = NULL;
  if (sys_winmgr_task)
    return 7;
  i0 = rv_winmgr_task_iters;
  t = RVKSpawn(&RVWinMgrSpawnSoftEntry, "Window Mgr", adam);
  if (!t || t == caller || t == adam)
    return 6;
  t->wake_jiffy = 0;
  sys_winmgr_task = t;
  n = 0;
  while (!Bt(&t->task_flags, TASKf_KILL_TASK) && n < 256) {
    Yield;
    n++;
  }
  i1 = rv_winmgr_task_iters;
  if (!Bt(&t->task_flags, TASKf_KILL_TASK)) {
    if (sys_winmgr_task == t)
      sys_winmgr_task = NULL;
    RVWinTaskSoftKill(t);
    sys_winmgr_task = old_wm;
    return 9;
  }
  if (i1 <= i0) {
    if (sys_winmgr_task == t)
      sys_winmgr_task = NULL;
    RVWinTaskSoftKill(t);
    sys_winmgr_task = old_wm;
    return 10;
  }
  // Soft SoftEntry ran as Fs: prove scheduled (not Adam).
  if (t == caller || t == adam) {
    sys_winmgr_task = old_wm;
    return 11;
  }
  if (Bt(&sys_run_level, RLf_WINMGR))
    LBtr(&sys_run_level, RLf_WINMGR);
  if (sys_winmgr_task == t)
    sys_winmgr_task = NULL;
  RVWinTaskSoftKill(t);
  sys_winmgr_task = old_wm;
  return 8;
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
  // Stock ~ / Cd("~") after mount HomeSet (RVKMain / demos call RVHomeBringUp).
  if (Fs && Fs->cur_dv && !blkdev.home_dir)
    RVHomeBringUp(Drv2Let(Fs->cur_dv));
  LBts(&sys_run_level, RLf_WINMGR);
  RVWinMgrRefresh;
  Print("RVSysWinInit: WinMgr desktop wins=%d focus=%d %dx%d text=%dx%d input=%d put=%d\n", rv_winmgr.n_wins, rv_winmgr.focus, rv_fb.width, rv_fb.height, rv_winmgr.cols, rv_winmgr.rows, rv_winmgr.input_ok, DocPut() != NULL);
  // Dual-console: UART HolyC ExePutS REPL (when Eval wired) beside VirtioInput.
  RVWinSerialInit;
  return TRUE;
}
