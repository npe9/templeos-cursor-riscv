// DocInit_RV.HC — stock Adam/DolDoc/DocInit.HC minus CmpCtrl PrsDocFlags.
//
// Libs-first: DefineLstLoad + HashLstAdd → doldoc.hash (DHT_DOC_CMD /
// DHT_DOC_FLAG / DHT_COLOR) so RVDocPrsDollarCmd HashFind matches stock
// PrsDollarCmd IDENT lookup. Default de/type flags are hand-planted from the
// same CmpCtrl seed string in DocInit.HC (TX+T;DA+P+…;HC+T) — no Lex.
//
// Prefer HashLstAdd(Define data) over HashDefineLstAdd: the latter lived in
// KHashB and historically compiled before KHashRV HashFind (empty doldoc.hash,
// DemoInPage lex=0). Direct HashFind+HashLstAdd is SoT on RV.
//
// Full PrsDocFlags via CmpCtrlNew/Lex remains G8 (Compiler_RV). When that is
// green, replace this file with `#include "DocInit"` from MakeDoc.
#help_index "DolDoc/RV"
U0 DocInit()
{
  //$LK-UL,"CMD Defines",A="MN:DOCT_TEXT"$ — RV hash warm; no CmpCtrl.
  I64 i;
  CHashDefineStr *tmph;
  // Idempotent: already warm if TX resolves (skip empty stale tables).
  if (doldoc.hash && HashFind("TX", doldoc.hash, DHT_DOC_CMD))
    return;
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
  // Hand plant of DocInit.HC CmpCtrl seed (no Lex / PrsDocFlags).
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
