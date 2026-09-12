// Soft tip rung D of the stock DocInit_RV Soft Cmp bisect ladder.
// The stock tail the guest DocInit_RV variant trims: full dft_de_flags plant,
// &= ~DOCG_BL_IV_UL loop, Bt/Bts type_flags_form loop, the 19-term and 15-term
// 1 << X | ... chains, and the clean_scan_codes Bts run. Rung E adds only the
// #help_index directive and the $LK DolDoc comment on top of this.
#include "A:/Compiler/DolDocDefines.HC"
#define DHT_DOC_CMD 1
import U8 *MemSet(U8 *dst, I64 dat, I64 size);
import Bool Bt(U8 *bf, I64 n);
import Bool Bts(U8 *bf, I64 n);
import I64 HashFind(U8 *needle, I64 table, I64 mask);
U0 DocInitRungD()
{
  I64 i;
  MemSet(doldoc.dft_de_flags, 0, sizeof(doldoc.dft_de_flags));
  MemSet(doldoc.dft_type_flags, 0, sizeof(doldoc.dft_type_flags));
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

public I64 RVDocInitRungDSelfTest()
{
  DocInitRungD;
  if (doldoc.dft_de_flags[DOCT_TEXT] != DOCEF_TAG)
    return 2;
  if (!doldoc.type_flags_data[0])
    return 3;
  if (!doldoc.clean_scan_codes[0])
    return 4;
  return 1;
}
