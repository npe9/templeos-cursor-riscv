// MakeDoc_RV.HC -- thin RV shim toward full Adam/DolDoc/MakeDoc.HC (P2 / P6).
//
// Libs-first path (this file):
//   #include DocInit_RV  -> stock DefineLstLoad + doldoc.hash HashDefineLstAdd
//     + hand-planted dft flags (Soft +docinitseed proves SeedApply == plant)
//   #include DocPlain_RV -> stock PrsDocFlagSingle HashFind (TX+CX); arg T=/HTML=
//     + LE=/LM=/A=/BI= (RVDocPrsArgOnce HashFind; Soft +docarg/+docargx);
//     CmpCtrl PrsDocFlags Soft +docflaglex (RVDocPrsFlagsLexProbe abs fps);
//     CmpCtrl one-cmd PrsDollarCmd Soft +doccmdlex (IDENT+flags+TK_STR);
//     CmpCtrl one LexExpressionI64 Soft +docarglex (BT,LE=1 / DA,LEN=8);
//     CmpCtrl LexExtStr Soft +docextstr (TX,T="hi" / MA,LM="Cd;");
//     CmpCtrl multi-arg Soft +docmultilex (TX+CX,T= / LK A=+HTML=+BI=);
//     product DocPrint Soft +docprintflags (TX+CX + DocRecalc);
//     stock DocEd Soft +doced (inject Tab/Enter BT LE + DocMenu MU)
//   Soft +docplaininc/+makedocinc: guest Cmp #include + late Soft Call nest OK.
//   Soft +docplainnest/+makedocnest/+makedocrel: RedSea nested A:/Adam/DolDoc/*
//     MakeDoc_RV nest seed = relative `#include DocPlain_RV` only (Soft Lex joins
//     relatives to including file dir). Soft `import Cd` + Soft `#define __DIR__`
//     Soft Cmp Invalid lval vs KernelA `__DIR__` `#exe{StreamDir}` — omit. Soft
//     DocInitInc Soft Cmp covers Soft Fs DocInit. Soft Cmp+Call OK. Soft AOT
//     Cd(__DIR__) still Invalid lval; SoftExeDir plant hung DocEd Soft Call —
//     do not plant. Full product DolDoc set still open.
//     Hand PrsDollarCmd bodies stay in Kernel/RVDoc.HC until full guest
//     MakeDoc #include Adam/DolDoc/* lands.
//
// Do not pull full MakeDoc into Kernel_RV.PRJ yet -- DocRecalc/DocPutKey/Lex
// still block guest Cmp. Soft probe: RVDocDemoProbe (DemoInPage + lex/flag).
// WS3: DocSpriteBinNew + stock FileMgr DirFileDoc/FilesFind (FileMgr_RV).
//
// Do not call DocInit at include time -- host AOT may run top-level before
// Fs/TaskInit. Warm from RVWinMgrInit (before PopUp) + RVDocPrsDollarCmd.
//
// When G8 clears class/StrCpy/U0-import gaps, replace this file with:
//   #include "MakeDoc"
// and drop Kernel/RVDoc.HC from the WinMgr path.
#help_index "DolDoc/RV"
#include "/Adam/DolDoc/DocInit_RV"
#include "/Adam/DolDoc/DocPlain_RV"
public I64 MakeDocRVProbe()
{
  //Thin stand-in for DocInit+MakeDoc load. Real work is RVDocDemoProbe.
  return RVDocDemoProbe();
}
