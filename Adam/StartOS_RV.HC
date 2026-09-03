// StartOS_RV.HC — RISC-V StartOS body (TempleOS StartOS.HC role).
//
// x86 StartOS: #include MakeAdam; DocTermNew; Spawn(WinMgrTask); WallPaperInit; MakeHome.
// RV path (P4 DocTerm):
//   1. MakeAdam_RV_Core markers on A: (READY/HOME.DD)
//   2. DocTermNew → Term + Put/Display/Border docs on RVWinMgr
//   3. RVDocHomeOpen loads A:/Adam/HOME.DD (WALLPAPER.TXT for status line)
//   4. Marks RLf_WINMGR; interactive hold path Spawns WinMgrTask via RVWinMgrSpawn
// Full DolDoc entry lists / ODE still open once guest Cmp + DolDoc land.
#include "/Adam/MakeAdam_RV_Core.HC"
public I64 StartOSProbe()
{
  return 1;
}

public U0 StartOS()
{
  U8 *wp;
  I64 sz = 0;
  AdamRVCoreInit;
  if (rv_winmgr.ready) {
    wp = FileRead("A:/Adam/WALLPAPER.TXT", &sz, NULL);
    if (wp && sz > 0)
      RVWinSetWallpaper(wp);
    else
      RVWinSetWallpaper("TempleOS/RISC-V  StartOS + DocTerm");
    if (rv_winmgr.n_wins <= 0) {
      // No prior demo desktop — create Adam chrome, then Term + HOME.DD.
      RVWinNew(2, 36, 2, 12, "Adam", "$$ETempleOS/RISC-V StartOS\n" "$$FMakeAdam_RV_Core markers on A:\n" "$$ADocTermNew + HOME.DD on FB\n", FALSE);
    } else {
      RVWinSetTitle(0, "Adam");
      RVWinSetBody(0, "$$ETempleOS/RISC-V StartOS\n" "$$FMakeAdam_RV_Core markers on A:\n" "$$BTab / click focus  $$3type into Term\n" "$$AA:/Adam/HOME.DD  $$7READY.TXT\n" "> Dir(\"A:/Adam\");\n" "> Ed(\"A:/Adam/HOME.DD\");\n");
    }
    DocTermNew;
    RVDocHomeOpen(NULL);
    RVDocPutS("StartOS ready\n");
    // Smokes must not Spawn(WinMgrTask): that loops until ESC. Mark authority on Adam;
    // `make kernel-win-run` Spawns via RVWinMgrSpawn after the UART proof line.
    LBts(&sys_run_level, RLf_WINMGR);
    if (!sys_winmgr_task)
      sys_winmgr_task = Fs;
    RVWinMgrRefresh;
  }
  Print("StartOS: DocTerm ready=%d wins=%d term=%d home=%d put=%d wm=%d\n", rv_winmgr.ready, rv_winmgr.n_wins, rv_winmgr.term_idx, rv_winmgr.home_idx, DocPut() != NULL, sys_winmgr_task != NULL);
}
