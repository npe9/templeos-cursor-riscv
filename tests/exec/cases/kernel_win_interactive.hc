// Interactive DocTerm desktop + VirtioInput proof.
// Headless: paint hash + input_ok + bounded pump. Hold: make kernel-win-run (ESC quits).
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 h, hold;
  RVKernelInit();
  rv_sys_gr_force = 1;
  if (!RVGrInit()) {
    Print("RVWinMgr interactive FAIL (Gr)\n");
    return 1;
  }
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
  // Paint proof first (CI), then bring up virtio-input.
  Print("RVWinMgr interactive hash=0x%08X present=%d backend=%d term=%d home=%d put=%d border=%d\n", h, rv_fb.present_ok, rv_fb.backend, rv_winmgr.term_idx, rv_winmgr.home_idx, DocPut() != NULL, DocBorder() != NULL);
  RVWinMgrInputInit;
  Print("RVWinMgr interactive input_ok=%d\n", rv_winmgr.input_ok);
  hold = 0;
#ifdef RV_WIN_HOLD
  hold = 1;
#endif
  // Stress: typing, wrap, cursor save-under, refresh (headless trap guard).
  
  {
    I64 si, sj;
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
  h = RVFbHash() & 0xFFFFFFFF;
  Print("RVWinMgr interactive DONE hash=0x%08X input_ok=%d events=%d iters=%d quit=%d\n", h, rv_winmgr.input_ok, rv_winmgr.input_events, rv_winmgr_task_iters, rv_winmgr.want_quit);
  return 0;
}
