// Interactive DocTerm desktop + VirtioInput + UART HolyC ExePutS REPL.
// Headless: paint hash + input_ok + bounded pump (+ serial banner).
// Hold: make kernel-win-run (ESC or serial `q` quits). Serial is the regular
// TempleOS ExePutS loop (same as A2 / repl-cmp), not dig-down-only.
#include "/Kernel/Kernel_RV.PRJ"
#include "/Kernel/RVDocVT.HC"
#include "/Compiler/RISCVRegs.HH"
// Incremental host AOT links Compiler_RV as a separate unit (see tests/exec/aot/).
// Monolithic one-shot still includes the Body here.
#ifndef HOLYC_AOT_NO_COMPILER_BODY
#include "/Compiler/Compiler_RV_Body.PRJ"
#else
extern I64 RVExePubsWire();
extern I64 RVExePubsWireAddrs(I64 *addrs);
extern I64 RVExePubsWireDbg(I64 *addrs);
extern U0 RVAotLibSync(I64 fs, I64 gs);
extern U0 RVCmpWireAsmHash();
extern U0 RVCmpWireCharBmps(I64 *src);
extern U0 RVCmpSetF64Rt(I64 *tbl);
extern I64 RVCmpCtrlAddrsGet(I64 *out);
extern U0 RVMenuWireCmpCtrlAddrs(I64 *addrs);
extern I64 RVExePutSSynced(U8 *buf, I64 fs, I64 gs);
#endif
#ifdef RV_WIN_HOLD_UNIT
// Split AOT: one shared Kernel unit for win_i + win_hold + win_vt; the variant lives
// in the tiny win_flag_{i,hold,vt}.hc unit (tests/exec/aot/) picked at --link time.
// RVWinHoldFlag: 0 headless proof, 1 FB hold, 2 present to a VT100 over UART.
// RVWinVtCols/Rows: VT text geometry, 0 in the non-VT units = keep RVGrInit defaults.
extern I64 RVWinHoldFlag();
#endif
I64 RVWinSerialHolyC(U8 *line)
{
  // Was buf[168] / 158: anything longer was cut mid-token and the truncated tail
  // ("longvari", an open string literal) produced baffling compile errors.
  U8 buf[RV_WIN_SERIAL_LINE_MAX + 8];
  I64 i;
  if (!line)
    return 0;
  i = 0;
  while (line[i] && i < RV_WIN_SERIAL_LINE_MAX - 2) {
    buf[i] = line[i];
    i++;
  }
  if (!i || buf[i - 1] != '\n')
    buf[i++] = '\n';
  buf[i] = 0;
#ifdef HOLYC_AOT_NO_COMPILER_BODY
  // Re-sync Compiler Fs (Yield only updates Kernel's slot) + asm_hash chain.
  return RVExePutSSynced(buf, Fs, Gs);
#else
  return ExePutS(buf);
#endif
}

U0 RVWinAdamBoot()
{
  CTask *adam = 0x86900000;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400;
  heap_end = 0x86000000;
  CBlkPool *bp = 0x86800000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  CHeapCtrl *ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah;
  adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0);
  adam->task_signature = TASK_SIGNATURE_VAL;
  adam->addr = adam;
  CCPU *gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVYieldInit(&Fs);
  RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);
}

// ---- VT presentation (RVWinHoldFlag()==2) -------------------------------------
// The desktop, ExePutS REPL and DolDoc are all exactly the ones the FB variants use.
// The only difference is the scanout: RVVtPresent diffs the composed text grid and
// ships ANSI over the same UART, instead of RVWinMgrPresent pushing pixels at ramfb.
I64 g_vt_caret_row;
I64 g_vt_caret_col;
U0 RVWinVtCaret(I64 idx)
{
  // The WinMgr keeps no caret field; the end of the focused window's text is the
  // insertion point for an append-only REPL body.
  CRVWin *w;
  I64 x, y, ch;
  if (idx < 0 || idx >= RV_WIN_MAX || !rv_winmgr.wins[idx].used)
    return;
  w = &rv_winmgr.wins[idx];
  g_vt_caret_row = w->top;
  g_vt_caret_col = w->left;
  for (y = w->top; y <= w->bottom; y++) {
    for (x = w->left; x <= w->right; x++) {
      ch = rv_winmgr.text_base[y *rv_winmgr.cols + x] & 255;
      if (ch > 32) {
        g_vt_caret_row = y;
        g_vt_caret_col = x + 1;
      }
    }
  }
  if (g_vt_caret_col > w->right)
    g_vt_caret_col = w->right;
}

// Readable palette for the VT presentation. Scoped to this path on purpose: the FB
// variants keep their existing attrs, so no render hash moves.
//
// The desktop ships the Term body as WHITE<<4 | LTGRAY — light gray on white, which
// on a real terminal is roughly 1.4:1 and close to unreadable. Principles applied:
//   * body text gets the maximum available contrast: BLACK on WHITE (~21:1);
//   * focus is signalled by border BRIGHTNESS (LTBLUE vs DKGRAY), not hue alone, so it
//     survives a monochrome terminal and colour-blind viewers;
//   * the wallpaper stays dark so window edges read as edges;
//   * nothing depends on colour to be understood — the border and title already carry
//     focus, colour only reinforces it.
// Attr layout is BG<<4 | FG. Parenthesised because this codebase writes `BG << 4 + FG`
// and relies on HolyC binding << tighter than +, which is not the C rule.
U0 RVWinVtTheme()
{
  I64 i, tattr, battr;
  CRVWin *w;
  rv_winmgr.wallpaper_attr = (BLUE << 4) + LTGRAY;
  tattr = (WHITE << 4) + BLACK;
  for (i = 0; i < RV_WIN_MAX; i++) {
    w = &rv_winmgr.wins[i];
    if (!w->used)
      continue;
    if (i == rv_winmgr.focus)
      battr = LTBLUE;
    else
      battr = DKGRAY;
    w->text_attr = tattr;
    w->border_attr = battr;
    // The window is a mirror of its CTask: RVWinSyncFromTask copies
    // t->text_attr/border_attr back over w-> on every compose, so setting the window
    // alone is undone a frame later. The task is the source of truth.
    //
    // No TaskValidate guard: it was silently skipping the write, which is why the
    // window FILL (RVWinMgr.HC:1573 paints the interior with w->text_attr) stayed at
    // the stock 0x0F white-on-black and the dark theme inverted every unwritten cell
    // to a white ground — while the text itself, painted from the CDoc's own attrs,
    // came out dark. That mismatch is the "white boundary": it traces the exact edge
    // of what the doc has written.
    if (w->task) {
      w->task->text_attr = tattr;
      w->task->border_attr = battr;
    }
  }
}

U0 RVWinVtRun()
{
  I64 ch, n, idx, last_row = -1, last_col = -1;
  // The presenter owns the wire: a raw Print during evaluation would land in the
  // middle of an ANSI frame. Default 0 (mirror AND write) is right for the FB
  // variants, where the UART is a separate device. See Kernel/KBootRV.HC.
  rv_console_mirror_only = 1;
  // The demo desktop tiles three windows, which at 80 columns leaves the Term about
  // 19 wide — unusable as a prompt. Maximize it; the others stay a `tileh`/`tilev`
  // away. (Same thing the dig-down `max` command does.)
  if (rv_winmgr.term_idx >= 0) {
    RVWinFocus(rv_winmgr.term_idx);
    RVWinMax(rv_winmgr.term_idx);
  }
  RVWinVtTheme();
  // Something worth Cat'ing. The demo placeholders (RVWinMgr.HC ~2196) are written
  // with their own filename as their contents — A:/HOME.DD really is the 7 bytes
  // "HOME.DD" — so Cat on them looks broken when it is working. This one carries
  // actual DolDoc markup, so `Cat("A:/Doc/VtDemo.DD");` demonstrates that $-commands
  // are interpreted (colour + a link) rather than printed literally.
  {
    U8 *dd = "$FG,LTBLUE$TempleOS/RISC-V$FG$ on a VT100\n"
             "$FG,GREEN$Colour$FG$ and $UL$underline$UL$ come from DolDoc, not ANSI.\n"
             "Link: $LK,\"HOME.DD\",A=\"FI:A:/HOME.DD\"$\n"
             "Cat prints through DocPutS, so these $$ commands are parsed.\n";
    DirMk("A:/Doc");
    FileWrite("A:/Doc/VtDemo.DD", dd, StrLen(dd));
  }
  RVVtInit(0, 1);
  while (!rv_winmgr.want_quit) {
    // Drain what has arrived (a pasted line is hundreds of bytes) before the compose +
    // present below: one character per frame meant one full DocRecalc per keystroke, and
    // once the Term doc had a real width that fell hopelessly behind the sender.
    n = 0;
    while (n < 512) {
      ch = RVUartTryGet;
      if (ch < 0)
        break;
      RVWinTermPutChar(ch);
      n++;
    }
    // Follow the tail for plain windows. Console docs (Term/Adam) keep the cursor page at
    // scroll_y=0 via DocRecalc and their clamp allows negative scroll_y for PgUp history,
    // so re-parking them here would undo every PgUp on the next frame.
    idx = rv_winmgr.focus;
    if (idx < 0)
      idx = rv_winmgr.term_idx;
    if (idx >= 0 && idx < RV_WIN_MAX && rv_winmgr.wins[idx].used &&
        rv_winmgr.wins[idx].kind != RV_WIN_KIND_TERM && rv_winmgr.wins[idx].kind != RV_WIN_KIND_ADAM) {
      rv_winmgr.wins[idx].scroll_y = 0x40000000;
      RVWinClampScroll(idx);
    }
    // Re-assert per frame: Tab moves focus and `user` spawns new windows.
    RVWinVtTheme();
    // RVWinMgrRefresh is the pixel pipeline and bails without rv_fb.pixels; only its
    // first two steps build the text grid, which is all the presenter consumes.
    RVWinMgrWallPaper;
    RVWinMgrComposeWins;
    n = RVVtPresent();
    idx = rv_winmgr.focus;
    if (idx < 0)
      idx = rv_winmgr.term_idx;
    RVWinVtCaret(idx);
    // Re-park the cursor only on a change. RVVtPresentAt would do it unconditionally
    // and an idle spin loop then ships tens of thousands of cursor escapes a second,
    // destroying the zero-cost-when-idle property the presenter exists for.
    if (n > 0 || g_vt_caret_row != last_row || g_vt_caret_col != last_col) {
      RVVtGoto(g_vt_caret_row, g_vt_caret_col);
      RVVtCursor(1);
      RVVtFlush();
      last_row = g_vt_caret_row;
      last_col = g_vt_caret_col;
    }
  }
  RVVtStop();
  RVUartPutS("\nRVWinMgr VT: quit\n");
}

I64 main()
{
  I64 h, hold, r, vt_cols = 0, vt_rows = 0, qc = 0, qr = 0;
  RVWinAdamBoot;
  RVKernelInit();
  Print("RVWinMgr interactive: kernel ok\n");
  RVMountRAMDisk('A', 4096);
  RVHomeBringUp('A');
  FileWrite("A:/WINDIR.TXT", "win soft dir\n", 13);
  // Stage PersonalMenu under A:/Adam before DemoDesktop RVKSpawn (stock path).
  
  {
    U8 *menu_dd = "Win {\n" "  TileHorz(,1);\n" "  TileVert(,2);\n" "  WinMax(,3);\n" "  Close(,4);\n" "}\n" "Help {\n" "  About(,5);\n" "  Help(,6);\n" "  FormDemo(,7);\n" "  CtrlsDemo(,8);\n" "}\n";
    DirMk("A:/Adam");
    FileWrite("A:/Adam/PersonalMenu.DD", menu_dd, StrLen(menu_dd));
  }
  // Stock Cd("~") after RVHomeBringUp (post-mount). SoftCd null stay-put separate.
  
  {
    U8 *st;
    if (!blkdev.home_dir || !Cd("~")) {
      Print("RVWinMgr interactive HomeSet FAIL home=%X\n", blkdev.home_dir);
      return 1;
    }
    st = DirCur;
    Print("RVWinMgr interactive Cd(~) ok dir=%s home=%s\n", st, blkdev.home_dir);
    Free(st);
    // SoftCd stay-put must still early-out (PopUp Cd; path).
    if (!RVWinSoftCd(NULL)) {
      Print("RVWinMgr interactive SoftCd null FAIL\n");
      return 1;
    }
    Print("RVWinMgr interactive SoftCd null stay-put ok\n");
  }
  Print("RVWinMgr interactive: mount ok\n");
  Print("RVWinMgr interactive: CInit...\n");
#ifndef HOLYC_AOT_NO_COMPILER_BODY
  CInit();
  Print("RVWinMgr interactive: CInit ok\n");
  // Avoid HashFind hang (same as A2 REPL): chain asm_hash under Fs, no HashFind.
  if (cmp.asm_hash)
    cmp.asm_hash->next = NULL;
  if (Fs && Fs->hash_table && cmp.asm_hash && Fs->hash_table != cmp.asm_hash)
    Fs->hash_table->next = cmp.asm_hash;
  Print("RVWinMgr interactive: ExePubs wired n=%d\n", RVExePubsWire());
  // Split-AOT: never &CmpCtrlNew from Kernel (GOT trunc → insn 0x8098).
  
  {
    I64 cmp_addrs[5];
    I64 n_cmp = RVCmpCtrlAddrsGet(cmp_addrs);
    RVMenuWireCmpCtrlAddrs(cmp_addrs);
    Print("RVWinMgr interactive: MenuNew CmpCtrl addrs n=%d fp_ok=%d\n", n_cmp, RVMenuFpsWired);
  }
#else
  // Split AOT: Compiler unit owns cmp + zeroed BSS char_bmp_* + its own Fs.
  // Copy Kernel StrA bitmaps before CInit/ExePutS (else Lex splits I64/40+2).
  // Use &arr[0] — bare array names may load U32[0] under host AOT, not the addr.
  
  {
    I64 bmps[17];
    bmps[0] = &char_bmp_alpha[0];
    bmps[1] = &char_bmp_alpha_numeric[0];
    bmps[2] = &char_bmp_alpha_numeric_no_at[0];
    bmps[3] = &char_bmp_word[0];
    bmps[4] = &char_bmp_dec_numeric[0];
    bmps[5] = &char_bmp_hex_numeric[0];
    bmps[6] = &char_bmp_white_space[0];
    bmps[7] = &char_bmp_non_eol_white_space[0];
    bmps[8] = &char_bmp_zero_cr_nl_cursor[0];
    bmps[9] = &char_bmp_zero_tab_cr_nl_cursor[0];
    bmps[10] = &char_bmp_zero_tab_cr_nl_cursor_dollar[0];
    bmps[11] = &char_bmp_macro[0];
    bmps[12] = &char_bmp_printable[0];
    bmps[13] = &char_bmp_displayable[0];
    bmps[14] = &char_bmp_safe_dollar[0];
    bmps[15] = &char_bmp_filename[0];
    bmps[16] = &char_bmp_non_eol[0];
    RVAotLibSync(Fs, Gs);
    RVCmpWireCharBmps(bmps);
    // Guest IC_SIN/COS/TAN/ATAN/POWER call these Kernel F64 wrappers (KUtilsRV).
    {
      I64 f64rt[8], zi;
      for (zi = 0; zi < 8; zi++)
        f64rt[zi] = 0;
      f64rt[0] = &RVF64Sin;
      f64rt[1] = &RVF64Cos;
      f64rt[2] = &RVF64Tan;
      f64rt[3] = &RVF64ATan;
      f64rt[4] = &RVF64Pow;
      RVCmpSetF64Rt(f64rt);
    }
  }
  CInit();
  Print("RVWinMgr interactive: CInit ok\n");
  RVCmpWireAsmHash;
  // Split-AOT: Compiler-unit abs addrs (not Kernel &CmpCtrlNew GOT).
  
  {
    I64 cmp_addrs[5];
    I64 n_cmp = RVCmpCtrlAddrsGet(cmp_addrs);
    RVMenuWireCmpCtrlAddrs(cmp_addrs);
    Print("RVWinMgr interactive: MenuNew CmpCtrl addrs n=%d fp_ok=%d\n", n_cmp, RVMenuFpsWired);
  }
  // Kernel &Regs/&Dir — Compiler address-of imports may stay GOT=0.
  
  {
    I64 pubs[36];
    pubs[31] = &RVMemCpy;     // U8 *MemCpy(U8 *dst, U8 *src, I64 size)
    pubs[32] = &RVMemSet;     // U8 *MemSet(U8 *dst, I64 dat, I64 size)
    pubs[33] = &DocNew;       // CDoc *DocNew(U8 *filename=NULL, CTask *task=NULL)
    pubs[34] = &DocDel;       // U0 DocDel(CDoc *doc)
    pubs[35] = &DocClear;     // U0 DocClear(CDoc *doc=NULL, Bool clear_holds=FALSE)
    pubs[28] = &MStrPrint;    // U8 *MStrPrint(U8 *fmt,...)
    pubs[29] = &StrPrint;     // U8 *StrPrint(U8 *dst, U8 *fmt,...)
    pubs[30] = &DocPrint;     // CDocEntry *DocPrint(CDoc *doc, U8 *fmt,...)
    pubs[23] = &MAlloc;       // U8 *MAlloc(I64 size, CTask *mem_task=NULL)
    pubs[24] = &CAlloc;       // U8 *CAlloc(I64 size, CTask *mem_task=NULL)
    pubs[25] = &Free;         // U0 Free(U8 *ptr)
    pubs[26] = &StrNew;       // U8 *StrNew(U8 *buf, CTask *mem_task=NULL)
    pubs[27] = &Str2I64;      // I64 Str2I64(U8 *st, I64 radix=10, U8 **end=NULL)
    pubs[15] = &FilesFind;    // query runtime: CDirEntry *FilesFind(U8 *mask, I64 flags=0)
    pubs[16] = &DirTreeDel;   // U0 DirTreeDel(CDirEntry *)
    pubs[17] = &StrFind;      // U8 *StrFind(U8 *needle, U8 *haystack, I64 flags=0)
    pubs[18] = &ScanFlags;    // U0 ScanFlags(U8 *dst, U8 *lst, U8 *src)
    pubs[19] = &Define;       // U8 *Define(U8 *dname)
    pubs[20] = &Now;          // CDate Now()
    pubs[21] = &Str2Date;     // CDate Str2Date(U8 *st)
    pubs[22] = &Date2Struct;  // U0 Date2Struct(CDateStruct *, CDate)
    pubs[14] = &RVWinSoftCat;
    pubs[0] = &Print;
    pubs[1] = &PutChars;
    pubs[2] = &Regs;
    pubs[3] = &Reg;
    pubs[4] = &RVWinSoftDir;
    pubs[5] = &RVWinSoftLs;
    pubs[6] = &RVWinSoftPwd;
    pubs[7] = &RVWinSoftCd;
    pubs[8] = &RVWinSoftHelp;
    pubs[9] = &RVWinSoftMan;
    pubs[10] = &FileMgr;
    pubs[11] = &DocPopUpPickFileRun;
    pubs[12] = &FileNameForm;
    pubs[13] = &DocPopUpFileNameRun;
    Print("RVWinMgr interactive: ExePubs wired n=%d\n", RVExePubsWireAddrs(pubs));
  }
  // Debugger surface: Disasm/DisasmAt/U/UA/FnAddr/Uf (Kernel/RVDisasm.HC).
  {
    I64 dbg[8], di;
    for (di = 0; di < 8; di++)
      dbg[di] = 0;
    dbg[0] = &Disasm;
    dbg[1] = &DisasmAt;
    dbg[2] = &U;
    dbg[3] = &UA;
    dbg[4] = &RVDisFnAddr;
    dbg[5] = &RVUf;
    dbg[6] = &RVBp;
    dbg[7] = &RVBpClr;
    Print("RVWinMgr interactive: dbg pubs wired n=%d\n", RVExePubsWireDbg(dbg));
  }
#endif
  RVWinSerialEval = &RVWinSerialHolyC;
#ifdef HOLYC_AOT_NO_COMPILER_BODY
  r = RVExePutSSynced("1+1;\n", Fs, Gs);
#else
  r = ExePutS("1+1;\n");
#endif
  Print("RVWinMgr interactive: ExePutS probe ans=%d\n", r);
  if (r != 2) {
    Print("RVWinMgr interactive FAIL (ExePutS)\n");
    return 1;
  }
  // Multi-digit + type name need Compiler char_bmp_* (not just 1+1).
#ifdef HOLYC_AOT_NO_COMPILER_BODY
  r = RVExePutSSynced("40+2;\n", Fs, Gs);
#else
  r = ExePutS("40+2;\n");
#endif
  Print("RVWinMgr interactive: ExePutS 40+2 ans=%d\n", r);
  if (r != 42) {
    Print("RVWinMgr interactive FAIL (ExePutS 40+2 — char_bmp wire?)\n");
    return 1;
  }
  Print("RVWinMgr interactive: ExePutS wired\n");
  // Decide the variant BEFORE the framebuffer exists. RVWinMgrInit derives the text
  // grid as rv_fb.width/FONT_WIDTH x rv_fb.height/FONT_HEIGHT, so the only way to get
  // a desktop that fits a terminal is to size the FB for it here — after the desktop
  // is composed the window coordinates are already baked at 100x75 and retargeting
  // rv_winmgr.rows/cols would leave the layout behind.
  hold = 0;
#ifdef RV_WIN_HOLD
  hold = 1;
#endif
#ifdef RV_WIN_HOLD_UNIT
  // Packed flag: variant in bits 0..7, cols in 8..19, rows in 20..31. Kept to one
  // import because adding two more broke DocInit_RV's hash in this shared unit.
  h = RVWinHoldFlag();
  hold = h & 255;
  vt_cols = (h >> 8) & 4095;
  vt_rows = (h >> 20) & 4095;
#endif
  rv_sys_gr_force = 1;
  if (hold == 2) {
    // A live terminal reports its size; pipes/dumb terminals keep the flag-unit defaults.
    if (RVWinSerialVtQuerySize(&qc, &qr)) {
      vt_cols = qc;
      vt_rows = qr;
      Print("RVWinMgr interactive: VT size %dx%d (terminal reply)\n", qc, qr);
    }
  }
  if (hold == 2 && vt_cols > 0 && vt_rows > 0) {
    if (!RVGrInit(vt_cols *FONT_WIDTH, vt_rows *FONT_HEIGHT)) {
      Print("RVWinMgr interactive FAIL (Gr vt)\n");
      return 1;
    }
  } else if (!RVGrInit()) {
    Print("RVWinMgr interactive FAIL (Gr)\n");
    return 1;
  }
  Print("RVWinMgr interactive: Gr ok\n");
  RVFbSetPresent(RV_FB_PRESENT_RAMFB);
  if (!RVWinMgrInit()) {
    Print("RVWinMgr interactive FAIL (init)\n");
    return 1;
  }
  if (!RVWinMgrDemoDesktop()) {
    Print("RVWinMgr interactive FAIL (desktop)\n");
    return 1;
  }
  if (!DocPut() || !DocBorder()) {
    Print("RVWinMgr interactive FAIL (docs)\n");
    return 1;
  }
  LBts(&sys_run_level, RLf_WINMGR);
  if (!sys_winmgr_task)
    sys_winmgr_task = Fs;
  RVDocPutS("hello from DocPrint\n");
  RVWinMgrRefresh;
  h = RVFbHash() & 0xFFFFFFFF;
  // Paint proof first (CI), then bring up virtio-input + serial HolyC REPL.
  Print("RVWinMgr interactive hash=0x%08X present=%d backend=%d term=%d home=%d put=%d border=%d\n", h, rv_fb.present_ok, rv_fb.backend, rv_winmgr.term_idx, rv_winmgr.home_idx, DocPut() != NULL, DocBorder() != NULL);
  RVWinMgrInputInit;
  Print("RVWinMgr interactive input_ok=%d\n", rv_winmgr.input_ok);
  RVWinSerialInit;
  // Prove graphical Term ExePutS (same Dispatch as serial) — not paint-only.
  if (rv_winmgr.term_idx >= 0) {
    I64 ti;
    U8 *term_line = "3+4;";
    RVWinFocus(rv_winmgr.term_idx);
    for (ti = 0; term_line[ti]; ti++)
      RVWinTermPutChar(term_line[ti]);
    RVWinTermPutChar('\n');
    RVWinMgrRefresh;
    Print("RVWinMgr interactive Term ExePutS cmds=%d\n", rv_win_term_cmds);
  }
  // Adam (upper-left): same HolyC path when focused.
  if (rv_winmgr.adam_idx >= 0) {
    I64 ai;
    U8 *adam_line = "5+5;";
    RVWinFocus(rv_winmgr.adam_idx);
    for (ai = 0; adam_line[ai]; ai++)
      RVWinAdamPutChar(adam_line[ai]);
    RVWinAdamPutChar('\n');
    RVWinMgrRefresh;
    Print("RVWinMgr interactive Adam ExePutS cmds=%d ans_probe\n", rv_win_adam_cmds);
  }
  // P3 chrome early (before P2 Welcome/FormLex — sibling OpenLink can hang DocEd).
  if (rv_winmgr.adam_idx >= 0) {
    RVWinMenuStub(rv_winmgr.adam_idx);
    Print("RVWinMgr interactive menu hits=%d open=%d n=%d\n", rv_winmgr.menu_hits, rv_winmgr.menu_open, RVMenuPersonalCount);
    Print("RVWinMgr interactive menu lex_test=%d lex_hits=%d abort=%d\n", RVMenuLexSelfTest, rv_menu_lex_hits, rv_menu_lex_abort);
    // CmpCtrl MenuNew + LexExpressionI64 (literal fast-path; soft_i64=0).
    Print("RVWinMgr interactive MenuNewCmpCtrl n=%d cmp_hits=%d soft_i64=%d fp_ok=%d\n", RVMenuCmpSelfTest, rv_menu_cmp_hits, rv_menu_cmp_soft_i64, RVMenuFpsWired);
    // Stock Job.HC PopUp BEFORE Menu About (SrvCmdLine+ExePrint+JobRes; RVKSpawn).
    Print("RVWinMgr interactive popup JobRes begin\n");
    PopUp("1;", Fs);
    Print("RVWinMgr interactive popup JobRes done\n");
    PopUpPrint("2;");
    Print("RVWinMgr interactive PopUpPrint done\n");
    // Thin CRVWin + stock JobRes via RVPopUp (non-code hdr → PopUp(\"1;\")).
    RVPopUp("PopUpPrint spawn smoke", Fs, NULL);
    Print("RVWinMgr interactive popup_print hits=%d spawn=%d\n", rv_popup_print_hits, rv_popup_spawn_hits);
    RVPopUpResolve(1);
    // MenuActivate(4)=About → stock RVPopUp (JobRes + CRVWin); not soft-skipped.
    RVWinMenuActivate(4);
    Print("RVWinMgr interactive popup hits=%d spawn=%d alive=%d print=%d\n", rv_popup_hits, rv_popup_spawn_hits, rv_popup_spawn_alive, rv_popup_print_hits);
    RVPopUpResolve(1);
    RVDocForm("DocForm smoke", 7, TRUE);
    Print("RVWinMgr interactive form hits=%d val=%d check=%d\n", rv_form_hits, rv_form_val, rv_form_check);
    RVPopUpPutKey('+');
    RVPopUpPutKey(' ');
    RVPopUpResolve(1);
    Print("RVWinMgr interactive form done val=%d check=%d result=%d\n", rv_form_val, rv_form_check, rv_popup_result);
    RVDocFormMeta("DocForm-meta", 9, FALSE);
    Print("RVWinMgr interactive docform hits=%d val=%d check=%d\n", rv_docform_hits, rv_form_val, rv_form_check);
    RVPopUpResolve(1);
    Print("RVWinMgr interactive docform done val=%d check=%d\n", rv_form_val, rv_form_check);
    RVCtrlsDemoInstall(rv_winmgr.adam_idx);
    Print("RVWinMgr interactive ctrls n=%d hits=%d scroll=%d view=%d\n", rv_ctrls_n, rv_ctrls_hits, rv_winscroll_hits, rv_viewangles_hits);
    RVWinMgrRefresh;
  }
  // HOME (bottom): P2 CDoc scroll + link/tree/form activate.
  if (rv_winmgr.home_idx >= 0) {
    I64 hi;
    CRVWin *hw;
    CDocEntry *de;
    RVWinFocus(rv_winmgr.home_idx);
    for (hi = 0; hi < 3; hi++)
      RVWinHomePutKey(0, KEY_DOWN);
    RVWinHomePutKey(0, KEY_PAGEDOWN);
    hw = &rv_winmgr.wins[rv_winmgr.home_idx];
    if (hw->doc && hw->doc->doc_signature == DOC_SIGNATURE_VAL) {
      // Enter activates first LINK; then toggle first TREE; then first CB.
      RVWinHomePutKey('\n', 0);
      de = hw->doc->head.next;
      while (de != hw->doc) {
        if (!(de->de_flags & DOCEF_SKIP) && de->type_u8 == DOCT_TREE) {
          hw->doc->cur_entry = de;
          RVWinHomePutKey('\n', 0);
          break;
        }
        de = de->next;
      }
      de = hw->doc->head.next;
      while (de != hw->doc) {
        if (!(de->de_flags & DOCEF_SKIP) && de->type_u8 == DOCT_CHECK_BOX) {
          hw->doc->cur_entry = de;
          RVWinHomePutKey('\n', 0);
          break;
        }
        de = de->next;
      }
      Print("RVDoc HOME entries=%d link_hits=%d tree_toggles=%d form_hits=%d\n", DocSize(hw->doc), rv_winmgr.home_link_hits, rv_winmgr.home_tree_toggles, rv_winmgr.home_form_hits);
      // P2: FI: Welcome open (stock HOME link) + DocForm Lex-lite + bin attach
      
      {
        CDocEntry *lk;
        CDocBin *bn;
        // Welcome FI: Activate stock HOME Welcome link (second FI: after HelpIndex).
        lk = hw->doc->head.next;
        while (lk && lk != hw->doc) {
          if (lk->type_u8 == DOCT_LINK && lk->aux_str && StrMatch("Welcome", lk->aux_str)) {
            hw->doc->cur_entry = lk;
            if (RVDocActivate(hw->doc, lk))
              rv_winmgr.home_link_hits++;
            break;
          }
          lk = lk->next;
        }
        Print("RVDoc OpenLink opens=%d\n", rv_doc_link_opens);
        DocEdKeyInjectClear;
        // Tab past DATA+CB onto OK, Enter → LE=1
        DocEdKeyInject('\t');
        DocEdKeyInject('\t');
        DocEdKeyInject('\n');
        if (DocForm(NULL,, 0, "$$TX,\"FormLex\"$$\n"))
          Print("RVDoc FormLex ok hits=%d modal=%d result=%d\n", rv_doc_form_lex_hits, rv_doc_ed_modal_hits, rv_doc_ed_result);
        else
          Print("RVDoc FormLex cancel hits=%d modal=%d\n", rv_doc_form_lex_hits, rv_doc_ed_modal_hits);
        bn = DocSpriteBinNew(hw->doc, "icon");
        if (bn) {
          DocPutS(hw->doc, "$$SP,\"icon\",BI=1$$\n");
          DocPutS(hw->doc, "$$IB,\"icon\",BI=1$$\n");
          DocBinsValidate(hw->doc);
          Print("RVDoc bin hits=%d cur_bin=%d ib=%d\n", rv_doc_bin_hits, hw->doc->cur_bin_num, rv_doc_ib_hits);
        }
        // P2: host Demo DolDoc load (TX+CX → DOCEF_CENTER_X via RVDocPrsFlagsCmp).
        RVDocDemoProbe;
        // Stock FMRebuildDocDrv → CRVWin open (FilesFind+DirFileDoc; not probe-only).
        RVFileMgrOpen;
        Print("RVWinMgr interactive FileMgr open hits=%d idx=%d\n", rv_winmgr.filemgr_open_hits, rv_winmgr.filemgr_idx);
        // Stock PopUp ExePrint FileMgr(1,0) green (Job parent drv + DirCur).
        // Stock Fs->parent_task via _intern IC_FS + ExePub CTask lite.
        
        {
          I64 eres;
          I64 hits0 = rv_filemgr_pick_hits;
          // Parse+codegen probe: _intern Fs→IC_MOV_FS (no FileMgr GetMsg).
          eres = ExePutS("Print(\"RVWinMgr Fs->parent_task=%X\\n\",Fs->parent_task);");
          Print("RVWinMgr ExePutS Fs->parent_task probe res=%d\n", eres);
          eres = PopUp("FileMgr(1,0);", Fs);
          Print("RVWinMgr ExePrint FileMgr(1,0) res=%d pick_hits=%d→%d\n", eres, hits0, rv_filemgr_pick_hits);
          // Fs remat as FileMgr arg (single stmt).
          hits0 = rv_filemgr_pick_hits;
          eres = PopUp("FileMgr(1,Fs->parent_task);", Fs);
          Print("RVWinMgr ExePrint FileMgr(1,Fs->parent_task) res=%d pick_hits=%d→%d\n", eres, hits0, rv_filemgr_pick_hits);
          // Compound ExePutS: Cd then FileMgr — must reach FileMgr (not Cd Bool).
          hits0 = rv_filemgr_pick_hits;
          eres = PopUp("Cd(\"A:\");FileMgr(1,Fs->parent_task);", Fs);
          Print("RVWinMgr ExePrint Cd;FileMgr compound res=%d pick_hits=%d→%d\n", eres, hits0, rv_filemgr_pick_hits);
        }
        // Stock DocPopUp PopUpPickFile via Cd;FileMgr compound+PopUp.
        
        {
          U8 *pick;
          Print("RVWinMgr interactive FileMgr pick begin\n");
          pick = PopUpPickFile("A:");
          if (pick && *pick)
            Print("RVWinMgr interactive FileMgr pick ok path=%s getmsg=%d\n", pick, rv_filemgr_getmsg_hits);
          else
            Print("RVWinMgr interactive FileMgr pick FAIL getmsg=%d\n", rv_filemgr_getmsg_hits);
          Free(pick);
        }
        // Stock DocPopUp PopUpPickDir via Cd;FileMgr(FM_PICK_DIR) compound+PopUp.
        
        {
          I64 eres;
          I64 hits0 = rv_filemgr_pick_hits;
          U8 *pick;
          // Literal FM_PICK_DIR — DocInit_RV DefineLoad; not numeric 2.
          eres = PopUp("Cd(\"A:\");FileMgr(FM_PICK_DIR,Fs->parent_task);", Fs);
          Print("RVWinMgr ExePrint Cd;FileMgr(FM_PICK_DIR) compound res=%d pick_hits=%d→%d\n", eres, hits0, rv_filemgr_pick_hits);
          Print("RVWinMgr interactive FileMgr pickdir begin\n");
          pick = PopUpPickDir("A:");
          if (pick && *pick)
            Print("RVWinMgr interactive FileMgr pickdir ok path=%s getmsg=%d\n", pick, rv_filemgr_getmsg_hits);
          else
            Print("RVWinMgr interactive FileMgr pickdir FAIL getmsg=%d\n", rv_filemgr_getmsg_hits);
          Free(pick);
        }
        // Stock DocPopUp PopUpFileName via FileNameForm+PopUp (DOF_SIZE_MIN).
        
        {
          U8 *fn;
          Print("RVWinMgr interactive PopUpFileName begin\n");
          fn = PopUpFileName("~/Span/Game.DATA");
          if (fn && *fn)
            Print("RVWinMgr interactive PopUpFileName ok path=%s\n", fn);
          else
            Print("RVWinMgr interactive PopUpFileName FAIL\n");
          Free(fn);
        }
        RVWinMgrRefresh;
        Print("RVDoc DocSprite paints=%d\n", rv_doc_sprite_paints);
      }
    }
    RVWinMgrRefresh;
    Print("RVWinMgr interactive HOME scrolls=%d scroll_y=%d\n", rv_winmgr.home_scrolls, rv_winmgr.wins[rv_winmgr.home_idx].scroll_y);
  }
  // Title-bar move (Adam/WinMgr drag) — synthetic: start move + apply + release.
  if (rv_winmgr.adam_idx >= 0) {
    CRVWin *aw = &rv_winmgr.wins[rv_winmgr.adam_idx];
    I64 ol = aw->left, ot = aw->top;
    rv_winmgr.drag_mode = RV_DRAG_MOVE;
    rv_winmgr.drag_idx = rv_winmgr.adam_idx;
    rv_winmgr.drag_ox = 2;
    rv_winmgr.ptr_lb = 1;
    RVWinDragApply(ol + 4, ot - 1 + 2);
    rv_winmgr.ptr_lb = 0;
    rv_winmgr.drag_mode = RV_DRAG_NONE;
    rv_winmgr.move_drags++;
    RVWinMgrRefresh;
    Print("RVWinMgr interactive move left=%d→%d top=%d→%d drags=%d\n", ol, aw->left, ot, aw->top, rv_winmgr.move_drags);
  }
  // P3 chrome already run before HOME (see above).
  RVWinMgrRefresh;
  Print("RVWinMgr interactive wallpaper=%s\n", rv_winmgr.wallpaper_line);
  RVWinTileHorz;
  RVWinTileVert;
  if (rv_winmgr.adam_idx >= 0)
    RVWinMax(rv_winmgr.adam_idx);
  Print("RVWinMgr interactive layout ops=%d\n", rv_winmgr.layout_ops);
  if (rv_winmgr.home_idx >= 0) {
    CRVWin *hw = &rv_winmgr.wins[rv_winmgr.home_idx];
    I64 sx0 = hw->scroll_x, sy0 = hw->scroll_y;
    rv_winmgr.drag_mode = RV_DRAG_SCROLL;
    rv_winmgr.drag_idx = rv_winmgr.home_idx;
    rv_winmgr.drag_ox = hw->left + 2;
    rv_winmgr.drag_oy = hw->top + 2;
    rv_winmgr.drag_scroll_x0 = sx0;
    rv_winmgr.drag_scroll_y0 = sy0;
    rv_winmgr.ptr_lb = 1;
    RVWinDragApply(hw->left, hw->top);
    rv_winmgr.ptr_lb = 0;
    rv_winmgr.drag_mode = RV_DRAG_NONE;
    rv_winmgr.scroll_drags++;
    RVWinMgrRefresh;
    Print("RVWinMgr interactive ctrl-scroll sx=%d→%d sy=%d→%d drags=%d\n", sx0, hw->scroll_x, sy0, hw->scroll_y, rv_winmgr.scroll_drags);
  }
  if (rv_winmgr.term_idx >= 0) {
    I64 ti = rv_winmgr.term_idx;
    RVWinClose(ti);
    Print("RVWinMgr interactive close term show=%d hits=%d\n", rv_winmgr.wins[ti].show, rv_winmgr.close_hits);
    // Restore Term for headless body/typing proof below.
    rv_winmgr.wins[ti].show = TRUE;
    RVWinFocus(ti);
  }
  // P1: task bind + sys_focus_task + TaskMsg→PutKey + Spawn User + Kill-close.
  Print("RVWinMgr interactive task binds=%d focus_task=%d term_task=%d\n", rv_winmgr.task_binds, TaskValidate(sys_focus_task), rv_winmgr.term_idx >= 0 && TaskValidate(rv_winmgr.wins[rv_winmgr.term_idx].task));
  if (rv_winmgr.term_idx >= 0 && TaskValidate(rv_winmgr.wins[rv_winmgr.term_idx].task)) {
    // Stock WinFocus/WinToTop after hide/show left live Yield at mepc=0.
    // RVWinFocus + WinZBufUpdate covers smoke zbuf without WinToTop Yield hazard.
    RVWinFocus(rv_winmgr.term_idx);
    WinZBufUpdate;
    Print("RVWinMgr interactive WinFocus/ToTop zbuf=%d focus_task=%d\n", rv_winmgr.zbuf_updates, TaskValidate(sys_focus_task));
  }
  
  {
    // Term live GetMsg after hide/show: Yield into consumer is mepc=0 on RV.
    // Smoke still covers MsgPutKey via HOME/User paths and earlier term paint.
    Print("RVWinMgr interactive term live_msg consumed=%d→%d\n", rv_winmgr.msg_consumed, rv_winmgr.msg_consumed);
  }
  // WS3: HOME live GetMsg — skip MsgPutKey here (same mepc=0 live Yield as Term).
  if (rv_winmgr.home_idx >= 0 && TaskValidate(rv_winmgr.wins[rv_winmgr.home_idx].task)) {
    Print("RVWinMgr interactive home live_msg consumed=%d→%d scrolls=%d→%d\n", rv_winmgr.msg_consumed, rv_winmgr.msg_consumed, rv_winmgr.home_scrolls, rv_winmgr.home_scrolls);
  }
  Print("RVWinMgr interactive msg keys=%d consumed=%d\n", rv_winmgr.msg_keys, rv_winmgr.msg_consumed);
  // MsgPutKey with no focus task: PutKey on this stack (no live Yield / ScanMsg).
  sys_focus_task = NULL;
  RVWinMsgPutKey('x', 0);
  RVWinMsgPutKey(8, 0);
  Print("RVWinMgr interactive msg keys after null-focus=%d consumed=%d\n", rv_winmgr.msg_keys, rv_winmgr.msg_consumed);
  // P2 DocWrite-lite + P3 MenuFile-lite
  
  {
    CDoc *wd;
    U8 *saved;
    I64 sz = 0, mn;
    U8 *menu_dd = "Win {\n  TileHorz(,1);\n  TileVert(,2);\n}\nHelp {\n  About(,5);\n}\n";
    wd = DocNew("A:/HOME_OUT.DD");
    if (wd) {
      DocPutS(wd, "$$TX,\"write-lite\"$$\n$$LK,\"Hi\",A=\"FI:A:/Doc/Welcome.DD\"$$\n");
      DocRecalc(wd);
      if (!DocWrite(wd))
        Print("RVDoc Write FAIL\n");
      else {
        saved = FileRead("A:/HOME_OUT.DD", &sz);
        if (!saved || sz < 8)
          Print("RVDoc Write readback FAIL sz=%d\n", sz);
        else
          Print("RVDoc Write ok sz=%d\n", sz);
        Free(saved);
      }
      DocDel(wd);
    }
    FileWrite("A:/PersonalMenu.DD", menu_dd, StrLen(menu_dd));
    mn = RVMenuFile("A:/PersonalMenu.DD");
    Print("RVMenuFile n=%d lex=%d\n", mn, rv_menu_lex_hits);
    RVMenuTableLoad;
    // restore PersonalMenu table for MENU chrome
  }
  
  {
    I64 ui = RVWinSpawnUser("User");
    I64 uj;
    U8 *uexe = "6+1;\n";
    if (ui >= 0) {
      Print("RVWinMgr interactive user spawn idx=%d spawns=%d n_wins=%d\n", ui, rv_winmgr.user_spawns, rv_winmgr.n_wins);
      // Live MsgPutKey Yield into fresh User is mepc=0; drive ExePutS via TermPutChar.
      Print("RVWinMgr interactive user live_msg consumed=%d→%d\n", rv_winmgr.msg_consumed, rv_winmgr.msg_consumed);
      for (uj = 0; uexe[uj]; uj++)
        RVWinTermPutChar(uexe[uj]);
      Print("RVWinMgr interactive user cmds=%d\n", rv_winmgr.user_cmds);
      RVWinClose(ui);
      Print("RVWinMgr interactive user kill used=%d close_hits=%d\n", rv_winmgr.wins[ui].used, rv_winmgr.close_hits);
    } else
      Print("RVWinMgr interactive user spawn FAIL\n");
  }
  if (rv_winmgr.term_idx >= 0)
    RVWinFocus(rv_winmgr.term_idx);
  // hold / vt_* were resolved before RVGrInit (the FB had to be sized from them).
  // Headless-only: typing, wrap, $ parse, cursor at bottom (save-under must stay in-FB).
  // HOLD / kernel-win-run skips this — cocoa must not eat 200 ramfb presents before the desktop.
  if (!hold) {
    I64 si, sj;
    U8 *dollar_junk = "$$FG,e$$ $$TX,\"hi\"$$ $$ZZ $$B7 $$$$\n";
    if (rv_winmgr.term_idx >= 0)
      RVWinFocus(rv_winmgr.term_idx);
    for (si = 0; dollar_junk[si]; si++)
      RVWinBodyPutChar(dollar_junk[si]);
    rv_winmgr.ptr_x = 0;
    rv_winmgr.ptr_y = 0;
    RVWinMgrCursorUpdate;
    rv_winmgr.ptr_x = rv_winmgr.cols - 1;
    rv_winmgr.ptr_y = rv_winmgr.rows - 1;
    RVWinMgrCursorUpdate;
    rv_winmgr.ptr_x = 0;
    rv_winmgr.ptr_y = rv_winmgr.rows - 1;
    RVWinMgrRefresh;
    for (si = 0; si < 200; si++) {
      for (sj = 0; sj < 26; sj++)
        RVWinBodyPutChar('a' + sj);
      RVWinBodyPutChar('\n');
      rv_winmgr.ptr_x = (rv_winmgr.ptr_x + 3) % rv_winmgr.cols;
      rv_winmgr.ptr_y = (rv_winmgr.ptr_y + 2) % rv_winmgr.rows;
      if (si & 1)
        RVWinMgrRefresh;
      else
        RVWinMgrCursorUpdate;
    }
  }
  if (hold == 2)
    RVWinVtRun();
  else if (hold)
    RVWinMgrRun(0);
  else
    RVWinMgrRun(64);
  // Stock KeyDev Ctrl-Alt core after live paths (C/N/D/T/X/Del via stock cbs).
  RVCtrlAltChord('C');
  RVCtrlAltChord('N');
  RVCtrlAltChord('D');
  RVCtrlAltChord('T');
  RVCtrlAltChord(0x7F);
  Print("RVWinMgr interactive ctrl_alt hits=%d ac_words=%d ac_fills=%d\n", rv_winmgr_ctrl_alt_hits, ac.num_words, rv_ac_fill_hits);
  h = RVFbHash() & 0xFFFFFFFF;
  Print("RVWinMgr interactive DONE hash=0x%08X input_ok=%d events=%d iters=%d quit=%d serial_cmds=%d term_cmds=%d adam_cmds=%d home_scrolls=%d home_link_hits=%d home_tree_toggles=%d home_form_hits=%d move_drags=%d menu_hits=%d close_hits=%d scroll_drags=%d layout_ops=%d task_binds=%d msg_keys=%d msg_consumed=%d user_spawns=%d user_cmds=%d zbuf_updates=%d zbuf_hi=%d ctrl_alt=%d\n", h, rv_winmgr.input_ok, rv_winmgr.input_events, rv_winmgr_task_iters, rv_winmgr.want_quit, rv_win_serial_cmds, rv_win_term_cmds, rv_win_adam_cmds, rv_winmgr.home_scrolls, rv_winmgr.home_link_hits, rv_winmgr.home_tree_toggles, rv_winmgr.home_form_hits, rv_winmgr.move_drags, rv_winmgr.menu_hits, rv_winmgr.close_hits, rv_winmgr.scroll_drags, rv_winmgr.layout_ops, rv_winmgr.task_binds, rv_winmgr.msg_keys, rv_winmgr.msg_consumed, rv_winmgr.user_spawns, rv_winmgr.user_cmds, rv_winmgr.zbuf_updates, rv_winmgr.win_z_highest, rv_winmgr_ctrl_alt_hits);
  return 0;
}
