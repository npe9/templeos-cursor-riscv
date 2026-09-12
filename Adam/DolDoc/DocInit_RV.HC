// DocInit_RV.HC -- stock Adam/DolDoc/DocInit.HC minus CmpCtrl dft-flag seed Lex.
//
// Libs-first: DefineLstLoad + HashLstAdd -> doldoc.hash (DHT_DOC_CMD /
// DHT_DOC_FLAG / DHT_COLOR) so RVDocPrsDollarCmd HashFind matches stock
// PrsDollarCmd IDENT lookup. Default de/type flags are hand-planted from the
// same CmpCtrl seed string in DocInit.HC (TX+T;DA+P+...;HC+T) -- no Lex.
// Soft tip +docinitseed: RVDocInitSeedApply (HashFind+RVDocPrsFlagsCmp) must
// match this hand plant (Kernel/RVDoc.HC). Do not call SeedApply from here --
// OPTf_EXTERNS_TO_IMPORTS + split-AOT GOT was null (win mcause=5 mtval=0).
//
// Prefer HashLstAdd(Define data) over HashDefineLstAdd: the latter lived in
// KHashB and historically compiled before KHashRV HashFind (empty doldoc.hash,
// DemoInPage lex=0). Direct HashFind+HashLstAdd is SoT on RV.
//
// Runtime TX flags (+CX): Kernel/RVDoc.HC RVDocPrsFlagsCmp (HashFind).
// Soft +docflaglex: CmpCtrl PrsDocFlags via planted abs fps (RVDocPrsFlagsLex).
// Soft +doccmdlex: CmpCtrl one-cmd PrsDollarCmd (IDENT+flags+TK_STR).
// Soft +docarglex: CmpCtrl one LexExpressionI64 arg (BT,LE=1 / DA,LEN=8;
// literal fast-path via RVCmpCtrlAddrsGet). Soft +docextstr: LexExtStr T=/LM=
// (TX,T="hi" / MA,LM="Cd;" via addrs[4]). Soft +docmultilex: multi-arg
// TX+CX,T= / LK A=+HTML=+BI=. Soft +docplaininc/+makedocinc/+docinitinc+docinitu0+docinitbody+docinitdefines+docinitmemset+docinitbts+docinitdefload+docinithashfind+docinithashtablenew+docinitdeflstload+docinithashlstadd+docinithash+docinitkernhash+docinitkernhashfind+glblvaridx+varrmw+formembrmw:
// guest DocInit Soft tip: Soft #include DolDocDefines + Soft CDocInitSoftGlbls g_doldoc +
// MemSet/Bts/DefineLoad + stock HashFind(Fs->hash_table) FM_PICK_* guard (Soft AOT
// sees _intern Fs via RVCmpWireAsmHash→asm_hash plant). Soft HashTableNew /
// DefineLstLoad / HashLstAdd Soft Cmp+Call early (+docinithashtablenew+docinitdeflstload+docinithashlstadd;
// Soft export HashLstAdd; Soft Call HashLstAdd return-count Soft tip; before Fs remat Soft Call). Soft
// g_doldoc.hash Soft Cmp+Call early (+docinithash; Soft Call HashLstAdd return-count Soft tip —
// Soft Call HashFind remat Soft glbl.hash Soft-fail r=3). Kernel doldoc.hash Soft Cmp+Call early
// (+docinitkernhash; Soft Call RVDocDolDocHashGet after host DocInit; no Soft Call Load Soft doldoc).
// Soft Call HashFind remat into Soft ht after Soft CALL_IMPORT (+docinitkernhashfind) Soft Cmp-only.
// Soft glbl != Kernel doldoc. Soft Call
// Soft tip Soft #include unmodified stock DocInit_RV.HC (bare Kernel doldoc into Soft
// asm_hash via RVExePubInternDolDocIn). Soft Call DocInitInc Soft tip Soft Call DocInit
// (+docinitinc; Soft #include guest DocInit_RV Soft Call MemSet/Bts/DefineLoad/HashFind+Fs Soft
// g_doldoc). Soft tip Soft #include stock Soft Call Soft tip (+docinitstock). Soft Call
// HashFind remat KernHashFind / Soft g_doldoc.hash still open (r=3). Full MakeDoc G8. When green,
// replace this file with `#include "DocInit"` from MakeDoc.
#help_index "DolDoc/RV"
U0 DocInit()
{
  //$LK-UL,"CMD Defines",A="MN:DOCT_TEXT"$ -- RV hash warm; no CmpCtrl.
  I64 i;
  CHashDefineStr *tmph;
  // Idempotent warm path FIRST (before any Fs->hash_table HashFind). Soft Call
  // remat Soft tips can leave Fs->hash_table Soft-CALL-hostile; walking it from
  // LiteInit→DocInit hung WinMgr lite Soft Call after stock DocTermNew Soft Call
  // OK. doldoc.hash TX probe stays host-safe when DocInit already warmed once.
  if (doldoc.hash && HashFind("TX", doldoc.hash, DHT_DOC_CMD))
    return;
  // ExePutS PopUp FileMgr(FM_PICK_*) -- plant on cold warm only (first DocInit).
  if (Fs && Fs->hash_table) {
    if (!HashFind("FM_PICK_FILE", Fs->hash_table, HTT_DEFINE_STR))
      DefineLoad("FM_PICK_FILE", "1");
    if (!HashFind("FM_PICK_DIR", Fs->hash_table, HTT_DEFINE_STR))
      DefineLoad("FM_PICK_DIR", "2");
  }
  if (!HashFind("ST_DOC_CMDS", Fs->hash_table, HTT_DEFINE_STR))
    DefineLstLoad("ST_DOC_CMDS", "TX\0CR\0SR\0TB\0PB\0CU\0MK\0PT\0CL\0PL\0LM\0RM\0HD\0FO\0ID\0FG\0" "BG\0FD\0BD\0WW\0HL\0BK\0IV\0UL\0SX\0SY\0CM\0AN\0LK\0BT\0" "DA\0CB\0LS\0MA\0MU\0HX\0TR\0SP\0IB\0IS\0SO\0HC\0ER\0");
  if (!HashFind("ST_DOC_FLAGS", Fs->hash_table, HTT_DEFINE_STR))
    DefineLstLoad("ST_DOC_FLAGS", "T\0LEN\0A\0D\0HTML\0LE\0LM\0RE\0RM\0BI\0BP\0RT\0SX\0SY\0SCX\0U\0" "LC\0LIS\0RC\0RIS\0LX\0CX\0RX\0TY\0CY\0BY\0" "HL\0WW\0BK\0IV\0SEL\0UL\0" "TC\0PRY\0MRX\0WR\0L\0X\0Q\0FST\0B\0S\0BD\0C\0CA\0RD\0UD\0P\0M\0" "TRM\0Z\0H\0TR\0LS\0SK\0PU\0SIF\0FS\0NC\0DD\0DL\0DRT\0");
  if (!HashFind("ST_LINK_TYPES", Fs->hash_table, HTT_DEFINE_STR))
    DefineLstLoad("ST_LINK_TYPES", "FI\0FA\0FF\0FL\0MN\0PI\0PF\0PL\0BF\0DN\0HI\0AD\0AI\0AA\0AF\0AL\0");
  if (!doldoc.hash) {
    doldoc.hash = HashTableNew(512);
    if (!doldoc.hash)
      return;
  }
  if (tmph = HashFind("ST_DOC_CMDS", Fs->hash_table, HTT_DEFINE_STR))
    HashLstAdd(tmph->data, DHT_DOC_CMD, doldoc.hash);
  if (tmph = HashFind("ST_DOC_FLAGS", Fs->hash_table, HTT_DEFINE_STR))
    HashLstAdd(tmph->data, DHT_DOC_FLAG, doldoc.hash);
  if (tmph = HashFind("ST_COLORS", Fs->hash_table, HTT_DEFINE_STR))
    HashLstAdd(tmph->data, DHT_COLOR, doldoc.hash);
  MemSet(doldoc.dft_de_flags, 0, sizeof(doldoc.dft_de_flags));
  MemSet(doldoc.dft_type_flags, 0, sizeof(doldoc.dft_type_flags));
  // Hand plant of DocInit.HC CmpCtrl seed (Soft Call SeedApply must match).
  doldoc.dft_de_flags[DOCT_TEXT] = DOCEF_TAG;
  doldoc.dft_de_flags[DOCT_DATA] = DOCEF_DEREF_DATA | DOCEF_HAS_TERMINATOR | DOCEF_TAG | DOCEF_DFT_LEN | DOCEF_DFT_RAW_TYPE;
  doldoc.dft_de_flags[DOCT_CURSOR_MOVEMENT] = DOCEF_LEFT_EXP | DOCEF_RIGHT_EXP;
  doldoc.dft_de_flags[DOCT_ANCHOR] = DOCEF_TAG;
  doldoc.dft_de_flags[DOCT_LINK] = DOCEF_LINK | DOCEF_UNDERLINE | DOCEF_TAG;
  doldoc.dft_type_flags[DOCT_LINK] = DOCET_UNDERLINE;
  doldoc.dft_de_flags[DOCT_MACRO] = DOCEF_ESC | DOCEF_UNDERLINE | DOCEF_TAG;
  doldoc.dft_type_flags[DOCT_MACRO] = DOCET_UNDERLINE;
  doldoc.dft_de_flags[DOCT_MENU_VAL] = DOCEF_ESC | DOCEF_UNDERLINE | DOCEF_TAG;
  doldoc.dft_type_flags[DOCT_MENU_VAL] = DOCET_UNDERLINE;
  doldoc.dft_de_flags[DOCT_BTTN] = DOCEF_ESC | DOCEF_HAS_BORDER | DOCEF_TAG;
  doldoc.dft_de_flags[DOCT_CHECK_BOX] = DOCEF_CHECK_COLLAPSABLE | DOCEF_DEREF_DATA | DOCEF_TAG | DOCEF_DFT_RAW_TYPE;
  doldoc.dft_de_flags[DOCT_LST] = DOCEF_LST | DOCEF_DEREF_DATA | DOCEF_TAG | DOCEF_DFT_RAW_TYPE;
  doldoc.dft_de_flags[DOCT_HEX_ED] = DOCEF_DEREF_DATA | DOCEF_ZERO_BASED;
  doldoc.dft_de_flags[DOCT_TREE] = DOCEF_TREE | DOCEF_CHECKED_COLLAPSED | DOCEF_CHECK_COLLAPSABLE | DOCEF_UNDERLINE | DOCEF_TAG;
  doldoc.dft_type_flags[DOCT_TREE] = DOCET_UNDERLINE;
  doldoc.dft_de_flags[DOCT_SPRITE] = DOCEF_TAG;
  doldoc.dft_de_flags[DOCT_INS_BIN] = DOCEF_TAG;
  doldoc.dft_de_flags[DOCT_INS_BIN_SIZE] = DOCEF_TAG;
  doldoc.dft_de_flags[DOCT_SONG] = DOCEF_TAG;
  doldoc.dft_de_flags[DOCT_HTML_CODE] = DOCEF_TAG;
  for (i = 0; i < DOCT_TYPES_NUM; i++)
    doldoc.dft_de_flags[i] &= ~DOCG_BL_IV_UL;
  doldoc.type_flags_form[0] = 0;
  for (i = 0; i < DOCT_TYPES_NUM; i++)
    if (Bt(&doldoc.dft_de_flags[i], DOCEf_TAG) && i != DOCT_TEXT || i == DOCT_HEX_ED)
      Bts(doldoc.type_flags_form, i);
  doldoc.type_flags_nontag_invis[0] = 1 << DOCT_PMT | 1 << DOCT_PAGE_LEN | 1 << DOCT_LEFT_MARGIN | 1 << DOCT_RIGHT_MARGIN | 1 << DOCT_HEADER | 1 << DOCT_FOOTER | 1 << DOCT_INDENT | 1 << DOCT_FOREGROUND | 1 << DOCT_BACKGROUND | 1 << DOCT_DFT_FOREGROUND | 1 << DOCT_DFT_BACKGROUND | 1 << DOCT_WORD_WRAP | 1 << DOCT_HIGHLIGHT | 1 << DOCT_BLINK | 1 << DOCT_INVERT | 1 << DOCT_UNDERLINE | 1 << DOCT_SHIFTED_X | 1 << DOCT_SHIFTED_Y | 1 << DOCT_SPRITE;
  doldoc.type_flags_data[0] = 1 << DOCT_DATA | 1 << DOCT_HEX_ED | 1 << DOCT_CHECK_BOX;
  doldoc.type_flags_chk_dup[0] = 1 << DOCT_LEFT_MARGIN | 1 << DOCT_RIGHT_MARGIN | 1 << DOCT_HEADER | 1 << DOCT_FOOTER | 1 << DOCT_FOREGROUND | 1 << DOCT_BACKGROUND | 1 << DOCT_DFT_FOREGROUND | 1 << DOCT_DFT_BACKGROUND | 1 << DOCT_WORD_WRAP | 1 << DOCT_HIGHLIGHT | 1 << DOCT_BLINK | 1 << DOCT_INVERT | 1 << DOCT_UNDERLINE | 1 << DOCT_SHIFTED_X | 1 << DOCT_SHIFTED_Y;
  Bts(doldoc.clean_scan_codes, SC_CURSOR_RIGHT);
  Bts(doldoc.clean_scan_codes, SC_CURSOR_LEFT);
  Bts(doldoc.clean_scan_codes, SC_CURSOR_UP);
  Bts(doldoc.clean_scan_codes, SC_CURSOR_DOWN);
  Bts(doldoc.clean_scan_codes, SC_PAGE_UP);
  Bts(doldoc.clean_scan_codes, SC_PAGE_DOWN);
  Bts(doldoc.clean_scan_codes, SC_ALT);
  Bts(doldoc.clean_scan_codes, SC_CTRL);
  Bts(doldoc.clean_scan_codes, SC_SHIFT);
  Bts(doldoc.clean_scan_codes, SC_CAPS);
  Bts(doldoc.clean_scan_codes, SC_NUM);
  Bts(doldoc.clean_scan_codes, SC_SCROLL);
  Bts(doldoc.clean_scan_codes, SC_HOME);
  Bts(doldoc.clean_scan_codes, SC_END);
  Bts(doldoc.clean_scan_codes, SC_GUI);
  Bts(doldoc.clean_scan_codes, SC_BACKSPACE);
}
