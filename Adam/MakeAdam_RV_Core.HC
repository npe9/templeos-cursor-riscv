// MakeAdam_RV_Core.HC — runnable Adam bring-up core for RISC-V StartOS.
// TempleOS MakeAdam.HC order (for guest ExeFile once A:/Adam is staged):
//   AExts AMath Training AMem TaskRep AMathODE Gr/MakeGr ASnd ABlkDev
//   Menu Win WinMgr ADbg GodExt DolDoc/MakeDoc Ctrls InFile ARegistry …
// Call AdamRVCoreInit from StartOS_RV / RVPhase3StartOS after RedSea is mounted.
#ifndef MAKEADAM_RV_CORE_HC
#define MAKEADAM_RV_CORE_HC
U0 AdamRVCoreInit()
{
  U8 *src;
  DirMk("A:/Adam");
  DirMk("A:/Adam/DolDoc");
  FileWrite("A:/Adam/READY.TXT", "Adam", 4);
  FileWrite("A:/Adam/CORE.TXT", "MakeAdam_RV_Core", 16);
  src = "$$ETempleOS/RISC-V  $$FAdam  $$BMakeAdam_RV_Core  $$3StartOS_RV  $$ADocTerm-lite";
  FileWrite("A:/Adam/WALLPAPER.TXT", src, StrLen(src));
  src = "$$ETempleOS/RISC-V Adam\n" "$$FMakeAdam_RV_Core on FB WinMgr\n" "$$FG,11$$Guest Cmp MakeOS$$FG,7$$  $$3StartOS_RV\n" "$$TX,\"A:/Adam/HOME.DD\"$$\n" "$$AA:/Adam  $$7A:/MakeOS  $$BA:/Compiler\n";
  FileWrite("A:/Adam/HOME.DD", src, StrLen(src));
}
#endif
