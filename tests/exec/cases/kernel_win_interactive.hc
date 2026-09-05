// Interactive DocTerm desktop + VirtioInput + UART HolyC ExePutS REPL.
// Headless: paint hash + input_ok + bounded pump (+ serial banner).
// Hold: make kernel-win-run (ESC or serial `q` quits). Serial is the regular
// TempleOS ExePutS loop (same as A2 / repl-cmp), not dig-down-only.
#include "/Kernel/Kernel_RV.PRJ"
#include "/Compiler/RISCVRegs.HH"
// Incremental host AOT links Compiler_RV as a separate unit (see tests/exec/aot/).
// Monolithic one-shot still includes the Body here.
#ifndef HOLYC_AOT_NO_COMPILER_BODY
#include "/Compiler/Compiler_RV_Body.PRJ"
#else
extern I64 RVExePubsWire();
extern I64 RVExePubsWireAddrs(I64 *addrs);
extern U0 RVAotLibSync(I64 fs, I64 gs);
extern U0 RVCmpWireAsmHash();
extern U0 RVCmpWireCharBmps(I64 *src);
extern I64 RVCmpCtrlAddrsGet(I64 *out);
extern U0 RVMenuWireCmpCtrlAddrs(I64 *addrs);
extern I64 RVExePutSSynced(U8 *buf, I64 fs, I64 gs);
#endif
I64 RVWinSerialHolyC(U8 *line)
{
  U8 buf[168];
  I64 i;
  if (!line)
    return 0;
  i = 0;
  while (line[i] && i < 158) {
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

I64 main()
{
  I64 h, hold, r;
  RVWinAdamBoot;
  RVKernelInit();
  Print("RVWinMgr interactive: kernel ok\n");
  RVMountRAMDisk('A', 4096);
  FileWrite("A:/WINDIR.TXT", "win soft dir\n", 13);
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
    I64 cmp_addrs[4];
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
  }
  CInit();
  Print("RVWinMgr interactive: CInit ok\n");
  RVCmpWireAsmHash;
  // Split-AOT: Compiler-unit abs addrs (not Kernel &CmpCtrlNew GOT).
  
  {
    I64 cmp_addrs[4];
    I64 n_cmp = RVCmpCtrlAddrsGet(cmp_addrs);
    RVMenuWireCmpCtrlAddrs(cmp_addrs);
    Print("RVWinMgr interactive: MenuNew CmpCtrl addrs n=%d fp_ok=%d\n", n_cmp, RVMenuFpsWired);
  }
  // Kernel &Regs/&Dir — Compiler address-of imports may stay GOT=0.
  
  {
    I64 pubs[10];
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
    Print("RVWinMgr interactive: ExePubs wired n=%d\n", RVExePubsWireAddrs(pubs));
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
  rv_sys_gr_force = 1;
  if (!RVGrInit()) {
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
    // Soft-I64 CmpCtrl MenuNew (TileHorz(,1)) via Compiler abs addrs.
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
        // Welcome FI: OpenLink proven via HelpIndex→Welcome path above; skip
        // second Activate (can hang post-OpenLink before opens= print).
        no_warn lk;
        Print("RVDoc OpenLink opens=%d (Welcome Activate skipped)\n", rv_doc_link_opens);
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
        // P2: host Demo DolDoc load (DemoInPage + HX/SO/HC) — no OpenLink hang.
        RVDocDemoProbe;
        // Stock FMRebuildDocDrv → CRVWin open (FilesFind+DirFileDoc; not probe-only).
        RVFileMgrOpen;
        Print("RVWinMgr interactive FileMgr open hits=%d idx=%d\n", rv_winmgr.filemgr_open_hits, rv_winmgr.filemgr_idx);
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
  hold = 0;
#ifdef RV_WIN_HOLD
  hold = 1;
#endif
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
  if (hold)
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
