// StartOS_RV.HC — RISC-V StartOS body (TempleOS StartOS.HC role).
// P3 intermediate: guest Cmp → A:/Adam/StartOS.BIN; StartOS Loads that BIN
// (see RVPhase3GuestRuntime / RVPhase3StartOS). Host-linked AdamRVCoreInit
// remains for Adam markers / WinMgr until Adam.BIN absorbs that surface.
// x86 StartOS: #include MakeAdam; DocTermNew; Spawn(WinMgrTask); WallPaperInit; MakeHome.
public I64 StartOSProbe()
{
  return 1;
}
