// MakeDoc_RV.HC — thin RV shim toward full Adam/DolDoc/MakeDoc.HC (P2 / P6).
//
// Libs-first path (this file):
//   #include DocInit_RV  → stock DefineLstLoad + doldoc.hash HashDefineLstAdd
//   (no CmpCtrl PrsDocFlags). Hand PrsDollarCmd bodies stay in Kernel/RVDoc.HC
//   until G8 can Lex CmpCtrlNew seed / stock DocPlain PrsDollarCmd.
//
// Do not pull full MakeDoc into Kernel_RV.PRJ yet — DocRecalc/DocPutKey/Lex
// still block guest Cmp. Soft probe: RVDocDemoProbe (DemoInPage + lex hits).
// WS3: DocSpriteBinNew + stock FileMgr DirFileDoc/FilesFind (FileMgr_RV).
//
// Do not call DocInit at include time — host AOT may run top-level before
// Fs/TaskInit. Warm from RVWinMgrInit (before PopUp) + RVDocPrsDollarCmd.
//
// When G8 clears class/StrCpy/U0-import gaps, replace this file with:
//   #include "MakeDoc"
// and drop Kernel/RVDoc.HC from the WinMgr path.
#help_index "DolDoc/RV"
#include "/Adam/DolDoc/DocInit_RV"
public I64 MakeDocRVProbe()
{
  //Thin stand-in for DocInit+MakeDoc load. Real work is RVDocDemoProbe.
  return RVDocDemoProbe();
}
