#include "A:/Adam/DolDoc/DolDocDefines.HC"
#define HTT_DEFINE_STR 0x4
import U8 *MemSet(U8 *dst, I64 dat, I64 size);
import Bool Bt(U8 *bf, I64 n);
import Bool Bts(U8 *bf, I64 n);
import I64 DefineLoad(U8 *dname, U8 *st);
import I64 HashFind(U8 *needle, I64 table, I64 mask);
class CDocInitSoftGlbls
{
  I64 hash;
  I64 dft_de_flags[43];
  I64 type_flags_nontag_invis[1];
  I64 type_flags_form[1];
  I64 type_flags_data[1];
  I64 type_flags_chk_dup[1];
  I64 clean_scan_codes[4];
  I32 dft_type_flags[43];
};
CDocInitSoftGlbls g_doldoc;
U0 DocInit()
{
  I64 i;
  // Stock DocInit_RV FM_PICK_* guard via Soft Fs->hash_table (asm_hash plant).
  if (Fs && Fs->hash_table) {
    if (!HashFind("FM_PICK_FILE", Fs->hash_table, HTT_DEFINE_STR))
      DefineLoad("FM_PICK_FILE", "1");
    if (!HashFind("FM_PICK_DIR", Fs->hash_table, HTT_DEFINE_STR))
      DefineLoad("FM_PICK_DIR", "2");
  }
  MemSet(g_doldoc.dft_de_flags, 0, sizeof(g_doldoc.dft_de_flags));
  MemSet(g_doldoc.dft_type_flags, 0, sizeof(g_doldoc.dft_type_flags));
  g_doldoc.dft_de_flags[DOCT_TEXT] = DOCEF_TAG;
  g_doldoc.dft_de_flags[DOCT_DATA] = DOCEF_DEREF_DATA | DOCEF_HAS_TERMINATOR | DOCEF_TAG | DOCEF_DFT_LEN | DOCEF_DFT_RAW_TYPE;
  g_doldoc.dft_de_flags[DOCT_CURSOR_MOVEMENT] = DOCEF_LEFT_EXP | DOCEF_RIGHT_EXP;
  g_doldoc.dft_de_flags[DOCT_ANCHOR] = DOCEF_TAG;
  g_doldoc.dft_de_flags[DOCT_LINK] = DOCEF_LINK | DOCEF_UNDERLINE | DOCEF_TAG;
  g_doldoc.dft_type_flags[DOCT_LINK] = DOCET_UNDERLINE;
  g_doldoc.dft_de_flags[DOCT_MACRO] = DOCEF_ESC | DOCEF_UNDERLINE | DOCEF_TAG;
  g_doldoc.dft_type_flags[DOCT_MACRO] = DOCET_UNDERLINE;
  g_doldoc.dft_de_flags[DOCT_MENU_VAL] = DOCEF_ESC | DOCEF_UNDERLINE | DOCEF_TAG;
  g_doldoc.dft_type_flags[DOCT_MENU_VAL] = DOCET_UNDERLINE;
  g_doldoc.dft_de_flags[DOCT_BTTN] = DOCEF_ESC | DOCEF_HAS_BORDER | DOCEF_TAG;
  g_doldoc.dft_de_flags[DOCT_CHECK_BOX] = DOCEF_CHECK_COLLAPSABLE | DOCEF_DEREF_DATA | DOCEF_TAG | DOCEF_DFT_RAW_TYPE;
  g_doldoc.dft_de_flags[DOCT_LST] = DOCEF_LST | DOCEF_DEREF_DATA | DOCEF_TAG | DOCEF_DFT_RAW_TYPE;
  g_doldoc.dft_de_flags[DOCT_HEX_ED] = DOCEF_DEREF_DATA | DOCEF_ZERO_BASED;
  g_doldoc.dft_de_flags[DOCT_TREE] = DOCEF_TREE | DOCEF_CHECKED_COLLAPSED | DOCEF_CHECK_COLLAPSABLE | DOCEF_UNDERLINE | DOCEF_TAG;
  g_doldoc.dft_type_flags[DOCT_TREE] = DOCET_UNDERLINE;
  g_doldoc.dft_de_flags[DOCT_SPRITE] = DOCEF_TAG;
  g_doldoc.dft_de_flags[DOCT_INS_BIN] = DOCEF_TAG;
  g_doldoc.dft_de_flags[DOCT_INS_BIN_SIZE] = DOCEF_TAG;
  g_doldoc.dft_de_flags[DOCT_SONG] = DOCEF_TAG;
  g_doldoc.dft_de_flags[DOCT_HTML_CODE] = DOCEF_TAG;
  for (i = 0; i < DOCT_TYPES_NUM; i++)
    g_doldoc.dft_de_flags[i] &= ~DOCG_BL_IV_UL;
  g_doldoc.type_flags_form[0] = 0;
  for (i = 0; i < DOCT_TYPES_NUM; i++)
    if (Bt(&g_doldoc.dft_de_flags[i], DOCEf_TAG) && i != DOCT_TEXT || i == DOCT_HEX_ED)
      Bts(g_doldoc.type_flags_form, i);
  g_doldoc.type_flags_nontag_invis[0] = 1 << DOCT_PMT | 1 << DOCT_PAGE_LEN | 1 << DOCT_LEFT_MARGIN | 1 << DOCT_RIGHT_MARGIN | 1 << DOCT_HEADER | 1 << DOCT_FOOTER | 1 << DOCT_INDENT | 1 << DOCT_FOREGROUND | 1 << DOCT_BACKGROUND | 1 << DOCT_DFT_FOREGROUND | 1 << DOCT_DFT_BACKGROUND | 1 << DOCT_WORD_WRAP | 1 << DOCT_HIGHLIGHT | 1 << DOCT_BLINK | 1 << DOCT_INVERT | 1 << DOCT_UNDERLINE | 1 << DOCT_SHIFTED_X | 1 << DOCT_SHIFTED_Y | 1 << DOCT_SPRITE;
  g_doldoc.type_flags_data[0] = 1 << DOCT_DATA | 1 << DOCT_HEX_ED | 1 << DOCT_CHECK_BOX;
  g_doldoc.type_flags_chk_dup[0] = 1 << DOCT_LEFT_MARGIN | 1 << DOCT_RIGHT_MARGIN | 1 << DOCT_HEADER | 1 << DOCT_FOOTER | 1 << DOCT_FOREGROUND | 1 << DOCT_BACKGROUND | 1 << DOCT_DFT_FOREGROUND | 1 << DOCT_DFT_BACKGROUND | 1 << DOCT_WORD_WRAP | 1 << DOCT_HIGHLIGHT | 1 << DOCT_BLINK | 1 << DOCT_INVERT | 1 << DOCT_UNDERLINE | 1 << DOCT_SHIFTED_X | 1 << DOCT_SHIFTED_Y;
  Bts(g_doldoc.clean_scan_codes, SC_CURSOR_RIGHT);
  Bts(g_doldoc.clean_scan_codes, SC_CURSOR_LEFT);
  Bts(g_doldoc.clean_scan_codes, SC_CURSOR_UP);
  Bts(g_doldoc.clean_scan_codes, SC_CURSOR_DOWN);
  Bts(g_doldoc.clean_scan_codes, SC_PAGE_UP);
  Bts(g_doldoc.clean_scan_codes, SC_PAGE_DOWN);
  Bts(g_doldoc.clean_scan_codes, SC_ALT);
  Bts(g_doldoc.clean_scan_codes, SC_CTRL);
  Bts(g_doldoc.clean_scan_codes, SC_SHIFT);
  Bts(g_doldoc.clean_scan_codes, SC_CAPS);
  Bts(g_doldoc.clean_scan_codes, SC_NUM);
  Bts(g_doldoc.clean_scan_codes, SC_SCROLL);
  Bts(g_doldoc.clean_scan_codes, SC_HOME);
  Bts(g_doldoc.clean_scan_codes, SC_END);
  Bts(g_doldoc.clean_scan_codes, SC_GUI);
  Bts(g_doldoc.clean_scan_codes, SC_BACKSPACE);
}

public I64 DocInitRVProbe()
{
  // Soft Call DocInitInc Soft tip: DocInit planted Soft g_doldoc flags.
  if (g_doldoc.dft_de_flags[DOCT_TEXT] != DOCEF_TAG)
    return 0;
  return 1;
}
