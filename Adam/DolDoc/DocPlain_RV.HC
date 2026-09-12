// DocPlain_RV.HC -- stock PrsDocFlagSingle toward PrsDollarCmd (G8).
//
// Flag HashFind body lives in Kernel/RVDoc.HC (RVDocPrsFlagsCmp) so Win
// split-AOT does not call through a null forward GOT (DemoInPage TX+CX was
// mcause=5 mtval=0). Arg KEY= quote/int is RVDocPrsArgOnce in the same unit
// (Soft tips: RVDocPrsArgTagProbe T=/HTML=; RVDocPrsArgExtraProbe LE=/LM=/A=/BI=).
// DocInit seed Soft tip: RVDocInitSeedProbe (+docinitseed).
// CmpCtrl PrsDocFlags Soft tip: RVDocPrsFlagsLexProbe (+docflaglex) -- abs-addr
// CmpCtrl Lex + DHT_DOC_FLAG HashFind (planted fps; not Kernel GOT).
// CmpCtrl one-cmd PrsDollarCmd Soft tip: RVDocPrsDollarCmdLexProbe (+doccmdlex)
// -- IDENT+flags+TK_STR via same abs fps.
// CmpCtrl one LexExpressionI64 arg Soft tip: RVDocPrsDollarCmdLexArgProbe
// (+docarglex) -- BT,LE=1 / DA,LEN=8 via RVCmpCtrlAddrsGet LexExpressionI64.
// CmpCtrl LexExtStr Soft tip: RVDocPrsDollarCmdLexExtProbe (+docextstr) --
// TX,T="hi" / MA,LM="Cd;" via RVCmpCtrlAddrsGet[4].
// CmpCtrl multi-arg PrsDollarCmd Soft tip: RVDocPrsDollarCmdLexMultiProbe
// (+docmultilex) -- TX+CX,T="hi" / LK multi A=/HTML=/BI= via abs fps[0..4].
// Product DocPrint Soft tip: RVDocPrintFlagsSoft (+docprintflags) -- DocPrint
// TX+CX -> CENTER_X + DocRecalc (UART; beyond flag/arg Soft).
// Stock DocEd Soft tip: RVDocEdSoft (+doced) -- DOCF_FORM inject Tab/Enter BT LE
// + DocMenu MU LE (UART; no FB).
// This file keeps MakeDoc_RV include + probe alias.
//
// Soft +docplaininc/+makedocinc/+docinitinc+docinitu0+docinitbody+glblvaridx+varrmw+formembrmw:
// late Soft Call SelfTest->local->IMPORT OK (guest import DocPlain; Soft DocInit =
// local DOCT_* #defines + Soft CDocInitSoftGlbls + for(i) member[i]=member[i]&~mask). Stock
// DocInit_RV / full MakeDoc Adam/DolDoc/* still G8 (KernelA defines plant).
#ifndef DOC_PLAIN_RV_HC
#define DOC_PLAIN_RV_HC
#help_index "DolDoc/RV"
extern I64 RVDocPrsFlagsProbe();
extern I64 RVDocPrsArgTagProbe();
extern I64 RVDocPrsArgExtraProbe();
extern I64 RVDocInitSeedProbe();
extern I64 RVDocPrsFlagsLexProbe();
extern I64 RVDocPrsDollarCmdLexProbe();
extern I64 RVDocPrsDollarCmdLexArgProbe();
extern I64 RVDocPrsDollarCmdLexExtProbe();
extern I64 RVDocPrsDollarCmdLexMultiProbe();
extern I64 RVDocPrintFlagsSoft();
extern I64 RVDocEdSoft();
// Alias for MakeDoc / Soft Call discoverability (body in RVDoc).
public I64 DocPlainRVProbe()
{
  return RVDocPrsFlagsProbe;
}
#endif
