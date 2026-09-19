// RVDoc.HC — Phase P2 DolDoc core for RISC-V WinMgr.
//
// Real CDoc entry stream subset (not the full Adam/DolDoc ~28-file stack):
//   DocNew / DocRst / DocInsEntry / DocEntryDel / DocDel
//   DocPutS / DocLoad / DocPrint (StrPrintJoin+DocPutS; stock DocPutS.HC)
//   DocRecalc (layout + tree collapse SKIP)
//   DocTop / DocLock / DocUnlock (single-task)
//   DocBorderNew (title DA + [X]/MENU widgets; chrome paint still WinMgr)
//   DocSave / DocWrite / DocRead ($$ re-emit + trailing CDocBin blob)
//   DocEdInsChar / DocEdBackspace / DocCaptureUndo / DocUndoRestore
//   DocEd modal (DOCF_FORM + inject/ScanMsg) / DocForm Lex-lite / DocMenu-lite
//   DocBinFind* / DocBinsValidate / DocBinDel (sprite/bin stubs→real queue)
//
// Entry kinds: TEXT, NEW_LINE, TAB, SOFT_NL, PAGE_BREAK, CURSOR, PMT, CLEAR,
// FG/BG, INDENT, BLINK/INVERT/UNDERLINE, LINK, TREE(+U=), TX(+HTML=), BT/DA/CB/MA,
// AN/MU(+U=)/LS/CM/SX/SY/WW/HL/LM/RM/PL, SP/IB (bin-backed DocSprite→Sprite3), HX/SO/HC.
// Soft-skip unknown $$. PrsDollarCmd IDENT: Adam/DolDoc/DocInit_RV doldoc.hash
// HashFind (libs-first; hand bodies SoT). TX+CX → DOCEF_CENTER_X via
// RVDocPrsFlagsCmp (HashFind DHT_DOC_FLAG; body here — DocPlain_RV forward GOT
// was null: mcause=5 ld a0,0(a0)). Arg KEY="..." / KEY=n via RVDocPrsArgOnce
// (same DHT_DOC_FLAG HashFind; quote or int; no CmpCtrl — Lex hung in prior hyps).
// Soft tips: T=/HTML= (+docarg) + LE=/LM=/A=/BI= (+docargx) + DocInit seed
// (+docinitseed) + CmpCtrl PrsDocFlagSingle Lex (+docflaglex: HashFind-planted
// CmpCtrlNew/Lex/CmpCtrlDel abs fps — not Kernel GOT / DocPlain forward GOT) +
// CmpCtrl one-cmd PrsDollarCmd Lex (+doccmdlex: IDENT+flags+TK_STR) +
// CmpCtrl one LexExpressionI64 arg (+docarglex: BT,LE=1 / DA,LEN=8 via
// RVCmpCtrlAddrsGet LexExpressionI64 abs; literal fast-path) + CmpCtrl
// LexExtStr T=/LM= (+docextstr: TX,T="hi" / MA,LM="Cd;" via addrs[4]) +
// CmpCtrl multi-arg PrsDollarCmd (+docmultilex: TX+CX,T= / LK A=+HTML=+BI=) +
// product DocPrint TX+CX (+docprintflags) + DocEd inject/DocMenu (+doced).
// Guest MakeDoc #include Adam/DolDoc/* — still G8.
// DocForm: class-meta when HTT_CLASS+format meta; else Lex-lite DA/CB + DocEd.
// Demo: RVDocDemoOpen embeds Demo/ToHtmlToTXTDemo/DemoInPage.DD (host path).
// FileMgr: stock DirFileDoc/FilesFind via Adam/ABlkDev/FileMgr_RV.HC.
//
// Paint/click hooks live in RVWinMgr (RVDocDrawWin / RVDocClickAt / DocSprites). Forward
// decls only — do not grow RVWinMgr beyond thin integration (P1 owns task bind).
// DocPut / RVDocPutS live in RVWinMgr (included after this file).
CDoc *DocPut(CTask *task = NULL);
U0 RVDocPutS(U8 *st);
Bool RVDocOpenLink(U8 *link);
U0 DocInit();
// body: Adam/DolDoc/DocInit_RV.HC via MakeDoc_RV
#define RV_DOC_ED_KEY_MAX 48
#define RV_DOC_ED_MAX_STEPS 4096
#define DHT_DOC_CMD	1
#define DHT_DOC_FLAG	2
#define DHT_COLOR	4
public class CDolDocGlbls
{
  CHashTable *hash;
  I64 dft_de_flags[DOCT_TYPES_NUM];
  I64 type_flags_nontag_invis[(DOCT_TYPES_NUM + 63) / 64];
  I64 type_flags_form[(DOCT_TYPES_NUM + 63) / 64];
  I64 type_flags_data[(DOCT_TYPES_NUM + 63) / 64];
  I64 type_flags_chk_dup[(DOCT_TYPES_NUM + 63) / 64];
  I64 clean_scan_codes[4];
  I32 dft_type_flags[DOCT_TYPES_NUM];
};
CDolDocGlbls doldoc;
I64 rv_doc_ed_keys[RV_DOC_ED_KEY_MAX];
I64 rv_doc_ed_key_n;
I64 rv_doc_ed_key_i;
I64 rv_doc_ed_modal_hits;
I64 rv_doc_ed_result;
I64 rv_doc_form_lex_hits;
I64 rv_doc_bin_hits;
I64 rv_doc_sprite_paints;
I64 rv_doc_ib_hits;
I64 rv_doc_filemgr_entries;
I64 rv_doc_filemgr_user_hits;
I64 rv_doc_filemgr_ffind;
I64 rv_doc_link_opens;
I64 rv_doc_open_busy;
I64 rv_doc_last_open_idx = -1;
// window opened by the most recent FI: link (auto-focus)
I64 rv_doc_sel_moves;
// cursor link-selection moves (canary for VT link-nav)
I64 rv_doc_html_hits;
I64 rv_doc_hx_hits;
I64 rv_doc_song_hits;
I64 rv_doc_hc_hits;
I64 rv_doc_demo_entries;
I64 rv_doc_prs_lex_hits;
I64 rv_doc_prs_flag_hits;
I64 rv_doc_prs_flag_cmp_ok;
I64 rv_doc_prs_flag_lex_hits;
I64 rv_doc_prs_dollar_lex_hits;
I64 rv_doc_prs_arg_lex_hits;
I64 rv_doc_prs_ext_lex_hits;
I64 rv_doc_prs_multi_lex_hits;
I64 rv_doc_prs_arg_hits;
Bool RVDocCmpFpOk(I64 fp)
{
  //Same gate as Menu_RV RVMenuFpOk — reject NULL / odd / truncated GOT stubs.
  if (!fp)
    return FALSE;
  if (fp & 1)
    return FALSE;
  if (fp < 0x80000000)
    return FALSE;
  return TRUE;
}

Bool RVDocCmpFpsGet(I64 *fp_new, I64 *fp_lex, I64 *fp_del, I64 *fp_lex_i64 = NULL, I64 *fp_lex_ext = NULL)
{
  //Prefer RVCmpCtrlAddrsGet (Compiler-unit abs) when planted; else HashFind
  // CmpCtrlNew/Lex/CmpCtrlDel after RVCmpPlantLoadedCmpFuns.
  // Optional fp_lex_i64: addrs[2] LexExpressionI64 (Menu/Doc arg Soft tips).
  // Optional fp_lex_ext: addrs[4] LexExtStr (Doc T=/LM= Soft tip).
  CHashFun *hf;
  I64 addrs[5];
  I64 (*fp_get)(I64 *out);
  I64 n;
  if (!fp_new || !fp_lex || !fp_del)
    return FALSE;
  *fp_new = 0;
  *fp_lex = 0;
  *fp_del = 0;
  if (fp_lex_i64)
    *fp_lex_i64 = 0;
  if (fp_lex_ext)
    *fp_lex_ext = 0;
  if (hf = HashFind("RVCmpCtrlAddrsGet", Fs->hash_table, HTT_FUN)) {
    if (RVDocCmpFpOk(hf->exe_addr)) {
      fp_get = hf->exe_addr;
      n = fp_get(addrs);
      if (n >= 4 && RVDocCmpFpOk(addrs[0]) && RVDocCmpFpOk(addrs[1]) && RVDocCmpFpOk(addrs[3])) {
        *fp_new = addrs[0];
        *fp_lex = addrs[1];
        *fp_del = addrs[3];
        if (fp_lex_i64) {
          if (!RVDocCmpFpOk(addrs[2]))
            return FALSE;
          *fp_lex_i64 = addrs[2];
        }
        if (fp_lex_ext) {
          if (n < 5 || !RVDocCmpFpOk(addrs[4]))
            return FALSE;
          *fp_lex_ext = addrs[4];
        }
        return TRUE;
      }
    }
  }
  if (!(hf = HashFind("CmpCtrlNew", Fs->hash_table, HTT_FUN)) || !RVDocCmpFpOk(hf->exe_addr))
    return FALSE;
  *fp_new = hf->exe_addr;
  if (!(hf = HashFind("Lex", Fs->hash_table, HTT_FUN)) || !RVDocCmpFpOk(hf->exe_addr))
    return FALSE;
  *fp_lex = hf->exe_addr;
  if (!(hf = HashFind("CmpCtrlDel", Fs->hash_table, HTT_FUN)) || !RVDocCmpFpOk(hf->exe_addr))
    return FALSE;
  *fp_del = hf->exe_addr;
  if (fp_lex_i64) {
    if (!(hf = HashFind("LexExpressionI64", Fs->hash_table, HTT_FUN)) || !RVDocCmpFpOk(hf->exe_addr))
      return FALSE;
    *fp_lex_i64 = hf->exe_addr;
  }
  if (fp_lex_ext) {
    if (!(hf = HashFind("LexExtStr", Fs->hash_table, HTT_FUN)) || !RVDocCmpFpOk(hf->exe_addr))
      return FALSE;
    *fp_lex_ext = hf->exe_addr;
  }
  return TRUE;
}

Bool RVDocPrsFlagsLex(U8 *st, I64 *_de_flags, U32 *_type)
{
  //Stock PrsDocFlags / PrsDocFlagSingle shape (DocPlain.HC) via abs-addr CmpCtrl
  // Lex + DHT_DOC_FLAG HashFind. Body here (not DocPlain_RV) — split-AOT
  // forward GOT was null; Kernel &CmpCtrlNew GOT is unsafe (Menu wire class).
  CCmpCtrl * (*fp_new)(U8 *buf = NULL, I64 flags = 0, U8 *filename = NULL);
  I64 (*fp_lex)(CCmpCtrl *cc);
  U0 (*fp_del)(CCmpCtrl *cc);
  CCmpCtrl *cc;
  CHashGeneric *tmph;
  I64 fp_n, fp_l, fp_d, res, hits;
  Bool turn_on;
  if (!st || !_de_flags || !_type)
    return FALSE;
  if (!doldoc.hash)
    DocInit;
  if (!doldoc.hash)
    return FALSE;
  if (!RVDocCmpFpsGet(&fp_n, &fp_l, &fp_d))
    return FALSE;
  fp_new = fp_n;
  fp_lex = fp_l;
  fp_del = fp_d;
  cc = fp_new(st, CCF_DONT_FREE_BUF, NULL);
  if (!cc)
    return FALSE;
  cc->htc.hash_table_lst = NULL;
  fp_lex(cc);
  hits = 0;
  while (TRUE) {
    if (cc->token == '+')
      turn_on = TRUE;
    else if (cc->token == '-')
      turn_on = FALSE;
    else
      break;
    fp_lex(cc);
    if (cc->token == TK_IDENT && cc->cur_str && (tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_FLAG))) {
      res = tmph->user_data0;
      if (res < 64) {
        BEqu(_de_flags, res, turn_on);
        switch (res) {
          case DOCEf_BLINK :
          case DOCEf_INVERT :
          case DOCEf_UNDERLINE :
          case DOCEf_SEL :
          BEqu(_type, res, turn_on);
          break;
        }
        hits++;
      }
      fp_lex(cc);
    } else
      break;
  }
  fp_del(cc);
  if (hits)
    rv_doc_prs_flag_lex_hits++;
  return hits > 0;
}
Bool RVDocExtractQuoted(U8 **pp, U8 *dst, I64 dst_max);
I64 RVDocParseInt(U8 *s, I64 *out);
Bool RVDocPrsFlagsCmp(U8 *st, I64 *_de_flags, U32 *_type)
{
  //Stock PrsDocFlagSingle shape (DocPlain.HC): +/− IDENT → DHT_DOC_FLAG HashFind.
  // Defined here (not DocPlain_RV extern) — split-AOT forward GOT was null
  // (mcause=5 mtval=0 ld a0,0(a0) on DemoInPage TX+CX).
  U8 *p;
  U8 ident[16];
  I64 n, res, hits;
  Bool turn_on;
  CHashGeneric *tmph;
  if (!st || !_de_flags || !_type)
    return FALSE;
  if (!doldoc.hash)
    DocInit;
  if (!doldoc.hash)
    return FALSE;
  p = st;
  hits = 0;
  while (*p == '+' || *p == '-') {
    turn_on = (*p == '+');
    p++;
    n = 0;
    while (*p && *p != '+' && *p != '-' && *p != ',' && *p != '"' && *p != ' ' && *p != '\t' && n < sizeof(ident) - 1)
      ident[n++] = *p++;
    ident[n] = 0;
    if (!ident[0])
      break;
    if (tmph = HashFind(ident, doldoc.hash, DHT_DOC_FLAG)) {
      res = tmph->user_data0;
      if (res < 64) {
        BEqu(_de_flags, res, turn_on);
        switch (res) {
          case DOCEf_BLINK :
          case DOCEf_INVERT :
          case DOCEf_UNDERLINE :
          case DOCEf_SEL :
          BEqu(_type, res, turn_on);
          break;
        }
        hits++;
      }
    }
  }
  if (hits)
    rv_doc_prs_flag_cmp_ok++;
  return hits > 0;
}

public I64 RVDocPrsFlagsProbe()
{
  //Soft/interactive: stock +CX → DOCEF_CENTER_X (DemoInPage TX+CX).
  I64 de_flags = DOCEF_TAG;
  U32 type = DOCT_TEXT;
  DocInit;
  if (!RVDocPrsFlagsCmp("+CX", &de_flags, &type))
    return 3;
  if (!(de_flags & DOCEF_CENTER_X))
    return 4;
  rv_doc_prs_flag_hits++;
  return 8;
}

public I64 RVDocPrsFlagsLexProbe()
{
  //Soft tip: stock PrsDocFlags +CX via abs-addr CmpCtrl Lex (planted fps).
  I64 de_flags = DOCEF_TAG;
  U32 type = DOCT_TEXT;
  I64 fp_n, fp_l, fp_d;
  DocInit;
  if (!doldoc.hash)
    return 2;
  if (!RVDocCmpFpsGet(&fp_n, &fp_l, &fp_d))
    return 3;
  if (!RVDocPrsFlagsLex("+CX", &de_flags, &type))
    return 4;
  if (!(de_flags & DOCEF_CENTER_X))
    return 5;
  // Multi-flag: +CX+UL → CENTER_X + UNDERLINE (type bit).
  de_flags = DOCEF_TAG;
  type = DOCT_TEXT;
  if (!RVDocPrsFlagsLex("+CX+UL", &de_flags, &type))
    return 6;
  if (!(de_flags & DOCEF_CENTER_X) || !(de_flags & DOCEF_UNDERLINE))
    return 7;
  if (!(type & DOCET_UNDERLINE))
    return 9;
  return 8;
}

Bool RVDocPrsDollarCmdLex(U8 *st, I64 *_cmd, I64 *_de_flags, U32 *_type, U8 *tag, I64 tag_max)
{
  //Stock PrsDollarCmd front half (DocPlain.HC): CmpCtrl Lex IDENT → DHT_DOC_CMD,
  // PrsDocFlags, skip commas, TK_STR tag. Abs-addr fps like RVDocPrsFlagsLex.
  // No LexExpression* / LexExtStr / DocIns — Soft tip only (hang → revert).
  CCmpCtrl * (*fp_new)(U8 *buf = NULL, I64 flags = 0, U8 *filename = NULL);
  I64 (*fp_lex)(CCmpCtrl *cc);
  U0 (*fp_del)(CCmpCtrl *cc);
  CCmpCtrl *cc;
  CHashGeneric *tmph;
  I64 fp_n, fp_l, fp_d, res, cmd, n;
  U32 typ;
  I64 de_flags;
  Bool turn_on;
  if (!st || !_cmd || !_de_flags || !_type || !tag || tag_max < 2)
    return FALSE;
  if (!doldoc.hash)
    DocInit;
  if (!doldoc.hash)
    return FALSE;
  if (!RVDocCmpFpsGet(&fp_n, &fp_l, &fp_d))
    return FALSE;
  fp_new = fp_n;
  fp_lex = fp_l;
  fp_del = fp_d;
  cc = fp_new(st, CCF_DONT_FREE_BUF, NULL);
  if (!cc)
    return FALSE;
  cc->htc.hash_table_lst = NULL;
  if (fp_lex(cc) != TK_IDENT || !cc->cur_str) {
    fp_del(cc);
    return FALSE;
  }
  if (!(tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_CMD | DHT_COLOR))) {
    fp_del(cc);
    return FALSE;
  }
  if (tmph->type & DHT_DOC_CMD)
    cmd = tmph->user_data0;
  else {
    cmd = DOCT_FOREGROUND;
  }
  fp_lex(cc);
  //skip cmd
  de_flags = doldoc.dft_de_flags[cmd];
  typ = cmd | doldoc.dft_type_flags[cmd];
  while (TRUE) {
    if (cc->token == '+')
      turn_on = TRUE;
    else if (cc->token == '-')
      turn_on = FALSE;
    else
      break;
    fp_lex(cc);
    if (cc->token == TK_IDENT && cc->cur_str && (tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_FLAG))) {
      res = tmph->user_data0;
      if (res < 64) {
        BEqu(&de_flags, res, turn_on);
        switch (res) {
          case DOCEf_BLINK :
          case DOCEf_INVERT :
          case DOCEf_UNDERLINE :
          case DOCEf_SEL :
          BEqu(&typ, res, turn_on);
          break;
        }
      }
      fp_lex(cc);
    } else
      break;
  }
  while (cc->token == ',')
    fp_lex(cc);
  tag[0] = 0;
  if (cc->token == TK_STR && cc->cur_str) {
    n = 0;
    while (cc->cur_str[n] && n < tag_max - 1) {
      tag[n] = cc->cur_str[n];
      n++;
    }
    tag[n] = 0;
  } else {
    fp_del(cc);
    return FALSE;
  }
  fp_del(cc);
  *_cmd = cmd;
  *_de_flags = de_flags;
  *_type = typ;
  rv_doc_prs_dollar_lex_hits++;
  return TRUE;
}

public I64 RVDocPrsDollarCmdLexProbe()
{
  //Soft tip: stock PrsDollarCmd one-cmd via abs-addr CmpCtrl Lex (TX+CX,"hi").
  I64 cmd, de_flags;
  U32 typ;
  U8 tag[32];
  I64 fp_n, fp_l, fp_d;
  DocInit;
  if (!doldoc.hash)
    return 2;
  if (!RVDocCmpFpsGet(&fp_n, &fp_l, &fp_d))
    return 3;
  if (!RVDocPrsDollarCmdLex("TX+CX,\"hi\"", &cmd, &de_flags, &typ, tag, sizeof(tag)))
    return 4;
  if (cmd != DOCT_TEXT)
    return 5;
  if (!(de_flags & DOCEF_CENTER_X))
    return 6;
  if (StrCmp(tag, "hi"))
    return 7;
  return 8;
}

Bool RVDocPrsDollarCmdLexArg(U8 *st, I64 *_cmd, I64 *_flag_idx, I64 *_val)
{
  //Stock PrsDollarCmd one LexExpression* arg (DocPlain.HC DOCEf_LEFT_EXP/LEN):
  // IDENT→DHT_DOC_CMD, optional +/-flags, optional TK_STR, IDENT→DHT_DOC_FLAG
  // (LE/LEN), '=', LexExpressionI64. Abs-addr fps incl. LexExpressionI64
  // (RVCmpCtrlAddrsGet[2]; literal fast-path — no Call). Soft tip only.
  CCmpCtrl * (*fp_new)(U8 *buf = NULL, I64 flags = 0, U8 *filename = NULL);
  I64 (*fp_lex)(CCmpCtrl *cc);
  I64 (*fp_lex_i64)(CCmpCtrl *cc);
  U0 (*fp_del)(CCmpCtrl *cc);
  CCmpCtrl *cc;
  CHashGeneric *tmph;
  I64 fp_n, fp_l, fp_d, fp_i64, res, cmd, fi, val;
  U32 typ;
  I64 de_flags;
  Bool turn_on;
  if (!st || !_cmd || !_flag_idx || !_val)
    return FALSE;
  if (!doldoc.hash)
    DocInit;
  if (!doldoc.hash)
    return FALSE;
  if (!RVDocCmpFpsGet(&fp_n, &fp_l, &fp_d, &fp_i64))
    return FALSE;
  fp_new = fp_n;
  fp_lex = fp_l;
  fp_del = fp_d;
  fp_lex_i64 = fp_i64;
  cc = fp_new(st, CCF_DONT_FREE_BUF, NULL);
  if (!cc)
    return FALSE;
  cc->htc.hash_table_lst = NULL;
  if (fp_lex(cc) != TK_IDENT || !cc->cur_str) {
    fp_del(cc);
    return FALSE;
  }
  if (!(tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_CMD | DHT_COLOR))) {
    fp_del(cc);
    return FALSE;
  }
  if (tmph->type & DHT_DOC_CMD)
    cmd = tmph->user_data0;
  else
    cmd = DOCT_FOREGROUND;
  fp_lex(cc);
  de_flags = doldoc.dft_de_flags[cmd];
  typ = cmd | doldoc.dft_type_flags[cmd];
  while (TRUE) {
    if (cc->token == '+')
      turn_on = TRUE;
    else if (cc->token == '-')
      turn_on = FALSE;
    else
      break;
    fp_lex(cc);
    if (cc->token == TK_IDENT && cc->cur_str && (tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_FLAG))) {
      res = tmph->user_data0;
      if (res < 64) {
        BEqu(&de_flags, res, turn_on);
        switch (res) {
          case DOCEf_BLINK :
          case DOCEf_INVERT :
          case DOCEf_UNDERLINE :
          case DOCEf_SEL :
          BEqu(&typ, res, turn_on);
          break;
        }
      }
      fp_lex(cc);
    } else
      break;
  }
  while (cc->token == ',')
    fp_lex(cc);
  if (cc->token == TK_STR)
    fp_lex(cc);
  while (cc->token == ',')
    fp_lex(cc);
  if (cc->token != TK_IDENT || !cc->cur_str || !(tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_FLAG))) {
    fp_del(cc);
    return FALSE;
  }
  fi = tmph->user_data0;
  if (fi != DOCEf_LEFT_EXP && fi != DOCEf_LEN) {
    fp_del(cc);
    return FALSE;
  }
  fp_lex(cc);
  if (cc->token != '=') {
    fp_del(cc);
    return FALSE;
  }
  fp_lex(cc);
  if (!cc->token) {
    fp_del(cc);
    return FALSE;
  }
  val = fp_lex_i64(cc);
  fp_del(cc);
  *_cmd = cmd;
  *_flag_idx = fi;
  *_val = val;
  rv_doc_prs_arg_lex_hits++;
  return TRUE;
}

public I64 RVDocPrsDollarCmdLexArgProbe()
{
  //Soft tip: stock PrsDollarCmd one LexExpressionI64 arg (BT,LE=1 / DA,LEN=8).
  I64 cmd, fi, val;
  I64 fp_n, fp_l, fp_d, fp_i64;
  DocInit;
  if (!doldoc.hash)
    return 2;
  if (!RVDocCmpFpsGet(&fp_n, &fp_l, &fp_d, &fp_i64))
    return 3;
  if (!RVDocPrsDollarCmdLexArg("BT,LE=1", &cmd, &fi, &val))
    return 4;
  if (cmd != DOCT_BTTN)
    return 5;
  if (fi != DOCEf_LEFT_EXP || val != 1)
    return 6;
  if (!RVDocPrsDollarCmdLexArg("DA,LEN=8", &cmd, &fi, &val))
    return 7;
  if (cmd != DOCT_DATA)
    return 9;
  if (fi != DOCEf_LEN || val != 8)
    return 10;
  return 8;
}

Bool RVDocPrsDollarCmdLexExt(U8 *st, I64 *_cmd, I64 *_flag_idx, U8 *out, I64 out_max)
{
  //Stock PrsDollarCmd LexExtStr arg (DocPlain.HC DOCEf_TAG / LEFT_MACRO):
  // IDENT→DHT_DOC_CMD, optional +/-flags, skip commas; then IDENT(T/LM)='='
  // TK_STR → LexExtStr (abs fp RVCmpCtrlAddrsGet[4]). Soft tip only.
  CCmpCtrl * (*fp_new)(U8 *buf = NULL, I64 flags = 0, U8 *filename = NULL);
  I64 (*fp_lex)(CCmpCtrl *cc);
  U8 * (*fp_lex_ext)(CCmpCtrl *cc, I64 *_size = NULL, Bool lex_next = TRUE);
  U0 (*fp_del)(CCmpCtrl *cc);
  CCmpCtrl *cc;
  CHashGeneric *tmph;
  I64 fp_n, fp_l, fp_d, fp_ext, res, cmd, fi, n;
  U32 typ;
  I64 de_flags;
  Bool turn_on;
  U8 *st2;
  if (!st || !_cmd || !_flag_idx || !out || out_max < 2)
    return FALSE;
  if (!doldoc.hash)
    DocInit;
  if (!doldoc.hash)
    return FALSE;
  if (!RVDocCmpFpsGet(&fp_n, &fp_l, &fp_d, NULL, &fp_ext))
    return FALSE;
  fp_new = fp_n;
  fp_lex = fp_l;
  fp_del = fp_d;
  fp_lex_ext = fp_ext;
  cc = fp_new(st, CCF_DONT_FREE_BUF, NULL);
  if (!cc)
    return FALSE;
  cc->htc.hash_table_lst = NULL;
  if (fp_lex(cc) != TK_IDENT || !cc->cur_str) {
    fp_del(cc);
    return FALSE;
  }
  if (!(tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_CMD | DHT_COLOR))) {
    fp_del(cc);
    return FALSE;
  }
  if (tmph->type & DHT_DOC_CMD)
    cmd = tmph->user_data0;
  else
    cmd = DOCT_FOREGROUND;
  fp_lex(cc);
  de_flags = doldoc.dft_de_flags[cmd];
  typ = cmd | doldoc.dft_type_flags[cmd];
  while (TRUE) {
    if (cc->token == '+')
      turn_on = TRUE;
    else if (cc->token == '-')
      turn_on = FALSE;
    else
      break;
    fp_lex(cc);
    if (cc->token == TK_IDENT && cc->cur_str && (tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_FLAG))) {
      res = tmph->user_data0;
      if (res < 64) {
        BEqu(&de_flags, res, turn_on);
        switch (res) {
          case DOCEf_BLINK :
          case DOCEf_INVERT :
          case DOCEf_UNDERLINE :
          case DOCEf_SEL :
          BEqu(&typ, res, turn_on);
          break;
        }
      }
      fp_lex(cc);
    } else
      break;
  }
  while (cc->token == ',')
    fp_lex(cc);
  if (cc->token != TK_IDENT || !cc->cur_str || !(tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_FLAG))) {
    fp_del(cc);
    return FALSE;
  }
  fi = tmph->user_data0;
  if (fi != DOCEf_TAG && fi != DOCEf_LEFT_MACRO) {
    fp_del(cc);
    return FALSE;
  }
  fp_lex(cc);
  if (cc->token != '=') {
    fp_del(cc);
    return FALSE;
  }
  fp_lex(cc);
  if (cc->token != TK_STR || !cc->cur_str) {
    fp_del(cc);
    return FALSE;
  }
  st2 = fp_lex_ext(cc, NULL, TRUE);
  if (!st2) {
    fp_del(cc);
    return FALSE;
  }
  n = 0;
  while (st2[n] && n < out_max - 1) {
    out[n] = st2[n];
    n++;
  }
  out[n] = 0;
  Free(st2);
  fp_del(cc);
  *_cmd = cmd;
  *_flag_idx = fi;
  rv_doc_prs_ext_lex_hits++;
  return TRUE;
}

public I64 RVDocPrsDollarCmdLexExtProbe()
{
  //Soft tip: stock PrsDollarCmd LexExtStr args (TX,T="hi" / MA,LM="Cd;").
  I64 cmd, fi;
  U8 out[32];
  I64 fp_n, fp_l, fp_d, fp_ext;
  DocInit;
  if (!doldoc.hash)
    return 2;
  if (!RVDocCmpFpsGet(&fp_n, &fp_l, &fp_d, NULL, &fp_ext))
    return 3;
  if (!RVDocPrsDollarCmdLexExt("TX,T=\"hi\"", &cmd, &fi, out, sizeof(out)))
    return 4;
  if (cmd != DOCT_TEXT)
    return 5;
  if (fi != DOCEf_TAG || StrCmp(out, "hi"))
    return 6;
  if (!RVDocPrsDollarCmdLexExt("MA,LM=\"Cd;\"", &cmd, &fi, out, sizeof(out)))
    return 7;
  if (cmd != DOCT_MACRO)
    return 9;
  if (fi != DOCEf_LEFT_MACRO || StrCmp(out, "Cd;"))
    return 10;
  return 8;
}

Bool RVDocPrsDollarCmdLexMulti(U8 *st, I64 *_cmd, I64 *_de_flags, U8 *tag, I64 tag_max, U8 *html, I64 html_max, U8 *aux, I64 aux_max, I64 *_bin)
{
  //Stock PrsDollarCmd multi-arg Soft tip (DocPlain.HC arg loop): IDENT→cmd,
  // +/-flags, then HAS_ARG: T/HTML/A via LexExtStr, BI via LexExpressionI64.
  // Abs fps RVCmpCtrlAddrsGet[0..4]. No DocIns / concat — Soft tip only.
  CCmpCtrl * (*fp_new)(U8 *buf = NULL, I64 flags = 0, U8 *filename = NULL);
  I64 (*fp_lex)(CCmpCtrl *cc);
  I64 (*fp_lex_i64)(CCmpCtrl *cc);
  U8 * (*fp_lex_ext)(CCmpCtrl *cc, I64 *_size = NULL, Bool lex_next = TRUE);
  U0 (*fp_del)(CCmpCtrl *cc);
  CCmpCtrl *cc;
  CHashGeneric *tmph;
  I64 fp_n, fp_l, fp_d, fp_i64, fp_ext, res, cmd, j, n, val;
  I64 de_flags, processed_flags, arg_flags;
  U32 typ;
  Bool turn_on;
  U8 *st2;
  if (!st || !_cmd || !_de_flags || !tag || tag_max < 2 || !html || html_max < 2 || !aux || aux_max < 2 || !_bin)
    return FALSE;
  if (!doldoc.hash)
    DocInit;
  if (!doldoc.hash)
    return FALSE;
  if (!RVDocCmpFpsGet(&fp_n, &fp_l, &fp_d, &fp_i64, &fp_ext))
    return FALSE;
  fp_new = fp_n;
  fp_lex = fp_l;
  fp_del = fp_d;
  fp_lex_i64 = fp_i64;
  fp_lex_ext = fp_ext;
  cc = fp_new(st, CCF_DONT_FREE_BUF, NULL);
  if (!cc)
    return FALSE;
  cc->htc.hash_table_lst = NULL;
  if (fp_lex(cc) != TK_IDENT || !cc->cur_str) {
    fp_del(cc);
    return FALSE;
  }
  if (!(tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_CMD | DHT_COLOR))) {
    fp_del(cc);
    return FALSE;
  }
  if (tmph->type & DHT_DOC_CMD)
    cmd = tmph->user_data0;
  else
    cmd = DOCT_FOREGROUND;
  fp_lex(cc);
  de_flags = doldoc.dft_de_flags[cmd];
  typ = cmd | doldoc.dft_type_flags[cmd];
  while (TRUE) {
    if (cc->token == '+')
      turn_on = TRUE;
    else if (cc->token == '-')
      turn_on = FALSE;
    else
      break;
    fp_lex(cc);
    if (cc->token == TK_IDENT && cc->cur_str && (tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_FLAG))) {
      res = tmph->user_data0;
      if (res < 64) {
        BEqu(&de_flags, res, turn_on);
        switch (res) {
          case DOCEf_BLINK :
          case DOCEf_INVERT :
          case DOCEf_UNDERLINE :
          case DOCEf_SEL :
          BEqu(&typ, res, turn_on);
          break;
        }
      }
      fp_lex(cc);
    } else
      break;
  }
  tag[0] = 0;
  html[0] = 0;
  aux[0] = 0;
  *_bin = -1;
  processed_flags = 0;
  while (TRUE) {
    while (cc->token == ',')
      fp_lex(cc);
    j = -1;
    if (cc->token == TK_IDENT && cc->cur_str && (tmph = HashFind(cc->cur_str, doldoc.hash, DHT_DOC_FLAG))) {
      j = tmph->user_data0;
      if (j < 64) {
        BEqu(&de_flags, j, TRUE);
        switch (j) {
          case DOCEf_BLINK :
          case DOCEf_INVERT :
          case DOCEf_UNDERLINE :
          case DOCEf_SEL :
          BEqu(&typ, j, TRUE);
          break;
        }
      }
      fp_lex(cc);
    }
    if (!(arg_flags = ~processed_flags & de_flags & DOCEG_HAS_ARG))
      break;
    if (cc->token == '=')
      fp_lex(cc);
    else
      j = Bsf(arg_flags);
    if (j < 0 || Bts(&processed_flags, j)) {
      fp_del(cc);
      return FALSE;
    }
    if (j == DOCEf_TAG || j == DOCEf_HTML_LINK || j == DOCEf_AUX_STR) {
      if (cc->token != TK_STR || !cc->cur_str) {
        fp_del(cc);
        return FALSE;
      }
      st2 = fp_lex_ext(cc, NULL, TRUE);
      if (!st2) {
        fp_del(cc);
        return FALSE;
      }
      n = 0;
      if (j == DOCEf_TAG) {
        while (st2[n] && n < tag_max - 1) {
          tag[n] = st2[n];
          n++;
        }
        tag[n] = 0;
      } else if (j == DOCEf_HTML_LINK) {
        while (st2[n] && n < html_max - 1) {
          html[n] = st2[n];
          n++;
        }
        html[n] = 0;
      } else {
        while (st2[n] && n < aux_max - 1) {
          aux[n] = st2[n];
          n++;
        }
        aux[n] = 0;
      }
      Free(st2);
    } else if (j == DOCEf_HAS_BIN) {
      if (!cc->token) {
        fp_del(cc);
        return FALSE;
      }
      val = fp_lex_i64(cc);
      *_bin = val;
    } else {
      fp_del(cc);
      return FALSE;
    }
  }
  fp_del(cc);
  *_cmd = cmd;
  *_de_flags = de_flags;
  rv_doc_prs_multi_lex_hits++;
  return TRUE;
}

public I64 RVDocPrsDollarCmdLexMultiProbe()
{
  //Soft tip: multi-arg stock PrsDollarCmd via abs-addr CmpCtrl
  // (TX+CX,T="hi" / LK,"hi",A=/HTML=/BI=).
  I64 cmd, de_flags, bin;
  U8 tag[32], html[64], aux[32];
  I64 fp_n, fp_l, fp_d, fp_i64, fp_ext;
  DocInit;
  if (!doldoc.hash)
    return 2;
  if (!RVDocCmpFpsGet(&fp_n, &fp_l, &fp_d, &fp_i64, &fp_ext))
    return 3;
  if (!RVDocPrsDollarCmdLexMulti("TX+CX,T=\"hi\"", &cmd, &de_flags, tag, sizeof(tag), html, sizeof(html), aux, sizeof(aux), &bin))
    return 4;
  if (cmd != DOCT_TEXT)
    return 5;
  if (!(de_flags & DOCEF_CENTER_X))
    return 6;
  if (StrCmp(tag, "hi"))
    return 7;
  if (!RVDocPrsDollarCmdLexMulti("LK,\"hi\",A=\"MN:Lex\",HTML=\"http://x\",BI=1", &cmd, &de_flags, tag, sizeof(tag), html, sizeof(html), aux, sizeof(aux), &bin))
    return 9;
  if (cmd != DOCT_LINK)
    return 10;
  if (StrCmp(tag, "hi"))
    return 11;
  if (StrCmp(aux, "MN:Lex"))
    return 12;
  if (StrCmp(html, "http://x"))
    return 13;
  if (bin != 1)
    return 14;
  return 8;
}

Bool RVDocPrsArgOnce(U8 **pp, I64 *_flag_idx, U8 *val, I64 val_max)
{
  //Stock PrsDollarCmd arg shape (DocPlain.HC): IDENT= → DHT_DOC_FLAG HashFind
  // then quoted "..." (T/HTML/LM/A) or int (LE/BI). No CmpCtrl Lex.
  U8 *p;
  U8 ident[16];
  I64 n, num, taken;
  CHashGeneric *tmph;
  if (!pp || !*pp || !_flag_idx || !val || val_max < 2)
    return FALSE;
  if (!doldoc.hash)
    DocInit;
  if (!doldoc.hash)
    return FALSE;
  p = *pp;
  while (*p == ' ' || *p == ',' || *p == '\t')
    p++;
  n = 0;
  while (*p && *p != '=' && *p != ',' && *p != '"' && *p != ' ' && *p != '\t' && n < sizeof(ident) - 1)
    ident[n++] = *p++;
  ident[n] = 0;
  if (!ident[0])
    return FALSE;
  while (*p == ' ' || *p == '\t')
    p++;
  if (*p != '=')
    return FALSE;
  p++;
  while (*p == ' ' || *p == '\t')
    p++;
  if (!(tmph = HashFind(ident, doldoc.hash, DHT_DOC_FLAG)))
    return FALSE;
  *_flag_idx = tmph->user_data0;
  if (*p == '"') {
    if (!RVDocExtractQuoted(&p, val, val_max))
      return FALSE;
  } else {
    taken = RVDocParseInt(p, &num);
    if (taken <= 0)
      return FALSE;
    p += taken;
    StrPrint(val, "%d", num);
  }
  *pp = p;
  rv_doc_prs_arg_hits++;
  return TRUE;
}

Bool RVDocPrsArgFind(U8 *cmd, I64 want_fi, U8 *val, I64 val_max)
{
  //Scan dollar-cmd for KEY=val via HashFind (want_fi = DOCEf_*).
  U8 *p, *scan;
  I64 fi;
  if (!cmd || !val || val_max < 2)
    return FALSE;
  p = cmd;
  while (*p) {
    while (*p && !(*p >= 'A' && *p <= 'Z') && !(*p >= 'a' && *p <= 'z'))
      p++;
    if (!*p)
      break;
    scan = p;
    if (RVDocPrsArgOnce(&scan, &fi, val, val_max)) {
      if (fi == want_fi)
        return TRUE;
      p = scan;
      continue;
    }
    p++;
  }
  return FALSE;
}

public I64 RVDocPrsArgTagProbe()
{
  //Soft tip: stock T=/HTML= arg Lex (HashFind + quote) toward PrsDollarCmd.
  U8 *p;
  U8 val[96];
  I64 fi;
  DocInit;
  p = ",T=\"TempleOS\",HTML=\"http://www.templeos.org\"";
  if (!RVDocPrsArgOnce(&p, &fi, val, sizeof(val)))
    return 3;
  if (fi != DOCEf_TAG || StrCmp(val, "TempleOS"))
    return 4;
  if (!RVDocPrsArgOnce(&p, &fi, val, sizeof(val)))
    return 5;
  if (fi != DOCEf_HTML_LINK || StrCmp(val, "http://www.templeos.org"))
    return 6;
  return 8;
}

public I64 RVDocPrsArgExtraProbe()
{
  //Soft tip: stock LE=/LM=/A=/BI= arg kinds (HashFind + int|quote).
  U8 *p;
  U8 val[96];
  I64 fi, n;
  DocInit;
  p = ",LE=1,LM=\"Cd;\",A=\"MN:Lex\",BI=17";
  if (!RVDocPrsArgOnce(&p, &fi, val, sizeof(val)))
    return 3;
  if (fi != DOCEf_LEFT_EXP || RVDocParseInt(val, &n) <= 0 || n != 1)
    return 4;
  if (!RVDocPrsArgOnce(&p, &fi, val, sizeof(val)))
    return 5;
  if (fi != DOCEf_LEFT_MACRO || StrCmp(val, "Cd;"))
    return 6;
  if (!RVDocPrsArgOnce(&p, &fi, val, sizeof(val)))
    return 7;
  if (fi != DOCEf_AUX_STR || StrCmp(val, "MN:Lex"))
    return 9;
  if (!RVDocPrsArgOnce(&p, &fi, val, sizeof(val)))
    return 10;
  if (fi != DOCEf_HAS_BIN || RVDocParseInt(val, &n) <= 0 || n != 17)
    return 11;
  return 8;
}

Bool RVDocInitSeedApply(U8 *seed)
{
  //Stock DocInit.HC CmpCtrl seed Lex shape without CmpCtrl: IDENT → DHT_DOC_CMD
  // HashFind, then +/−flags via RVDocPrsFlagsCmp (same DHT_DOC_FLAG HashFind).
  U8 *p;
  U8 ident[16];
  U8 flagbuf[96];
  I64 n, i, fn;
  U32 typ;
  CHashGeneric *tmph;
  if (!seed || !doldoc.hash)
    return FALSE;
  p = seed;
  while (*p) {
    while (*p == ' ' || *p == '\t' || *p == ';')
      p++;
    if (!*p)
      break;
    n = 0;
    while (*p && *p != '+' && *p != '-' && *p != ';' && *p != ' ' && *p != '\t' && n < sizeof(ident) - 1)
      ident[n++] = *p++;
    ident[n] = 0;
    if (!ident[0])
      break;
    fn = 0;
    while (*p && *p != ';' && fn < sizeof(flagbuf) - 1)
      flagbuf[fn++] = *p++;
    flagbuf[fn] = 0;
    if (*p == ';')
      p++;
    if (!(tmph = HashFind(ident, doldoc.hash, DHT_DOC_CMD)))
      continue;
    i = tmph->user_data0;
    if (i < 0 || i >= DOCT_TYPES_NUM)
      return FALSE;
    if (flagbuf[0]) {
      typ = doldoc.dft_type_flags[i];
      RVDocPrsFlagsCmp(flagbuf, &doldoc.dft_de_flags[i], &typ);
      doldoc.dft_type_flags[i] = typ;
    }
  }
  return TRUE;
}

public I64 RVDocDolDocHashGet()
{
  //Soft tip: Kernel doldoc.hash addr without Soft defining Soft doldoc (Load shadow).
  if (!doldoc.hash)
    DocInit;
  return doldoc.hash(I64);
}

public I64 RVDocKernDolDocHashProbe()
{
  //Soft tip: Kernel doldoc.hash TX via Soft Call (no Soft Call Load of Soft doldoc).
  DocInit;
  if (!doldoc.hash)
    return 2;
  if (!HashFind("TX", doldoc.hash, DHT_DOC_CMD))
    return 3;
  return 1;
}

public I64 RVDocInitSeedProbe()
{
  //Soft tip: DocInit DHT_DOC_FLAG/CMD plant + stock seed-string dft flags
  // (DocInit.HC CmpCtrl seed Lex shape via RVDocInitSeedApply).
  I64 i;
  I64 de_hand[DOCT_TYPES_NUM];
  I32 ty_hand[DOCT_TYPES_NUM];
  DocInit;
  if (!doldoc.hash)
    return 2;
  if (!HashFind("T", doldoc.hash, DHT_DOC_FLAG))
    return 3;
  if (!HashFind("CX", doldoc.hash, DHT_DOC_FLAG))
    return 4;
  if (!HashFind("TX", doldoc.hash, DHT_DOC_CMD))
    return 5;
  if (!HashFind("LK", doldoc.hash, DHT_DOC_CMD))
    return 6;
  // Snapshot current dfts (hand plant or prior SeedApply), re-apply stock seed.
  MemCpy(de_hand, doldoc.dft_de_flags, sizeof(de_hand));
  MemCpy(ty_hand, doldoc.dft_type_flags, sizeof(ty_hand));
  MemSet(doldoc.dft_de_flags, 0, sizeof(doldoc.dft_de_flags));
  MemSet(doldoc.dft_type_flags, 0, sizeof(doldoc.dft_type_flags));
  if (!RVDocInitSeedApply("TX+T;DA+P+TRM+T+DL+DRT;CM+LE+RE;AN+T;LK+L+UL+T;MA+X+UL+T;" "MU+X+UL+T;BT+X+B+T;CB+CA+P+T+DRT;LS+LS+P+T+DRT;HX+P+Z;TR+TR+C+CA+UL+T;" "SP+T;IB+T;IS+T;SO+T;HC+T;")) {
    MemCpy(doldoc.dft_de_flags, de_hand, sizeof(de_hand));
    MemCpy(doldoc.dft_type_flags, ty_hand, sizeof(ty_hand));
    return 7;
  }
  for (i = 0; i < DOCT_TYPES_NUM; i++)
    doldoc.dft_de_flags[i] &= ~DOCG_BL_IV_UL;
  if (doldoc.dft_de_flags[DOCT_TEXT] != DOCEF_TAG) {
    MemCpy(doldoc.dft_de_flags, de_hand, sizeof(de_hand));
    MemCpy(doldoc.dft_type_flags, ty_hand, sizeof(ty_hand));
    return 9;
  }
  if (doldoc.dft_de_flags[DOCT_DATA] != (DOCEF_DEREF_DATA | DOCEF_HAS_TERMINATOR | DOCEF_TAG | DOCEF_DFT_LEN | DOCEF_DFT_RAW_TYPE)) {
    MemCpy(doldoc.dft_de_flags, de_hand, sizeof(de_hand));
    MemCpy(doldoc.dft_type_flags, ty_hand, sizeof(ty_hand));
    return 10;
  }
  if (doldoc.dft_de_flags[DOCT_LINK] != (DOCEF_LINK | DOCEF_TAG) || !(doldoc.dft_type_flags[DOCT_LINK] & DOCET_UNDERLINE)) {
    MemCpy(doldoc.dft_de_flags, de_hand, sizeof(de_hand));
    MemCpy(doldoc.dft_type_flags, ty_hand, sizeof(ty_hand));
    return 11;
  }
  if (doldoc.dft_de_flags[DOCT_CURSOR_MOVEMENT] != (DOCEF_LEFT_EXP | DOCEF_RIGHT_EXP)) {
    MemCpy(doldoc.dft_de_flags, de_hand, sizeof(de_hand));
    MemCpy(doldoc.dft_type_flags, ty_hand, sizeof(ty_hand));
    return 12;
  }
  // Seed apply must match hand plant (or prior SeedApply SoT).
  if (doldoc.dft_de_flags[DOCT_TEXT] != de_hand[DOCT_TEXT] || doldoc.dft_de_flags[DOCT_DATA] != de_hand[DOCT_DATA] || doldoc.dft_de_flags[DOCT_LINK] != de_hand[DOCT_LINK] || doldoc.dft_type_flags[DOCT_LINK] != ty_hand[DOCT_LINK]) {
    MemCpy(doldoc.dft_de_flags, de_hand, sizeof(de_hand));
    MemCpy(doldoc.dft_type_flags, ty_hand, sizeof(ty_hand));
    return 13;
  }
  return 8;
}

Bool DocLock(CDoc *doc)
{
  //Adam/DolDoc/DocNew.HC DocLock — Yield while contending so WinMgr can unlock.
  if (!doc)
    return FALSE;
  if (!Bt(&doc->locked_flags, DOClf_LOCKED) || doc->owning_task != Fs) {
    while (LBts(&doc->locked_flags, DOClf_LOCKED))
      Yield;
    doc->owning_task = Fs;
    return TRUE;
  }
  return FALSE;
}

Bool DocUnlock(CDoc *doc)
{
  if (!doc)
    return FALSE;
  if (Bt(&doc->locked_flags, DOClf_LOCKED) && doc->owning_task == Fs) {
    doc->owning_task = 0;
    LBtr(&doc->locked_flags, DOClf_LOCKED);
    return TRUE;
  }
  return FALSE;
}

CDocEntry *DocEntryNewBase(CDoc *doc, I64 type, I64 de_flags = 0, I64 x = 0, I64 y = 0, I64 page_line_num = 0)
{
  CDocEntry *res;
  CTask *task;
  if (!doc)
    return NULL;
  task = doc->mem_task;
  if (!task)
    task = Fs;
  res = CAlloc(sizeof(CDocEntry), task);
  res->type = type;
  res->de_flags = de_flags;
  res->x = x;
  res->y = y;
  res->page_line_num = page_line_num;
  return res;
}

U0 DocEntryDel(CDoc *doc, CDocEntry *doc_e)
{
  if (!doc || !doc_e || doc == doc_e)
    return;
  if (doc->cur_entry == doc_e)
    doc->cur_entry = doc_e->next;
  QueRem(doc_e);
  // KUtilsRV QueRem null-safe (no sd through NULL last/next)
  if (doc_e->de_flags & DOCEF_TAG)
    Free(doc_e->tag);
  if (doc_e->de_flags & DOCEF_AUX_STR)
    Free(doc_e->aux_str);
  if (doc_e->de_flags & DOCEF_DEFINE)
    Free(doc_e->define_str);
  if (doc_e->de_flags & DOCEF_HTML_LINK)
    Free(doc_e->html_link);
  Free(doc_e);
}

U0 DocInsEntry(CDoc *doc, CDocEntry *doc_e)
{
  CDocEntry *doc_ce;
  Bool unlock;
  if (!doc || !doc_e)
    return;
  unlock = DocLock(doc);
  doc_ce = doc->cur_entry;
  if (!doc_ce)
    doc_ce = doc;
  doc_e->x = doc_ce->x;
  doc_e->y = doc_ce->y;
  doc_e->page_line_num = doc_ce->page_line_num;
  MemCpy(&doc_e->settings, &doc_ce->settings, sizeof(CDocSettings));
  QueIns(doc_e, doc_ce->last);
  doc->cur_entry = doc_e->next;
  doc->cur_col = doc->cur_entry->min_col;
  if (unlock)
    DocUnlock(doc);
}
Bool DocRecalc(CDoc *doc, I64 recalc_flags = RECALCt_NORMAL);
U0 DocTop(CDoc *doc = NULL)
{
  Bool unlock;
  if (!doc && !(doc = DocPut))
    return;
  if (doc->doc_signature != DOC_SIGNATURE_VAL)
    return;
  unlock = DocLock(doc);
  doc->cur_entry = doc->head.next;
  doc->cur_col = doc->cur_entry->min_col;
  doc->line = 1;
  doc->top_line_num = 0;
  if (unlock)
    DocUnlock(doc);
  DocRecalc(doc);
}

U0 DocBottom(CDoc *doc = NULL)
{
  Bool unlock;
  if (!doc && !(doc = DocPut))
    return;
  if (doc->doc_signature != DOC_SIGNATURE_VAL)
    return;
  unlock = DocLock(doc);
  doc->cur_entry = doc;
  doc->cur_col = 0;
  if (unlock)
    DocUnlock(doc);
  DocRecalc(doc);
}

U0 DocCenter(CDoc *doc = NULL)
{
  //Soft center — DocTop is enough for FileMgr rebuild smoke.
  DocTop(doc);
}

U0 DocRst(CDoc *doc, Bool is_old)
{
  CDocEntry *doc_e, *doc_e2;
  CDocBin *b, *b2;
  CDocSettings *s;
  Bool unlock;
  if (!doc)
    return;
  unlock = DocLock(doc);
  if (is_old) {
    doc_e = doc->head.next;
    while (doc_e != doc) {
      doc_e2 = doc_e->next;
      DocEntryDel(doc, doc_e);
      doc_e = doc_e2;
    }
    // Free bins before QueInit (QueInit orphans without unlink — UAF risk).
    b = doc->bin_head.next;
    while (b && b != &doc->bin_head) {
      b2 = b->next;
      QueRem(b);
      Free(b->data);
      Free(b->tag);
      Free(b);
      b = b2;
    }
  }
  doc->flags &= DOCF_BREAK_UNLOCKED;
  doc->head.next = doc->head.last = doc;
  QueInit(&doc->bin_head);
  QueInit(&doc->undo_head);
  doc->undo_cnt = 0;
  doc->cur_bin_num = 1;
  doc->dollar_buf_ptr = 0;
  doc->page_line_num = 0;
  doc->best_d = I64_MAX;
  doc->min_x = doc->min_y = 0;
  doc->max_x = doc->max_y = 0;
  doc->x = doc->y = 0;
  s = &doc->settings_head;
  MemSet(s, 0, sizeof(CDocSettings));
  s->left_margin = DOC_DFT;
  s->right_margin = DOC_DFT;
  s->indent = 0;
  s->page_len = 66;
  s->header = DOC_DFT;
  s->footer = DOC_DFT;
  s->cur_text_attr = s->dft_text_attr = DOC_ATTR_DFT_TEXT;
  doc_e = &doc->head;
  doc_e->type = DOCT_ERROR;
  doc_e->de_flags = 0;
  doc_e->x = 0;
  doc_e->y = 0;
  doc_e->min_col = 0;
  doc_e->max_col = 0;
  MemCpy(&doc_e->settings, s, sizeof(CDocSettings));
  doc->cur_entry = doc;
  doc->cur_col = 0;
  if (unlock)
    DocUnlock(doc);
}

U0 DocDel(CDoc *doc)
{
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return;
  DocLock(doc);
  doc->doc_signature = 0;
  DocRst(doc, TRUE);
  Free(doc->find_replace);
  Free(doc->dollar_buf);
  DocUnlock(doc);
  Free(doc);
}

CDoc *DocNew(U8 *filename = NULL, CTask *task = NULL)
{
  CDoc *doc;
  if (!task)
    task = Fs;
  doc = CAlloc(sizeof(CDoc), task);
  if (!doc)
    return NULL;
  if (filename)
    StrCpy(doc->filename.name, filename);
  else
    StrCpy(doc->filename.name, "NONAME.DD");
  doc->find_replace = CAlloc(sizeof(CEdFindText), task);
  doc->dollar_buf_size = 84;
  doc->dollar_buf = MAlloc(doc->dollar_buf_size, task);
  doc->max_entries = I64_MAX;
  doc->win_task = task;
  doc->mem_task = task;
  DocRst(doc, FALSE);
  doc->doc_signature = DOC_SIGNATURE_VAL;
  doc->cur_entry = doc;
  return doc;
}

CDocBin *DocBinFindNum(CDoc *haystack_doc, I64 needle_num)
{
  CDocBin *b;
  if (!haystack_doc)
    return NULL;
  b = haystack_doc->bin_head.next;
  while (b != &haystack_doc->bin_head) {
    if (b->num == needle_num)
      return b;
    b = b->next;
  }
  return NULL;
}

CDocBin *DocBinFindTag(CDoc *haystack_doc, U8 *needle_tag)
{
  CDocBin *b;
  if (!haystack_doc || !needle_tag)
    return NULL;
  b = haystack_doc->bin_head.next;
  while (b != &haystack_doc->bin_head) {
    if (b->tag && !StrCmp(b->tag, needle_tag))
      return b;
    b = b->next;
  }
  return NULL;
}

U0 DocBinDel(CDoc *doc, CDocBin *b)
{
  if (!doc || !b)
    return;
  if (b->use_cnt)
    b->use_cnt--;
  if (!b->use_cnt) {
    QueRem(b);
    Free(b->tag);
    Free(b->data);
    Free(b);
  }
}

U0 DocBinsValidate(CDoc *doc)
{
  //Thin Adam/DocBin.HC: renumber used bins; drop orphans; wire entry bin_data.
  Bool unlock;
  CDocBin *b, *b1;
  CDocEntry *doc_e;
  I64 renum = 0;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return;
  unlock = DocLock(doc);
  b = doc->bin_head.next;
  while (b != &doc->bin_head) {
    b->use_cnt = 0;
    b->tmp_use_cnt = 0;
    b->renum_num = -1;
    Free(b->tag);
    b->tag = NULL;
    b = b->next;
  }
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->de_flags & DOCEF_HAS_BIN) {
      b = DocBinFindNum(doc, doc_e->bin_num);
      doc_e->bin_data = b;
      if (b) {
        if (!b->use_cnt++)
          b->renum_num = ++renum;
        doc_e->bin_num = b->renum_num;
        if (!b->tag && doc_e->de_flags & DOCEF_TAG && doc_e->tag && doc_e->tag[0])
          b->tag = StrNew(doc_e->tag, doc->mem_task);
      } else {
        doc_e->de_flags &= ~DOCEF_HAS_BIN;
        doc_e->bin_num = 0;
      }
    }
    doc_e = doc_e->next;
  }
  b = doc->bin_head.next;
  doc->cur_bin_num = 1;
  while (b != &doc->bin_head) {
    b1 = b->next;
    if (!b->use_cnt) {
      QueRem(b);
      Free(b->data);
      Free(b);
    } else {
      b->num = b->renum_num;
      if (b->num >= doc->cur_bin_num)
        doc->cur_bin_num = b->num + 1;
    }
    b = b1;
  }
  if (unlock)
    DocUnlock(doc);
}

CDocBin *DocBinNew(CDoc *doc, U8 *data, I64 size, U8 *tag = NULL)
{
  CDocBin *b;
  if (!doc)
    return NULL;
  b = CAlloc(sizeof(CDocBin), doc->mem_task);
  b->num = doc->cur_bin_num++;
  b->size = size;
  b->use_cnt = 1;
  if (size > 0 && data) {
    b->data = MAlloc(size, doc->mem_task);
    if (!b->data) {
      Free(b);
      return NULL;
    }
    MemCpy(b->data, data, size);
  }
  if (tag)
    b->tag = StrNew(tag, doc->mem_task);
  QueIns(b, doc->bin_head.last);
  rv_doc_bin_hits++;
  return b;
}

I64 DocSize(CDoc *doc)
{
  CDocEntry *doc_e;
  I64 res = 0, guard = 0;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return 0;
  doc_e = doc->head.next;
  while (doc_e && doc_e != doc) {
    res++;
    if (++guard > 100000)
      break;
    doc_e = doc_e->next;
  }
  return res;
}

U8 *RVDocStrNew(CDoc *doc, U8 *st)
{
  I64 l;
  U8 *res;
  CTask *task;
  if (!st)
    return NULL;
  task = doc->mem_task;
  if (!task)
    task = Fs;
  l = StrLen(st);
  res = MAlloc(l + 1, task);
  if (!res)
    return NULL;
  MemCpy(res, st, l + 1);
  return res;
}

U0 RVDocInsText(CDoc *doc, U8 *tag, I64 attr = -1)
{
  CDocEntry *doc_e;
  I64 l;
  if (!doc || !tag || !tag[0])
    return;
  l = StrLen(tag);
  doc_e = DocEntryNewBase(doc, DOCT_TEXT | (doc->settings_head.dft_text_attr << 8));
  if (attr >= 0)
    doc_e->type = DOCT_TEXT | ((attr & 255) << 8);
  doc_e->de_flags = DOCEF_TAG;
  doc_e->tag = RVDocStrNew(doc, tag);
  doc_e->max_col = l;
  DocInsEntry(doc, doc_e);
}

U0 RVDocInsNewLine(CDoc *doc)
{
  CDocEntry *doc_e;
  if (!doc)
    return;
  doc_e = DocEntryNewBase(doc, DOCT_NEW_LINE | (doc->settings_head.dft_text_attr << 8));
  DocInsEntry(doc, doc_e);
}

U0 RVDocInsTab(CDoc *doc)
{
  CDocEntry *doc_e;
  if (!doc)
    return;
  doc_e = DocEntryNewBase(doc, DOCT_TAB | (doc->settings_head.dft_text_attr << 8));
  DocInsEntry(doc, doc_e);
}

I64 RVDocParseInt(U8 *s, I64 *out)
{
  //Decimal or 0x hex (FileMgr $$TR/$$MU U=0x%X).
  I64 i = 0, v = 0, sign = 1, d;
  if (!s || !out)
    return 0;
  while (s[i] == ' ')
    i++;
  if (s[i] == '+')
    i++;
  else if (s[i] == '-') {
    sign = -1;
    i++;
  }
  if (s[i] == '0' && (s[i + 1] == 'x' || s[i + 1] == 'X')) {
    i += 2;
    if (!((s[i] >= '0' && s[i] <= '9') || (s[i] >= 'a' && s[i] <= 'f') || (s[i] >= 'A' && s[i] <= 'F')))
      return 0;
    while (TRUE) {
      if (s[i] >= '0' && s[i] <= '9')
        d = s[i] - '0';
      else if (s[i] >= 'a' && s[i] <= 'f')
        d = s[i] - 'a' + 10;
      else if (s[i] >= 'A' && s[i] <= 'F')
        d = s[i] - 'A' + 10;
      else
        break;
      v = v << 4 + d;
      i++;
    }
    *out = sign *v;
    return i;
  }
  if (s[i] < '0' || s[i] > '9')
    return 0;
  while (s[i] >= '0' && s[i] <= '9') {
    v = v * 10 + s[i] - '0';
    i++;
  }
  *out = sign *v;
  return i;
}

Bool RVDocAttachUserData(CDoc *doc, CDocEntry *doc_e, U8 *cmd)
{
  //Parse U=n / U=0x%X into user_data (FileMgr DirFileDoc shape).
  U8 *q;
  I64 n;
  no_warn doc;
  if (!doc_e || !cmd)
    return FALSE;
  q = cmd;
  while (*q) {
    if (q[0] == 'U' && q[1] == '=') {
      q += 2;
      if (RVDocParseInt(q, &n) > 0) {
        doc_e->de_flags |= DOCEF_USER_DATA;
        doc_e->user_data = n;
        rv_doc_filemgr_user_hits++;
        return TRUE;
      }
      return FALSE;
    }
    q++;
  }
  return FALSE;
}

I64 RVDocColorName(U8 *s)
{
  //Subset of ST_COLORS — enough for HOME / Welcome.DD.
  if (!s)
    return -1;
  if (!StrCmp(s, "BLACK"))
    return BLACK;
  if (!StrCmp(s, "BLUE"))
    return BLUE;
  if (!StrCmp(s, "GREEN"))
    return GREEN;
  if (!StrCmp(s, "CYAN"))
    return CYAN;
  if (!StrCmp(s, "RED"))
    return RED;
  if (!StrCmp(s, "PURPLE"))
    return PURPLE;
  if (!StrCmp(s, "BROWN"))
    return BROWN;
  if (!StrCmp(s, "LTGRAY"))
    return LTGRAY;
  if (!StrCmp(s, "DKGRAY"))
    return DKGRAY;
  if (!StrCmp(s, "LTBLUE"))
    return LTBLUE;
  if (!StrCmp(s, "LTGREEN"))
    return LTGREEN;
  if (!StrCmp(s, "LTCYAN"))
    return LTCYAN;
  if (!StrCmp(s, "LTRED"))
    return LTRED;
  if (!StrCmp(s, "LTPURPLE"))
    return LTPURPLE;
  if (!StrCmp(s, "YELLOW"))
    return YELLOW;
  if (!StrCmp(s, "WHITE"))
    return WHITE;
  return -1;
}

Bool RVDocExtractQuoted(U8 **pp, U8 *dst, I64 dst_max)
{
  //Advance *pp past "..." into dst. Returns FALSE if no quote.
  U8 *p;
  I64 n = 0;
  if (!pp || !*pp || !dst || dst_max < 2)
    return FALSE;
  p = *pp;
  while (*p == ' ' || *p == ',')
    p++;
  if (*p != '"')
    return FALSE;
  p++;
  while (*p && *p != '"' && n < dst_max - 1)
    dst[n++] = *p++;
  dst[n] = 0;
  if (*p == '"')
    p++;
  *pp = p;
  return TRUE;
}

U8 *RVDocFindArg(U8 *cmd, U8 *key)
{
  //Find KEY="..." inside dollar cmd (e.g. A="FI:..."). Returns ptr at opening quote.
  U8 *p;
  I64 kl;
  if (!cmd || !key)
    return NULL;
  kl = StrLen(key);
  p = cmd;
  while (*p) {
    if (!StrNCmp(p, key, kl) && p[kl] == '=') {
      p += kl + 1;
      while (*p == ' ')
        p++;
      if (*p == '"')
        return p;
      return NULL;
    }
    p++;
  }
  return NULL;
}

Bool RVDocCmdHasFlag(U8 *cmd, I64 ch)
{
  //True if +ch or -ch appears in flag run before first comma/quote.
  U8 *p = cmd;
  if (!cmd)
    return FALSE;
  while (*p && *p != ',' && *p != '"' && *p != ' ') {
    if ((*p == '+' || *p == '-') && p[1] == ch)
      return TRUE;
    p++;
  }
  return FALSE;
}

U0 RVDocAttachHtml(CDoc *doc, CDocEntry *doc_e, U8 *cmd)
{
  U8 *p, *q, *scan, aux[160];
  I64 n, fi;
  if (!doc || !doc_e || !cmd)
    return;
  // Stock arg Lex: HTML="..." via DHT_DOC_FLAG HashFind (PrsDollarCmd shape).
  p = cmd;
  while (*p) {
    while (*p && !(*p >= 'A' && *p <= 'Z') && !(*p >= 'a' && *p <= 'z'))
      p++;
    if (!*p)
      break;
    scan = p;
    if (RVDocPrsArgOnce(&scan, &fi, aux, sizeof(aux))) {
      if (fi == DOCEf_HTML_LINK && aux[0]) {
        doc_e->de_flags |= DOCEF_HTML_LINK;
        doc_e->html_link = RVDocStrNew(doc, aux);
        rv_doc_html_hits++;
        return;
      }
      p = scan;
      continue;
    }
    p++;
  }
  // Fallback string KEY= (pre-HashFind path).
  q = RVDocFindArg(cmd, "HTML");
  if (!q)
    return;
  q++;
  n = 0;
  while (*q && *q != '"' && n < sizeof(aux) - 1)
    aux[n++] = *q++;
  aux[n] = 0;
  if (!aux[0])
    return;
  doc_e->de_flags |= DOCEF_HTML_LINK;
  doc_e->html_link = RVDocStrNew(doc, aux);
  rv_doc_html_hits++;
}

U0 RVDocPrsDollarCmd(CDoc *doc, U8 *cmd)
{
  //DocInit_RV HashFind + hand bodies; TX+CX via RVDocPrsFlagsCmp (same unit).
  CDocEntry *doc_e;
  CHashGeneric *tmph;
  U8 tag[128], aux[160], buf[48], ident[16];
  U8 *p, *q;
  I64 attr, n, i, color, cols, de_flags, fi;
  U32 typ;
  if (!doc || !cmd || !cmd[0])
    return;
  DocInit;
  p = cmd;
  while (*p == ' ' || *p == '\t')
    p++;
  n = 0;
  while (*p && n < sizeof(ident) - 1 && (*p >= 'A' && *p <= 'Z' || *p >= 'a' && *p <= 'z' || *p >= '0' && *p <= '9'))
    ident[n++] = *p++;
  ident[n] = 0;
  if (ident[0] && doldoc.hash && (tmph = HashFind(ident, doldoc.hash, DHT_DOC_CMD | DHT_COLOR))) {
    rv_doc_prs_lex_hits++;
    if (tmph->type & DHT_COLOR) {
      doc_e = DocEntryNewBase(doc, DOCT_FOREGROUND);
      doc_e->attr = tmph->user_data0 & 15;
      DocInsEntry(doc, doc_e);
      return;
    }
  }
  // Color name alone → FOREGROUND (RED, LTBLUE, …) — fallback if hash cold
  color = RVDocColorName(cmd);
  if (color >= 0) {
    doc_e = DocEntryNewBase(doc, DOCT_FOREGROUND);
    doc_e->attr = color;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'F' || cmd[0] == 'f') && (cmd[1] == 'G' || cmd[1] == 'g')) {
    doc_e = DocEntryNewBase(doc, DOCT_FOREGROUND);
    doc_e->attr = DOC_DFT;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr & 15;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'B' || cmd[0] == 'b') && (cmd[1] == 'G' || cmd[1] == 'g')) {
    doc_e = DocEntryNewBase(doc, DOCT_BACKGROUND);
    doc_e->attr = DOC_DFT;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr & 15;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'I' || cmd[0] == 'i') && (cmd[1] == 'D' || cmd[1] == 'd')) {
    doc_e = DocEntryNewBase(doc, DOCT_INDENT);
    doc_e->attr = 0;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'T' || cmd[0] == 't') && (cmd[1] == 'X' || cmd[1] == 'x')) {
    p = cmd + 2;
    tag[0] = 0;
    // Flag run (+CX / -UL) → RVDocPrsFlagsCmp HashFind (not CmpCtrl Lex).
    fi = 0;
    while (*p && *p != ',' && *p != '"' && fi < sizeof(buf) - 1)
      buf[fi++] = *p++;
    buf[fi] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    if (!RVDocExtractQuoted(&p, tag, sizeof(tag))) {
      // Stock T="..." when TAG is keyed (dft may omit positional quote).
      q = p;
      if (!RVDocPrsArgOnce(&q, &fi, tag, sizeof(tag)) || fi != DOCEf_TAG || !tag[0])
        return;
      p = q;
    }
    de_flags = DOCEF_TAG;
    if (doldoc.hash)
      de_flags = doldoc.dft_de_flags[DOCT_TEXT];
    typ = DOCT_TEXT | (doc->settings_head.dft_text_attr << 8);
    if (doldoc.hash)
      typ |= doldoc.dft_type_flags[DOCT_TEXT];
    if (buf[0] && RVDocPrsFlagsCmp(buf, &de_flags, &typ))
      rv_doc_prs_flag_hits++;
    doc_e = DocEntryNewBase(doc, typ);
    doc_e->de_flags = de_flags;
    doc_e->tag = RVDocStrNew(doc, tag);
    doc_e->max_col = StrLen(tag);
    RVDocAttachHtml(doc, doc_e, cmd);
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'L' || cmd[0] == 'l') && (cmd[1] == 'K' || cmd[1] == 'k')) {
    p = cmd + 2;
    tag[0] = 0;
    aux[0] = 0;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (RVDocPrsArgFind(cmd, DOCEf_AUX_STR, aux, sizeof(aux))) {
      // HashFind A="..."
    } else {
      q = RVDocFindArg(cmd, "A");
      if (q) {
        q++;
        // skip '"'
        n = 0;
        while (*q && *q != '"' && n < sizeof(aux) - 1)
          aux[n++] = *q++;
        aux[n] = 0;
      } else {
        // Positional second string
        RVDocExtractQuoted(&p, aux, sizeof(aux));
      }
    }
    if (!tag[0])
      return;
    doc_e = DocEntryNewBase(doc, DOCT_LINK | (DOC_COLOR_LINK << 8));
    doc_e->de_flags = DOCEF_TAG | DOCEF_LINK | DOCEF_UNDERLINE;
    if (aux[0]) {
      doc_e->de_flags |= DOCEF_AUX_STR;
      doc_e->aux_str = RVDocStrNew(doc, aux);
    }
    doc_e->tag = RVDocStrNew(doc, tag);
    doc_e->max_col = 1;
    RVDocAttachHtml(doc, doc_e, cmd);
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'T' || cmd[0] == 't') && (cmd[1] == 'R' || cmd[1] == 'r')) {
    p = cmd + 2;
    tag[0] = 0;
    // Skip flag run (+C / -C etc.)
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (!tag[0])
      StrCpy(tag, "");
    // Display form "+] name" / "-] name"
    if (RVDocCmdHasFlag(cmd + 2, 'C'))
      StrPrint(buf, "-] %s", tag);
    else
      StrPrint(buf, "+] %s", tag);
    doc_e = DocEntryNewBase(doc, DOCT_TREE | (DOC_COLOR_TREE << 8));
    doc_e->de_flags = DOCEF_TAG | DOCEF_TREE | DOCEF_UNDERLINE | DOCEF_CHECK_COLLAPSABLE;
    if (RVDocCmdHasFlag(cmd + 2, 'C'))
      doc_e->de_flags |= DOCEF_CHECKED_COLLAPSED;
    doc_e->tag = RVDocStrNew(doc, buf);
    doc_e->max_col = 1;
    RVDocAttachUserData(doc, doc_e, cmd);
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'B' || cmd[0] == 'b') && (cmd[1] == 'T' || cmd[1] == 't')) {
    // $$BT,"label"$$ or $$BT,"label",LE=n$$
    p = cmd + 2;
    tag[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (!tag[0])
      return;
    doc_e = DocEntryNewBase(doc, DOCT_BTTN | (DOC_COLOR_MACRO << 8));
    doc_e->de_flags = DOCEF_TAG | DOCEF_UNDERLINE;
    doc_e->tag = RVDocStrNew(doc, tag);
    doc_e->max_col = 1;
    if (RVDocPrsArgFind(cmd, DOCEf_LEFT_EXP, aux, sizeof(aux)) && RVDocParseInt(aux, &n) > 0) {
      doc_e->de_flags |= DOCEF_LEFT_EXP;
      doc_e->left_exp = n;
    } else {
      q = cmd;
      while (*q) {
        if (q[0] == 'L' && q[1] == 'E' && q[2] == '=') {
          q += 3;
          if (RVDocParseInt(q, &n) > 0) {
            doc_e->de_flags |= DOCEF_LEFT_EXP;
            doc_e->left_exp = n;
          }
          break;
        }
        q++;
      }
    }
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'D' || cmd[0] == 'd') && (cmd[1] == 'A' || cmd[1] == 'a')) {
    // $$DA,"value"$$ or $$DA,A="Label:%s"$$ (display-only forms subset)
    p = cmd + 2;
    tag[0] = 0;
    aux[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (!RVDocPrsArgFind(cmd, DOCEf_AUX_STR, aux, sizeof(aux))) {
      q = RVDocFindArg(cmd, "A");
      if (q) {
        q++;
        n = 0;
        while (*q && *q != '"' && n < sizeof(aux) - 1)
          aux[n++] = *q++;
        aux[n] = 0;
      }
    }
    if (!tag[0] && aux[0]) {
      // Format-only: show aux as label with empty value placeholder
      StrCpy(tag, "___");
    }
    if (!tag[0])
      return;
    if (aux[0] && StrLen(aux) < sizeof(buf) - 8) {
      // Expand %s once with tag value for display
      p = aux;
      i = 0;
      while (*p && i < sizeof(buf) - 1) {
        if (p[0] == '%' && p[1] == 's') {
          n = 0;
          while (tag[n] && i < sizeof(buf) - 1)
            buf[i++] = tag[n++];
          p += 2;
        } else
          buf[i++] = *p++;
      }
      buf[i] = 0;
    } else
      StrCpy(buf, tag);
    doc_e = DocEntryNewBase(doc, DOCT_DATA | (DOC_COLOR_STR << 8));
    doc_e->de_flags = DOCEF_TAG;
    if (aux[0]) {
      doc_e->de_flags |= DOCEF_AUX_STR;
      doc_e->aux_str = RVDocStrNew(doc, aux);
    }
    doc_e->tag = RVDocStrNew(doc, buf);
    doc_e->max_col = StrLen(buf);
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'C' || cmd[0] == 'c') && (cmd[1] == 'B' || cmd[1] == 'b')) {
    // $$CB,"label"$$ — [ ] / [X] toggle
    p = cmd + 2;
    tag[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (!tag[0])
      StrCpy(tag, "");
    if (RVDocCmdHasFlag(cmd + 2, 'C') || RVDocCmdHasFlag(cmd + 2, 'A'))
      StrPrint(buf, "[X] %s", tag);
    else
      StrPrint(buf, "[ ] %s", tag);
    doc_e = DocEntryNewBase(doc, DOCT_CHECK_BOX | (DOC_COLOR_PMT << 8));
    doc_e->de_flags = DOCEF_TAG | DOCEF_CHECK_COLLAPSABLE;
    if (RVDocCmdHasFlag(cmd + 2, 'C') || RVDocCmdHasFlag(cmd + 2, 'A'))
      doc_e->de_flags |= DOCEF_CHECKED_COLLAPSED;
    doc_e->tag = RVDocStrNew(doc, buf);
    doc_e->max_col = 2;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'M' || cmd[0] == 'm') && (cmd[1] == 'A' || cmd[1] == 'a')) {
    // $$MA,"label",LM="code"$$ — macro link (ExePutS deferred; status print)
    p = cmd + 2;
    tag[0] = 0;
    aux[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (RVDocPrsArgFind(cmd, DOCEf_LEFT_MACRO, aux, sizeof(aux))) {
      // HashFind LM="..."
    } else if (RVDocPrsArgFind(cmd, DOCEf_AUX_STR, aux, sizeof(aux))) {
      // HashFind A="..."
    } else {
      q = RVDocFindArg(cmd, "LM");
      if (q) {
        q++;
        n = 0;
        while (*q && *q != '"' && n < sizeof(aux) - 1)
          aux[n++] = *q++;
        aux[n] = 0;
      } else {
        q = RVDocFindArg(cmd, "A");
        if (q) {
          q++;
          n = 0;
          while (*q && *q != '"' && n < sizeof(aux) - 1)
            aux[n++] = *q++;
          aux[n] = 0;
        }
      }
    }
    if (!tag[0])
      return;
    doc_e = DocEntryNewBase(doc, DOCT_MACRO | (DOC_COLOR_MACRO << 8));
    doc_e->de_flags = DOCEF_TAG | DOCEF_UNDERLINE;
    if (aux[0]) {
      doc_e->de_flags |= DOCEF_LEFT_MACRO | DOCEF_AUX_STR;
      doc_e->aux_str = RVDocStrNew(doc, aux);
      doc_e->left_macro = doc_e->aux_str;
    }
    doc_e->tag = RVDocStrNew(doc, tag);
    doc_e->max_col = 1;
    DocInsEntry(doc, doc_e);
    return;
  }
  // Cheap entry kinds (layout / attr cmds) — no Lex
  if ((cmd[0] == 'P' || cmd[0] == 'p') && (cmd[1] == 'B' || cmd[1] == 'b')) {
    doc_e = DocEntryNewBase(doc, DOCT_PAGE_BREAK | (doc->settings_head.dft_text_attr << 8));
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'C' || cmd[0] == 'c') && (cmd[1] == 'L' || cmd[1] == 'l')) {
    doc_e = DocEntryNewBase(doc, DOCT_CLEAR);
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'P' || cmd[0] == 'p') && (cmd[1] == 'T' || cmd[1] == 't')) {
    p = cmd + 2;
    tag[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    doc_e = DocEntryNewBase(doc, DOCT_PMT | (DOC_COLOR_PMT << 8));
    if (tag[0]) {
      doc_e->de_flags = DOCEF_TAG;
      doc_e->tag = RVDocStrNew(doc, tag);
      doc_e->max_col = StrLen(tag);
    }
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'B' || cmd[0] == 'b') && (cmd[1] == 'K' || cmd[1] == 'k')) {
    doc_e = DocEntryNewBase(doc, DOCT_BLINK);
    doc_e->attr = DOC_DFT;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'I' || cmd[0] == 'i') && (cmd[1] == 'V' || cmd[1] == 'v')) {
    doc_e = DocEntryNewBase(doc, DOCT_INVERT);
    doc_e->attr = DOC_DFT;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'U' || cmd[0] == 'u') && (cmd[1] == 'L' || cmd[1] == 'l')) {
    doc_e = DocEntryNewBase(doc, DOCT_UNDERLINE);
    doc_e->attr = DOC_DFT;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  // AN,"name" — anchor
  if ((cmd[0] == 'A' || cmd[0] == 'a') && (cmd[1] == 'N' || cmd[1] == 'n')) {
    p = cmd + 2;
    tag[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (!tag[0])
      return;
    doc_e = DocEntryNewBase(doc, DOCT_ANCHOR | (DOC_COLOR_ANCHOR << 8));
    doc_e->de_flags = DOCEF_TAG;
    doc_e->tag = RVDocStrNew(doc, tag);
    doc_e->max_col = 0;
    DocInsEntry(doc, doc_e);
    return;
  }
  // MU,"label",LE=n — menu value (button-like)
  if ((cmd[0] == 'M' || cmd[0] == 'm') && (cmd[1] == 'U' || cmd[1] == 'u')) {
    p = cmd + 2;
    tag[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (!tag[0])
      return;
    doc_e = DocEntryNewBase(doc, DOCT_MENU_VAL | (DOC_COLOR_MACRO << 8));
    doc_e->de_flags = DOCEF_TAG | DOCEF_UNDERLINE;
    doc_e->tag = RVDocStrNew(doc, tag);
    doc_e->max_col = 1;
    if (RVDocPrsArgFind(cmd, DOCEf_LEFT_EXP, aux, sizeof(aux)) && RVDocParseInt(aux, &n) > 0) {
      doc_e->de_flags |= DOCEF_LEFT_EXP;
      doc_e->left_exp = n;
    } else {
      q = cmd;
      while (*q) {
        if (q[0] == 'L' && q[1] == 'E' && q[2] == '=') {
          q += 3;
          if (RVDocParseInt(q, &n) > 0) {
            doc_e->de_flags |= DOCEF_LEFT_EXP;
            doc_e->left_exp = n;
          }
          break;
        }
        q++;
      }
    }
    RVDocAttachUserData(doc, doc_e, cmd);
    DocInsEntry(doc, doc_e);
    return;
  }
  // LS,"item" or LS,D="DEFINE" — list display stub
  if ((cmd[0] == 'L' || cmd[0] == 'l') && (cmd[1] == 'S' || cmd[1] == 's')) {
    p = cmd + 2;
    tag[0] = 0;
    aux[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    q = RVDocFindArg(cmd, "D");
    if (q) {
      q++;
      n = 0;
      while (*q && *q != '"' && n < sizeof(aux) - 1)
        aux[n++] = *q++;
      aux[n] = 0;
    }
    if (!tag[0] && aux[0])
      StrPrint(tag, "[%s]", aux);
    else if (!tag[0])
      StrCpy(tag, "[]");
    else if (tag[0] != '[') {
      StrPrint(buf, "[%s]", tag);
      StrCpy(tag, buf);
    }
    doc_e = DocEntryNewBase(doc, DOCT_LST | (DOC_COLOR_DEFINE_STR << 8));
    doc_e->de_flags = DOCEF_TAG | DOCEF_LST;
    if (aux[0]) {
      doc_e->de_flags |= DOCEF_DEFINE;
      doc_e->define_str = RVDocStrNew(doc, aux);
    }
    doc_e->tag = RVDocStrNew(doc, tag);
    doc_e->min_col = 1;
    doc_e->max_col = StrLen(tag);
    DocInsEntry(doc, doc_e);
    return;
  }
  // CM — cursor movement (attr ignored for lite layout; marker only)
  if ((cmd[0] == 'C' || cmd[0] == 'c') && (cmd[1] == 'M' || cmd[1] == 'm')) {
    doc_e = DocEntryNewBase(doc, DOCT_CURSOR_MOVEMENT);
    doc_e->attr = 0;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  // SX / SY — shifted x/y (super/sub display markers)
  if ((cmd[0] == 'S' || cmd[0] == 's') && (cmd[1] == 'X' || cmd[1] == 'x')) {
    doc_e = DocEntryNewBase(doc, DOCT_SHIFTED_X);
    doc_e->attr = 0;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'S' || cmd[0] == 's') && (cmd[1] == 'Y' || cmd[1] == 'y')) {
    doc_e = DocEntryNewBase(doc, DOCT_SHIFTED_Y);
    doc_e->attr = 0;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  // WW / HL / LM / RM / PL — settings cmds (store attr; Recalc honors WW/margins lite)
  if ((cmd[0] == 'W' || cmd[0] == 'w') && (cmd[1] == 'W' || cmd[1] == 'w')) {
    doc_e = DocEntryNewBase(doc, DOCT_WORD_WRAP);
    doc_e->attr = 1;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'H' || cmd[0] == 'h') && (cmd[1] == 'L' || cmd[1] == 'l')) {
    doc_e = DocEntryNewBase(doc, DOCT_HIGHLIGHT);
    doc_e->attr = 1;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'L' || cmd[0] == 'l') && (cmd[1] == 'M' || cmd[1] == 'm')) {
    doc_e = DocEntryNewBase(doc, DOCT_LEFT_MARGIN);
    doc_e->attr = DOC_DFT;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'R' || cmd[0] == 'r') && (cmd[1] == 'M' || cmd[1] == 'm')) {
    doc_e = DocEntryNewBase(doc, DOCT_RIGHT_MARGIN);
    doc_e->attr = DOC_DFT;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  if ((cmd[0] == 'P' || cmd[0] == 'p') && (cmd[1] == 'L' || cmd[1] == 'l')) {
    doc_e = DocEntryNewBase(doc, DOCT_PAGE_LEN);
    doc_e->attr = 66;
    p = cmd + 2;
    while (*p == ' ' || *p == ',')
      p++;
    if (RVDocParseInt(p, &attr) > 0)
      doc_e->attr = attr;
    DocInsEntry(doc, doc_e);
    return;
  }
  // SP,"tag",BI=n — sprite entry + optional bin attach (+ LM= for PsmMenu play/record)
  if ((cmd[0] == 'S' || cmd[0] == 's') && (cmd[1] == 'P' || cmd[1] == 'p')) {
    p = cmd + 2;
    tag[0] = 0;
    aux[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (!tag[0])
      StrCpy(tag, "<SP>");
    if (!RVDocPrsArgFind(cmd, DOCEf_LEFT_MACRO, aux, sizeof(aux))) {
      q = RVDocFindArg(cmd, "LM");
      if (q) {
        q++;
        n = 0;
        while (*q && *q != '"' && n < sizeof(aux) - 1)
          aux[n++] = *q++;
        aux[n] = 0;
      }
    }
    doc_e = DocEntryNewBase(doc, DOCT_SPRITE | (DOC_COLOR_BIN << 8));
    doc_e->de_flags = DOCEF_TAG;
    doc_e->tag = RVDocStrNew(doc, tag);
    doc_e->max_col = StrLen(tag);
    if (aux[0]) {
      doc_e->de_flags |= DOCEF_LEFT_MACRO | DOCEF_AUX_STR;
      doc_e->aux_str = RVDocStrNew(doc, aux);
      doc_e->left_macro = doc_e->aux_str;
    }
    n = 0;
    if (RVDocPrsArgFind(cmd, DOCEf_HAS_BIN, buf, sizeof(buf)) && RVDocParseInt(buf, &n) > 0) {
      doc_e->de_flags |= DOCEF_HAS_BIN;
      doc_e->bin_num = n;
      doc_e->bin_data = DocBinFindNum(doc, n);
      rv_doc_bin_hits++;
    } else {
      q = cmd;
      while (*q) {
        if (q[0] == 'B' && q[1] == 'I' && q[2] == '=') {
          q += 3;
          if (RVDocParseInt(q, &n) > 0) {
            doc_e->de_flags |= DOCEF_HAS_BIN;
            doc_e->bin_num = n;
            doc_e->bin_data = DocBinFindNum(doc, n);
            rv_doc_bin_hits++;
          }
          break;
        }
        q++;
      }
    }
    DocInsEntry(doc, doc_e);
    return;
  }
  // IB,"tag",BI=n — insert-bin display (tag or size); paint is SP→Sprite3.
  if ((cmd[0] == 'I' || cmd[0] == 'i') && (cmd[1] == 'B' || cmd[1] == 'b')) {
    p = cmd + 2;
    tag[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (!tag[0])
      StrCpy(tag, "<IB>");
    doc_e = DocEntryNewBase(doc, DOCT_INS_BIN | (DOC_COLOR_BIN << 8));
    doc_e->de_flags = DOCEF_TAG;
    doc_e->tag = RVDocStrNew(doc, tag);
    doc_e->max_col = StrLen(tag);
    n = 0;
    if (RVDocPrsArgFind(cmd, DOCEf_HAS_BIN, buf, sizeof(buf)) && RVDocParseInt(buf, &n) > 0) {
      doc_e->de_flags |= DOCEF_HAS_BIN;
      doc_e->bin_num = n;
      doc_e->bin_data = DocBinFindNum(doc, n);
      if (doc_e->bin_data && doc_e->bin_data->size > 0) {
        if (!tag[0] || !StrCmp(tag, "<IB>")) {
          StrPrint(buf, "IB:%d", doc_e->bin_data->size);
          Free(doc_e->tag);
          doc_e->tag = RVDocStrNew(doc, buf);
          doc_e->max_col = StrLen(buf);
        }
      }
      rv_doc_bin_hits++;
      rv_doc_ib_hits++;
    } else {
      q = cmd;
      while (*q) {
        if (q[0] == 'B' && q[1] == 'I' && q[2] == '=') {
          q += 3;
          if (RVDocParseInt(q, &n) > 0) {
            doc_e->de_flags |= DOCEF_HAS_BIN;
            doc_e->bin_num = n;
            doc_e->bin_data = DocBinFindNum(doc, n);
            if (doc_e->bin_data && doc_e->bin_data->size > 0) {
              if (!tag[0] || !StrCmp(tag, "<IB>")) {
                StrPrint(buf, "IB:%d", doc_e->bin_data->size);
                Free(doc_e->tag);
                doc_e->tag = RVDocStrNew(doc, buf);
                doc_e->max_col = StrLen(buf);
              }
            }
            rv_doc_bin_hits++;
            rv_doc_ib_hits++;
          }
          break;
        }
        q++;
      }
    }
    DocInsEntry(doc, doc_e);
    return;
  }
  // HX[,flags],len,cols — hex editor stub (layout placeholder; no data bind yet)
  if ((cmd[0] == 'H' || cmd[0] == 'h') && (cmd[1] == 'X' || cmd[1] == 'x')) {
    p = cmd + 2;
    while (*p && (*p == '+' || *p == '-' || (*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z')))
      p++;
    while (*p == ' ' || *p == ',')
      p++;
    n = 16;
    cols = 4;
    if (RVDocParseInt(p, &n) > 0) {
      while (*p && *p != ',')
        p++;
      while (*p == ' ' || *p == ',')
        p++;
      RVDocParseInt(p, &cols);
    }
    if (n < 1)
      n = 1;
    if (cols < 1)
      cols = 1;
    StrPrint(buf, "<HX:%d*%d>", n, cols);
    doc_e = DocEntryNewBase(doc, DOCT_HEX_ED | (DOC_COLOR_BIN << 8));
    doc_e->de_flags = DOCEF_TAG;
    doc_e->tag = RVDocStrNew(doc, buf);
    doc_e->len = n;
    doc_e->hex_ed_width = cols;
    doc_e->max_col = StrLen(buf);
    rv_doc_hx_hits++;
    DocInsEntry(doc, doc_e);
    return;
  }
  // SO,"tag",A="notes" — song marker (aux = notes; no Play yet)
  if ((cmd[0] == 'S' || cmd[0] == 's') && (cmd[1] == 'O' || cmd[1] == 'o')) {
    p = cmd + 2;
    tag[0] = 0;
    aux[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (!RVDocPrsArgFind(cmd, DOCEf_AUX_STR, aux, sizeof(aux))) {
      q = RVDocFindArg(cmd, "A");
      if (q) {
        q++;
        n = 0;
        while (*q && *q != '"' && n < sizeof(aux) - 1)
          aux[n++] = *q++;
        aux[n] = 0;
      }
    }
    if (!tag[0])
      StrCpy(tag, "<SO>");
    doc_e = DocEntryNewBase(doc, DOCT_SONG | (DOC_COLOR_MACRO << 8));
    doc_e->de_flags = DOCEF_TAG;
    doc_e->tag = RVDocStrNew(doc, tag);
    doc_e->max_col = StrLen(tag);
    if (aux[0]) {
      doc_e->de_flags |= DOCEF_AUX_STR;
      doc_e->aux_str = RVDocStrNew(doc, aux);
    }
    rv_doc_song_hits++;
    DocInsEntry(doc, doc_e);
    return;
  }
  // HC,"html" — HTML code blob (invisible on FB; kept for DocSave/ToHtml)
  if ((cmd[0] == 'H' || cmd[0] == 'h') && (cmd[1] == 'C' || cmd[1] == 'c')) {
    p = cmd + 2;
    tag[0] = 0;
    while (*p && *p != ',' && *p != '"')
      p++;
    RVDocExtractQuoted(&p, tag, sizeof(tag));
    if (!tag[0])
      return;
    doc_e = DocEntryNewBase(doc, DOCT_HTML_CODE);
    doc_e->de_flags = DOCEF_TAG;
    doc_e->tag = RVDocStrNew(doc, tag);
    doc_e->max_col = 0;
    rv_doc_hc_hits++;
    DocInsEntry(doc, doc_e);
    return;
  }
  // Unknown — soft skip (CX etc.)
  no_warn i;
}

U0 RVDocInsTextN(CDoc *doc, U8 *tag, I64 len)
{
  U8 buf[256];
  I64 n;
  if (!doc || !tag || len <= 0)
    return;
  while (len > 0) {
    n = len;
    if (n > 255)
      n = 255;
    MemCpy(buf, tag, n);
    buf[n] = 0;
    RVDocInsText(doc, buf);
    tag += n;
    len -= n;
  }
}

CDocEntry *DocPutS(CDoc *doc, U8 *st)
{
  //Parse plain text + $cmd$ into entries. Returns last dollar entry or NULL.
  U8 *ptr, *ptr2, cmd[256];
  I64 j, n;
  CDocEntry *res = NULL;
  U8 tmp[2];
  Bool unlock;
  if (!st || !doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return NULL;
  unlock = DocLock(doc);
  ptr = st;
  while (*ptr) {
    ptr2 = ptr;
    while (*ptr && *ptr != '$' && *ptr != '\n' && *ptr != '\t')
      ptr++;
    if (ptr > ptr2)
      RVDocInsTextN(doc, ptr2, ptr - ptr2);
    if (!*ptr)
      break;
    if (*ptr == '\n') {
      RVDocInsNewLine(doc);
      ptr++;
      continue;
    }
    if (*ptr == '\t') {
      RVDocInsTab(doc);
      ptr++;
      continue;
    }
    // '$'
    ptr++;
    if (*ptr == '$') {
      tmp[0] = '$';
      tmp[1] = 0;
      RVDocInsText(doc, tmp);
      ptr++;
      continue;
    }
    ptr2 = ptr;
    while (*ptr && *ptr != '$')
      ptr++;
    n = ptr - ptr2;
    if (n <= 0) {
      tmp[0] = '$';
      tmp[1] = 0;
      RVDocInsText(doc, tmp);
      if (*ptr == '$')
        ptr++;
      continue;
    }
    if (n >= sizeof(cmd))
      n = sizeof(cmd) - 1;
    MemCpy(cmd, ptr2, n);
    cmd[n] = 0;
    j = DocSize(doc);
    RVDocPrsDollarCmd(doc, cmd);
    if (DocSize(doc) > j)
      res = doc->cur_entry->last;
    if (*ptr == '$')
      ptr++;
  }
  if (unlock)
    DocUnlock(doc);
  return res;
}

U0 DocLoad(CDoc *doc, U8 *src2, I64 size)
{
  U8 *src, *p;
  I64 text_len, rem, hdr;
  CDocBin *tmpb;
  if (!doc || !src2 || size <= 0)
    return;
  // Text until first NUL; trailing bytes are packed CDocBin blobs (Adam DocFile).
  text_len = 0;
  while (text_len < size && src2[text_len])
    text_len++;
  src = MAlloc(text_len + 1, doc->mem_task);
  MemCpy(src, src2, text_len);
  src[text_len] = 0;
  DocPutS(doc, src);
  Free(src);
  hdr = offset(CDocBin.end) - offset(CDocBin.start);
  if (text_len + 1 < size && hdr > 0) {
    p = src2 + text_len + 1;
    rem = size - (text_len + 1);
    while (rem >= hdr) {
      tmpb = CAlloc(sizeof(CDocBin), doc->mem_task);
      MemCpy(&tmpb->start, p, hdr);
      p += hdr;
      rem -= hdr;
      if (tmpb->size > 0) {
        if (rem < tmpb->size) {
          Free(tmpb);
          break;
        }
        tmpb->data = MAlloc(tmpb->size, doc->mem_task);
        MemCpy(tmpb->data, p, tmpb->size);
        p += tmpb->size;
        rem -= tmpb->size;
      }
      QueIns(tmpb, doc->bin_head.last);
      if (tmpb->num >= doc->cur_bin_num)
        doc->cur_bin_num = tmpb->num + 1;
      rv_doc_bin_hits++;
    }
    DocBinsValidate(doc);
  }
  DocTop(doc);
}

CDocEntry *DocPrint(CDoc *doc = NULL, U8 *fmt,...)
{
  //Stock DocPutS.HC DocPrint — StrPrintJoin then DocPutS (Psalmody PopUpDuration LE=%d).
  U8 *buf;
  CDocEntry *res;
  if (!fmt)
    return NULL;
  buf = StrPrintJoin(NULL, fmt, argc, argv);
  if (!buf)
    return NULL;
  if (!doc) {
    RVDocPutS(buf);
    Free(buf);
    return NULL;
  }
  if (doc->doc_signature != DOC_SIGNATURE_VAL) {
    Free(buf);
    return NULL;
  }
  res = DocPutS(doc, buf);
  Free(buf);
  return res;
}

CDocEntry *DocPrintF(CDoc *doc, U8 *fmt, I64 a)
{
  // Fixed-arity Soft Call bridge into stock DocPrint vararg.
  // True guest DocPrint Soft Call uses CALL_IMPORT remat LEA argv (OptPass_RV).
  return DocPrint(doc, fmt, a);
}

I64 DocPrintStockProbe(CDoc *doc)
{
  // 1-arg host-only bisect helper (Soft Call proof uses guest DocPrintF).
  I64 n0, n1;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return 3;
  n0 = DocSize(doc);
  DocPrint(doc, "%d", 8);
  n1 = DocSize(doc);
  if (n1 <= n0)
    return 4;
  return 8;
}

public Bool DocCursor(Bool show = OFF, CDoc *doc = NULL)
{
  //TempleOS DocCursor soft — toggle DOCf_HIDE_CURSOR when a DocPut exists.
  if (!doc && !(doc = DocPut))
    return FALSE;
  return !LBEqu(&doc->flags, DOCf_HIDE_CURSOR, !show);
}

U0 DocClear(CDoc *doc = NULL, Bool clear_holds = FALSE)
{
  //TempleOS DocClear — stock inserts $$CL$$ then DocRecalc→DocDelToEntry.
  // RV: delete entries directly (put_doc lite queues were uninit; $$CL$$ Recalc hung).
  CDocEntry *doc_e, *doc_e2;
  I64 guard = 0;
  Bool unlock;
  if (!doc && !(doc = DocPut))
    return;
  unlock = DocLock(doc);
  doc_e = doc->head.next;
  while (doc_e && doc_e != doc && ++guard < 100000) {
    doc_e2 = doc_e->next;
    if (clear_holds && (doc_e->de_flags & DOCEF_HOLD)) {
      doc_e = doc_e2;
      continue;
    }
    DocEntryDel(doc, doc_e);
    doc_e = doc_e2;
  }
  doc->head.next = doc->head.last = doc;
  doc->cur_entry = doc;
  doc->cur_col = 0;
  if (unlock)
    DocUnlock(doc);
  DocRecalc(doc);
}

CDocEntry *DocPutLine(CDoc *doc, CDocEntry *doc_e)
{
  no_warn doc;
  no_warn doc_e;
  return NULL;
}

U0 RVDocEmitDollarCmd(U8 **pdst, U8 *cmd)
{
  I64 n;
  U8 *dst;
  if (!pdst || !*pdst || !cmd)
    return;
  dst = *pdst;
  n = StrLen(cmd);
  *dst++ = '$';
  MemCpy(dst, cmd, n);
  dst += n;
  *dst++ = '$';
  *pdst = dst;
}

U8 *DocSave(CDoc *doc, I64 *_size = NULL)
{
  // Plain $$ re-emit of RVDoc entry kinds + trailing CDocBin blobs.
  CDocEntry *doc_e;
  CDocBin *b;
  Bool unlock;
  I64 cnt = 1, n, hdr;
  U8 *res, *dst, *tag, *name, tmp[192];
  if (_size)
    *_size = 0;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return NULL;
  unlock = DocLock(doc);
  DocBinsValidate(doc);
  hdr = offset(CDocBin.end) - offset(CDocBin.start);
  doc_e = doc->head.next;
  while (doc_e != doc) {
    tag = doc_e->tag;
    switch (doc_e->type_u8) {
      case DOCT_SOFT_NEW_LINE :
      case DOCT_CURSOR :
      break;
      case DOCT_NEW_LINE :
      case DOCT_TAB :
      case DOCT_PAGE_BREAK :
      cnt++;
      break;
      case DOCT_TEXT :
      if (doc_e->de_flags & DOCEF_HTML_LINK && doc_e->html_link) {
        cnt += 24;
        if (tag)
          cnt += StrLen(tag);
        cnt += StrLen(doc_e->html_link) + 8;
      } else if (tag) {
        cnt += StrLen(tag);
        n = 0;
        while (tag[n]) {
          if (tag[n] == '$')
            cnt++;
          n++;
        }
      }
      break;
      case DOCT_LINK :
      case DOCT_TREE :
      case DOCT_BTTN :
      case DOCT_DATA :
      case DOCT_CHECK_BOX :
      case DOCT_MACRO :
      case DOCT_PMT :
      case DOCT_ANCHOR :
      case DOCT_MENU_VAL :
      case DOCT_LST :
      case DOCT_SPRITE :
      case DOCT_INS_BIN :
      case DOCT_HEX_ED :
      case DOCT_SONG :
      case DOCT_HTML_CODE :
      cnt += 24;
      if (tag)
        cnt += StrLen(tag);
      if (doc_e->aux_str)
        cnt += StrLen(doc_e->aux_str) + 8;
      if (doc_e->html_link)
        cnt += StrLen(doc_e->html_link) + 8;
      break;
      case DOCT_FOREGROUND :
      case DOCT_BACKGROUND :
      case DOCT_INDENT :
      case DOCT_BLINK :
      case DOCT_INVERT :
      case DOCT_UNDERLINE :
      case DOCT_CLEAR :
      case DOCT_WORD_WRAP :
      case DOCT_HIGHLIGHT :
      case DOCT_LEFT_MARGIN :
      case DOCT_RIGHT_MARGIN :
      case DOCT_PAGE_LEN :
      case DOCT_SHIFTED_X :
      case DOCT_SHIFTED_Y :
      case DOCT_CURSOR_MOVEMENT :
      cnt += 16;
      break;
      default:
      break;
    }
    doc_e = doc_e->next;
  }
  for (b = doc->bin_head.next; b != &doc->bin_head; b = b->next)
    if (b->use_cnt > b->tmp_use_cnt)
      cnt += hdr + b->size;
  res = MAlloc(cnt + 32, doc->mem_task);
  if (!res) {
    if (unlock)
      DocUnlock(doc);
    return NULL;
  }
  dst = res;
  doc_e = doc->head.next;
  while (doc_e != doc) {
    tag = doc_e->tag;
    switch (doc_e->type_u8) {
      case DOCT_SOFT_NEW_LINE :
      case DOCT_CURSOR :
      break;
      case DOCT_NEW_LINE :
      *dst++ = '\n';
      break;
      case DOCT_TAB :
      *dst++ = '\t';
      break;
      case DOCT_PAGE_BREAK :
      *dst++ = '\f';
      break;
      case DOCT_TEXT :
      if (doc_e->de_flags & DOCEF_HTML_LINK && doc_e->html_link) {
        if (!tag)
          tag = "";
        StrPrint(tmp, "TX,\"%s\",HTML=\"%s\"", tag, doc_e->html_link);
        RVDocEmitDollarCmd(&dst, tmp);
      } else if (tag) {
        while (*tag) {
          *dst++ = *tag;
          if (*tag == '$')
            *dst++ = '$';
          tag++;
        }
      }
      break;
      case DOCT_FOREGROUND :
      if (doc_e->attr == DOC_DFT)
        StrPrint(tmp, "FG");
      else
        StrPrint(tmp, "FG,%d", doc_e->attr & 15);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_BACKGROUND :
      if (doc_e->attr == DOC_DFT)
        StrPrint(tmp, "BG");
      else
        StrPrint(tmp, "BG,%d", doc_e->attr & 15);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_INDENT :
      StrPrint(tmp, "ID,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_BLINK :
      if (doc_e->attr == DOC_DFT)
        StrPrint(tmp, "BK");
      else
        StrPrint(tmp, "BK,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_INVERT :
      if (doc_e->attr == DOC_DFT)
        StrPrint(tmp, "IV");
      else
        StrPrint(tmp, "IV,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_UNDERLINE :
      if (doc_e->attr == DOC_DFT)
        StrPrint(tmp, "UL");
      else
        StrPrint(tmp, "UL,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_CLEAR :
      StrPrint(tmp, "CL");
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_PMT :
      if (tag && tag[0])
        StrPrint(tmp, "PT,\"%s\"", tag);
      else
        StrPrint(tmp, "PT");
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_LINK :
      if (!tag)
        tag = "";
      if (doc_e->de_flags & DOCEF_HTML_LINK && doc_e->html_link) {
        if (doc_e->de_flags & DOCEF_AUX_STR && doc_e->aux_str)
          StrPrint(tmp, "LK,\"%s\",A=\"%s\",HTML=\"%s\"", tag, doc_e->aux_str, doc_e->html_link);
        else
          StrPrint(tmp, "LK,\"%s\",HTML=\"%s\"", tag, doc_e->html_link);
      } else if (doc_e->de_flags & DOCEF_AUX_STR && doc_e->aux_str)
        StrPrint(tmp, "LK,\"%s\",A=\"%s\"", tag, doc_e->aux_str);
      else
        StrPrint(tmp, "LK,\"%s\"", tag);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_TREE :
      name = tag;
      if (tag && tag[0] && tag[1] == ']' && tag[2] == ' ')
        name = tag + 3;
      if (!name)
        name = "";
      if (doc_e->de_flags & DOCEF_CHECKED_COLLAPSED)
        StrPrint(tmp, "TR+C,\"%s\"", name);
      else
        StrPrint(tmp, "TR,\"%s\"", name);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_BTTN :
      if (!tag)
        tag = "";
      if (doc_e->de_flags & DOCEF_LEFT_EXP)
        StrPrint(tmp, "BT,\"%s\",LE=%d", tag, doc_e->left_exp);
      else
        StrPrint(tmp, "BT,\"%s\"", tag);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_DATA :
      if (!tag)
        tag = "";
      if (doc_e->de_flags & DOCEF_AUX_STR && doc_e->aux_str)
        StrPrint(tmp, "DA,\"%s\",A=\"%s\"", tag, doc_e->aux_str);
      else
        StrPrint(tmp, "DA,\"%s\"", tag);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_CHECK_BOX :
      name = tag;
      if (tag && tag[0] == '[' && tag[2] == ']' && tag[3] == ' ')
        name = tag + 4;
      if (!name)
        name = "";
      if (doc_e->de_flags & DOCEF_CHECKED_COLLAPSED)
        StrPrint(tmp, "CB+C,\"%s\"", name);
      else
        StrPrint(tmp, "CB,\"%s\"", name);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_MACRO :
      if (!tag)
        tag = "";
      if (doc_e->de_flags & DOCEF_AUX_STR && doc_e->aux_str)
        StrPrint(tmp, "MA,\"%s\",LM=\"%s\"", tag, doc_e->aux_str);
      else
        StrPrint(tmp, "MA,\"%s\"", tag);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_ANCHOR :
      if (!tag)
        tag = "";
      StrPrint(tmp, "AN,\"%s\"", tag);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_MENU_VAL :
      if (!tag)
        tag = "";
      if (doc_e->de_flags & DOCEF_LEFT_EXP)
        StrPrint(tmp, "MU,\"%s\",LE=%d", tag, doc_e->left_exp);
      else
        StrPrint(tmp, "MU,\"%s\"", tag);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_LST :
      if (!tag)
        tag = "[]";
      StrPrint(tmp, "LS,\"%s\"", tag);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_SPRITE :
      if (!tag)
        tag = "<SP>";
      if (doc_e->de_flags & DOCEF_HAS_BIN)
        StrPrint(tmp, "SP,\"%s\",BI=%d", tag, doc_e->bin_num);
      else
        StrPrint(tmp, "SP,\"%s\"", tag);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_INS_BIN :
      if (!tag)
        tag = "<IB>";
      if (doc_e->de_flags & DOCEF_HAS_BIN)
        StrPrint(tmp, "IB,\"%s\",BI=%d", tag, doc_e->bin_num);
      else
        StrPrint(tmp, "IB,\"%s\"", tag);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_HEX_ED :
      StrPrint(tmp, "HX,%d,%d", doc_e->len, doc_e->hex_ed_width);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_SONG :
      if (!tag)
        tag = "<SO>";
      if (doc_e->de_flags & DOCEF_AUX_STR && doc_e->aux_str)
        StrPrint(tmp, "SO,\"%s\",A=\"%s\"", tag, doc_e->aux_str);
      else
        StrPrint(tmp, "SO,\"%s\"", tag);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_HTML_CODE :
      if (!tag)
        tag = "";
      StrPrint(tmp, "HC,\"%s\"", tag);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_WORD_WRAP :
      StrPrint(tmp, "WW,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_HIGHLIGHT :
      StrPrint(tmp, "HL,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_LEFT_MARGIN :
      StrPrint(tmp, "LM,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_RIGHT_MARGIN :
      StrPrint(tmp, "RM,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_PAGE_LEN :
      StrPrint(tmp, "PL,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_SHIFTED_X :
      StrPrint(tmp, "SX,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_SHIFTED_Y :
      StrPrint(tmp, "SY,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      case DOCT_CURSOR_MOVEMENT :
      StrPrint(tmp, "CM,%d", doc_e->attr);
      RVDocEmitDollarCmd(&dst, tmp);
      break;
      default:
      break;
    }
    doc_e = doc_e->next;
  }
  *dst++ = 0;
  b = doc->bin_head.next;
  while (b != &doc->bin_head) {
    if (b->use_cnt > b->tmp_use_cnt) {
      MemCpy(dst, &b->start, hdr);
      dst += hdr;
      if (b->size && b->data) {
        MemCpy(dst, b->data, b->size);
        dst += b->size;
      }
    }
    b = b->next;
  }
  if (_size)
    *_size = dst(I64) - res(I64);
  if (unlock)
    DocUnlock(doc);
  return res;
}

Bool DocWrite(CDoc *doc, Bool prompt = FALSE)
{
  // Lite Write: DocSave → FileWrite. prompt/DocForm + bins/sprites still open.
  U8 *buf;
  I64 size = 0, wrote;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return FALSE;
  if (prompt)
    return FALSE;
  if (!doc->filename.name[0] || !StrCmp(doc->filename.name, "NONAME.DD"))
    return FALSE;
  buf = DocSave(doc, &size);
  if (!buf)
    return FALSE;
  wrote = FileWrite(doc->filename.name, buf, size);
  Free(buf);
  return wrote >= 0;
}

CDoc *DocRead(U8 *name = NULL, I64 flags = 0)
{
  //Fetch doc from disk (FileRead → DocLoad).
  CDoc *doc;
  U8 *src;
  I64 size = 0;
  doc = DocNew(name);
  if (!doc)
    return NULL;
  doc->flags |= flags;
  if (name && name[0])
    StrCpy(doc->filename.name, name);
  src = FileRead(doc->filename.name, &size, NULL);
  if (src) {
    DocLoad(doc, src, size);
    Free(src);
  }
  return doc;
}

U0 DocUndoDel(CDoc *doc, CDocUndo *u)
{
  no_warn doc;
  if (!u)
    return;
  Free(u->body);
  Free(u);
}

U0 DocUndoCntSet(CDoc *doc)
{
  CDocUndo *u;
  I64 n = 0;
  if (!doc)
    return;
  u = doc->undo_head.next;
  while (u != &doc->undo_head) {
    n++;
    u = u->next;
  }
  doc->undo_cnt = n;
}

Bool DocCaptureUndo(CDoc *doc, Bool force = FALSE)
{
  //Lite undo: single DocSave snapshot when ALLOW_UNDO.
  Bool res = FALSE, unlock;
  CDocUndo *u, *u2;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return FALSE;
  if (!(doc->flags & DOCF_ALLOW_UNDO))
    return FALSE;
  unlock = DocLock(doc);
  if (force || doc->flags & DOCF_UNDO_DIRTY || !doc->undo_cnt) {
    u = doc->undo_head.next;
    while (u != &doc->undo_head) {
      u2 = u->next;
      QueRem(u);
      DocUndoDel(doc, u);
      u = u2;
    }
    u = CAlloc(sizeof(CDocUndo), doc->mem_task);
    // Unchecked before: a failed CAlloc here faulted on the next store rather than
    // degrading. Undo is a convenience — dropping a snapshot when the heap is tight
    // is correct behaviour, crashing the REPL is not. (DocSave below already guards
    // its own MAlloc this way.)
    if (!u) {
      if (unlock)
        DocUnlock(doc);
      return FALSE;
    }
    u->time_stamp = GetTSC;
    u->body = DocSave(doc, &u->size);
    u->doc_flags = doc->flags;
    QueIns(u, doc->undo_head.last);
    doc->flags &= ~DOCF_UNDO_DIRTY;
    DocUndoCntSet(doc);
    res = TRUE;
  }
  if (unlock)
    DocUnlock(doc);
  return res;
}

U0 DocUndoRestore(CDoc *doc)
{
  Bool unlock;
  CDocUndo *u;
  I64 flags;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return;
  unlock = DocLock(doc);
  u = doc->undo_head.last;
  if (u != &doc->undo_head && u->body) {
    QueRem(u);
    flags = u->doc_flags;
    DocRst(doc, TRUE);
    doc->flags = flags & ~DOCF_NO_CURSOR;
    DocLoad(doc, u->body, u->size);
    DocUndoDel(doc, u);
    DocUndoCntSet(doc);
    doc->flags &= ~DOCF_UNDO_DIRTY;
  }
  if (unlock)
    DocUnlock(doc);
}
U0 DocEdInsChar(CDoc *doc, I64 ch);
U0 DocEdBackspace(CDoc *doc);
Bool RVDocActivate(CDoc *doc, CDocEntry *doc_e);
Bool RVDocToggleCheck(CDoc *doc, CDocEntry *doc_e);
Bool DocEd(CDoc *doc, I64 dof_flags = 0)
{
  //Lite DocEd enables undo. Modal View-lite when DOCF_FORM or inject queue set
  // (Adam DocEd = put/display swap + GetKey until ESC). Smoke-safe: no inject → no block.
  I64 ch, sc, steps, idle;
  CDocEntry *doc_e;
  Bool res = TRUE;
  no_warn dof_flags;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return FALSE;
  doc->flags |= DOCF_ALLOW_UNDO;
  if (dof_flags & DOF_DONT_SHOW)
    return TRUE;
  if (!(doc->flags & DOCF_FORM) && rv_doc_ed_key_n <= 0)
    return TRUE;
  if (!(dof_flags & DOF_DONT_HOME))
    DocTop(doc);
  DocRecalc(doc);
  rv_doc_ed_modal_hits++;
  rv_doc_ed_result = DOCM_CANCEL;
  rv_doc_ed_key_i = 0;
  steps = 0;
  idle = 0;
  // Inject-only sessions never block on ScanMsg/Yield (win smoke headless).
  while (steps < RV_DOC_ED_MAX_STEPS) {
    steps++;
    ch = -1;
    if (rv_doc_ed_key_i < rv_doc_ed_key_n) {
      ch = rv_doc_ed_keys[rv_doc_ed_key_i++];
      idle = 0;
    } else if (rv_doc_ed_key_n > 0) {
      // Inject queue drained — end modal (smoke / scripted DocForm).
      break;
    } else if (ScanMsg(&ch, &sc, 1 << MSG_KEY_DOWN) == MSG_KEY_DOWN) {
      idle = 0;
    } else {
      idle++;
      if (idle > 2)
        break;
      continue;
    }
    if (ch == CH_ESC || ch == CH_SHIFT_ESC) {
      res = (ch == CH_ESC);
      break;
    }
    if (ch == '\n' || ch == '\r') {
      doc_e = doc->cur_entry;
      if (doc_e && doc_e != doc) {
        if (doc_e->type_u8 == DOCT_BTTN || doc_e->type_u8 == DOCT_MENU_VAL) {
          if (doc_e->de_flags & DOCEF_LEFT_EXP)
            rv_doc_ed_result = doc_e->left_exp;
          else
            rv_doc_ed_result = 1;
          res = TRUE;
          break;
        }
        if (RVDocActivate(doc, doc_e)) {
          // stay in modal for CB/TREE; OK button exits
        }
      }
      continue;
    }
    if (ch == '\t') {
      doc_e = doc->cur_entry;
      if (!doc_e || doc_e == doc)
        doc_e = doc->head.next;
      else
        doc_e = doc_e->next;
      while (doc_e != doc) {
        if (doc_e->type_u8 == DOCT_DATA || doc_e->type_u8 == DOCT_CHECK_BOX || doc_e->type_u8 == DOCT_BTTN || doc_e->type_u8 == DOCT_MENU_VAL || doc_e->type_u8 == DOCT_LST || doc_e->type_u8 == DOCT_LINK) {
          doc->cur_entry = doc_e;
          doc->cur_col = doc_e->min_col;
          break;
        }
        doc_e = doc_e->next;
      }
      continue;
    }
    if (ch == ' ') {
      doc_e = doc->cur_entry;
      if (doc_e && doc_e->type_u8 == DOCT_CHECK_BOX)
        RVDocToggleCheck(doc, doc_e);
      continue;
    }
    if (ch == 8 || ch == 127)
      DocEdBackspace(doc);
    else if (ch >= 32 && ch < 127)
      DocEdInsChar(doc, ch);
  }
  rv_doc_ed_key_n = 0;
  rv_doc_ed_key_i = 0;
  return res;
}

U0 DocEdKeyInject(I64 ch)
{
  if (rv_doc_ed_key_n >= RV_DOC_ED_KEY_MAX)
    return;
  rv_doc_ed_keys[rv_doc_ed_key_n++] = ch;
}

U0 DocEdKeyInjectClear()
{
  rv_doc_ed_key_n = 0;
  rv_doc_ed_key_i = 0;
}

Bool DocForm(U8 *_d = NULL, U8 *class_name = NULL, I64 dof_flags = 0, U8 *header = NULL, U8 *footer = NULL)
{
  //DocForm: class-meta when HTT_CLASS+format meta exist; else Lex-lite DA/CB/BT + DocEd.
  CDoc *doc;
  CDocEntry *doc_e;
  CHashClass *tmpc;
  CMemberLst *ml;
  CMemberLstMeta *meta;
  Bool res = FALSE, *chk_ptr;
  I64 *val_ptr;
  U8 line[96], *p, *format;
  rv_doc_form_lex_hits++;
  // ---- class-meta path (MemberMeta format → DocPutS; DocEd modal) ----
  if (_d && class_name && Fs && Fs->hash_table && (tmpc = HashFind(class_name, Fs->hash_table, HTT_CLASS))) {
    doc = DocNew("FORM.DD");
    if (!doc)
      return FALSE;
    doc->flags |= DOCF_FORM | DOCF_ALLOW_UNDO | DOCF_OVERSTRIKE;
    if (dof_flags & DOF_SIZE_MIN)
      doc->flags |= DOCF_SIZE_MIN;
    if (header)
      DocPutS(doc, header);
    ml = tmpc->member_lst_and_root;
    while (ml) {
      format = NULL;
      meta = ml->meta;
      while (meta) {
        if (!StrCmp(meta->str, "format")) {
          format = meta->user_data(U8 *);
          break;
        }
        meta = meta->next;
      }
      if (format && (doc_e = DocPutS(doc, format))) {
        doc_e->data = _d + ml->offset;
        if (doc_e->type_u8 == DOCT_DATA)
          doc_e->raw_type = RT_I64;
      }
      ml = ml->next;
    }
    DocPutS(doc, "$$BT,\"OK\",LE=1$$\n$$BT,\"Cancel\",LE=-1$$\n");
    if (footer)
      DocPutS(doc, footer);
    DocRecalc(doc);
    DocTop(doc);
    if (DocEd(doc, dof_flags)) {
      res = TRUE;
      if (rv_doc_ed_result == DOCM_CANCEL || rv_doc_ed_result < 0)
        res = FALSE;
      if (res) {
        doc_e = doc->head.next;
        ml = tmpc->member_lst_and_root;
        while (doc_e != doc && ml) {
          format = NULL;
          meta = ml->meta;
          while (meta) {
            if (!StrCmp(meta->str, "format")) {
              format = meta->user_data(U8 *);
              break;
            }
            meta = meta->next;
          }
          if (format) {
            if (doc_e->type_u8 == DOCT_DATA && doc_e->data)
              *(_d + ml->offset)(I64 *) = *doc_e->data(I64 *);
            if (doc_e->type_u8 == DOCT_CHECK_BOX)
              *(_d + ml->offset)(Bool *) = !!(doc_e->de_flags & DOCEF_CHECKED_COLLAPSED);
            ml = ml->next;
          }
          doc_e = doc_e->next;
        }
      }
    }
    DocDel(doc);
    return res;
  }
  // ---- Lex-lite (no class HashFind): I64 at +0, Bool at +8 ----
  doc = DocNew("FORM.DD");
  if (!doc)
    return FALSE;
  doc->flags |= DOCF_FORM | DOCF_ALLOW_UNDO;
  if (dof_flags & DOF_SIZE_MIN)
    doc->flags |= DOCF_SIZE_MIN;
  // DocPutS for DolDoc templates — DocPrint→StrPrintJoin treats %s/%d as
  // printf (argc=0 → throw('StrPrint') → unhandled Panic). Same shape as
  // class-meta / RVDocFormBuildDemo. (Soft-skip mislabeled this "postinc".)
  if (header)
    DocPutS(doc, header);
  else
    DocPutS(doc, "$$TX,\"DocForm\"$$\n");
  DocPutS(doc, "$$DA,A=\"Value:%s\"$$\n");
  doc_e = doc->cur_entry->last;
  val_ptr = NULL;
  if (_d) {
    val_ptr = _d(I64 *);
    if (doc_e && doc_e->type_u8 == DOCT_DATA) {
      doc_e->data = val_ptr;
      StrPrint(line, "Value:%d", *val_ptr);
      Free(doc_e->tag);
      doc_e->tag = RVDocStrNew(doc, line);
      doc_e->max_col = StrLen(line);
    }
  }
  DocPutS(doc, "$$CB,\"Check\"$$\n");
  doc_e = doc->cur_entry->last;
  chk_ptr = NULL;
  if (_d) {
    chk_ptr = (_d + 8)(Bool *);
    if (doc_e && doc_e->type_u8 == DOCT_CHECK_BOX && *chk_ptr) {
      doc_e->de_flags |= DOCEF_CHECKED_COLLAPSED;
      Free(doc_e->tag);
      doc_e->tag = RVDocStrNew(doc, "[X] Check");
    }
  }
  DocPutS(doc, "$$BT,\"OK\",LE=1$$\n$$BT,\"Cancel\",LE=-1$$\n");
  if (footer)
    DocPutS(doc, footer);
  DocRecalc(doc);
  DocTop(doc);
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->type_u8 == DOCT_DATA) {
      doc->cur_entry = doc_e;
      break;
    }
    doc_e = doc_e->next;
  }
  if (DocEd(doc, dof_flags)) {
    res = TRUE;
    if (rv_doc_ed_result == DOCM_CANCEL || rv_doc_ed_result < 0)
      res = FALSE;
    if (res && val_ptr) {
      doc_e = doc->head.next;
      while (doc_e != doc) {
        if (doc_e->type_u8 == DOCT_DATA && doc_e->tag) {
          p = doc_e->tag;
          while (*p && *p != ':')
            p++;
          if (*p == ':')
            p++;
          while (*p == ' ')
            p++;
          *val_ptr = 0;
          while (*p >= '0' && *p <= '9') {
            *val_ptr = *val_ptr * 10 + (*p - '0');
            p++;
          }
        }
        if (doc_e->type_u8 == DOCT_CHECK_BOX && chk_ptr)
          *chk_ptr = ToBool(doc_e->de_flags & DOCEF_CHECKED_COLLAPSED);
        doc_e = doc_e->next;
      }
    }
  }
  DocDel(doc);
  return res;
}

I64 DocMenu(CDoc *m, I64 dof_flags = 0)
{
  //Menu chooser lite: modal DocEd; returns LE of selected MU/BT or DOCM_CANCEL.
  I64 res = DOCM_CANCEL;
  CDocEntry *doc_e;
  if (!m || m->doc_signature != DOC_SIGNATURE_VAL)
    return DOCM_CANCEL;
  m->flags |= DOCF_FORM;
  m->desc = 'Menu';
  if (!(dof_flags & DOF_DONT_HOME))
    DocTop(m);
  if (DocEd(m, dof_flags)) {
    if (rv_doc_ed_result != DOCM_CANCEL)
      res = rv_doc_ed_result;
    else {
      doc_e = m->cur_entry;
      if (doc_e && doc_e != m && (doc_e->de_flags & DOCEF_LEFT_EXP))
        res = doc_e->left_exp;
    }
  }
  return res;
}

U0 DocEdInsChar(CDoc *doc, I64 ch)
{
  //Insert one char at insert point (Term typing / body sync).
  CDocEntry *last;
  U8 *nt, one[2];
  I64 l;
  Bool unlock;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return;
  if (ch == '\r')
    return;
  DocCaptureUndo(doc, FALSE);
  unlock = DocLock(doc);
  if (ch == '\n')
    RVDocInsNewLine(doc);
  else if (ch == '\t')
    RVDocInsTab(doc);
  else if (ch >= 32 && ch < 127) {
    last = doc->cur_entry;
    if (last && last != doc)
      last = last->last;
    else
      last = doc->head.last;
    if (last && last != doc && last->type_u8 == DOCT_TEXT && last->tag) {
      l = StrLen(last->tag);
      nt = MAlloc(l + 2, doc->mem_task);
      MemCpy(nt, last->tag, l);
      nt[l] = ch;
      nt[l + 1] = 0;
      Free(last->tag);
      last->tag = nt;
      last->max_col = l + 1;
      doc->cur_entry = last->next;
      doc->cur_col = 0;
    } else {
      one[0] = ch;
      one[1] = 0;
      RVDocInsText(doc, one);
    }
  }
  doc->flags |= DOCF_UNDO_DIRTY;
  if (unlock)
    DocUnlock(doc);
}

U0 DocEdBackspace(CDoc *doc)
{
  //Delete one char / NEW_LINE / TAB before insert point.
  CDocEntry *doc_e;
  I64 l;
  Bool unlock;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return;
  DocCaptureUndo(doc, FALSE);
  unlock = DocLock(doc);
  doc_e = doc->cur_entry;
  if (!doc_e || doc_e == doc)
    doc_e = doc->head.last;
  else
    doc_e = doc_e->last;
  if (!doc_e || doc_e == doc) {
    if (unlock)
      DocUnlock(doc);
    return;
  }
  if (doc_e->type_u8 == DOCT_TEXT && doc_e->tag) {
    l = StrLen(doc_e->tag);
    if (l <= 1) {
      doc->cur_entry = doc_e->next;
      DocEntryDel(doc, doc_e);
    } else {
      doc_e->tag[l - 1] = 0;
      doc_e->max_col = l - 1;
      doc->cur_entry = doc_e->next;
      doc->cur_col = 0;
    }
  } else if (doc_e->type_u8 == DOCT_NEW_LINE || doc_e->type_u8 == DOCT_TAB || doc_e->type_u8 == DOCT_SOFT_NEW_LINE) {
    doc->cur_entry = doc_e->next;
    DocEntryDel(doc, doc_e);
  }
  doc->flags |= DOCF_UNDO_DIRTY;
  if (unlock)
    DocUnlock(doc);
}

Bool DocRecalc(CDoc *doc, I64 recalc_flags = RECALCt_NORMAL)
{
  //Assign x/y, apply tree collapse → DOCEF_SKIP, update max_y.
  CDocEntry *doc_e, *doc_e2;
  CDocSettings *s;
  I64 x, y, indent, cur_attr, fg, bg, j, i, guard;
  I64 blink, invert, ul;
  Bool tree_collapsed;
  Bool unlock;
  no_warn recalc_flags;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return FALSE;
  unlock = DocLock(doc);
  s = &doc->settings_head;
  indent = 0;
  x = 0;
  y = 0;
  blink = invert = ul = 0;
  cur_attr = s->dft_text_attr;
  fg = cur_attr & 15;
  bg = (cur_attr >> 4) & 15;
  doc->min_x = doc->min_y = 0;
  doc->max_x = doc->max_y = 0;
  // Clear prior SKIP from trees
  doc_e = doc->head.next;
  guard = 0;
  while (doc_e && doc_e != doc) {
    doc_e->de_flags &= ~DOCEF_SKIP;
    doc_e = doc_e->next;
    if (++guard > 100000)
      break;
  }
  doc_e = doc->head.next;
  guard = 0;
  while (doc_e && doc_e != doc) {
    if (++guard > 100000)
      break;
    if (doc_e->de_flags & DOCEF_SKIP) {
      doc_e->x = x;
      doc_e->y = y;
      doc_e = doc_e->next;
      continue;
    }
    MemCpy(&doc_e->settings, s, sizeof(CDocSettings));
    doc_e->x = x;
    doc_e->y = y;
    switch (doc_e->type_u8) {
      case DOCT_FOREGROUND :
      if (doc_e->attr == DOC_DFT)
        fg = s->dft_text_attr & 15;
      else
        fg = doc_e->attr & 15;
      cur_attr = bg << 4 + fg;
      break;
      case DOCT_BACKGROUND :
      if (doc_e->attr == DOC_DFT)
        bg = (s->dft_text_attr >> 4) & 15;
      else
        bg = doc_e->attr & 15;
      cur_attr = bg << 4 + fg;
      break;
      case DOCT_INDENT :
      indent += doc_e->attr;
      if (indent < 0)
        indent = 0;
      x = indent;
      doc_e->x = x;
      break;
      case DOCT_NEW_LINE :
      y++;
      x = indent;
      break;
      case DOCT_SOFT_NEW_LINE :
      // Soft wrap — same visual as NEW_LINE for lite Recalc
      y++;
      x = indent;
      break;
      case DOCT_PAGE_BREAK :
      y++;
      x = indent;
      break;
      case DOCT_CURSOR :
      case DOCT_CLEAR :
      // Marker / clear — no layout advance
      break;
      case DOCT_PMT :
      if (doc_e->tag) {
        doc_e->max_col = StrLen(doc_e->tag);
        x += doc_e->max_col;
      }
      doc_e->type = DOCT_PMT | (DOC_COLOR_PMT << 8);
      break;
      case DOCT_BLINK :
      if (doc_e->attr == DOC_DFT)
        blink = 0;
      else if (doc_e->attr)
        blink = DOCET_BLINK;
      else
        blink = 0;
      break;
      case DOCT_INVERT :
      if (doc_e->attr == DOC_DFT)
        invert = 0;
      else if (doc_e->attr)
        invert = DOCET_INVERT;
      else
        invert = 0;
      break;
      case DOCT_UNDERLINE :
      if (doc_e->attr == DOC_DFT)
        ul = 0;
      else if (doc_e->attr)
        ul = DOCET_UNDERLINE;
      else
        ul = 0;
      break;
      case DOCT_TAB :
      x = (x + 8) & ~7;
      break;
      case DOCT_TEXT :
      if (doc_e->tag) {
        doc_e->max_col = StrLen(doc_e->tag);
        x += doc_e->max_col;
      }
      doc_e->type = DOCT_TEXT | (cur_attr << 8) | blink | invert | ul;
      break;
      case DOCT_LINK :
      doc_e->type = DOCT_LINK | (DOC_COLOR_LINK << 8) | DOCET_UNDERLINE;
      if (doc_e->tag)
        x += StrLen(doc_e->tag);
      doc_e->max_col = 1;
      break;
      case DOCT_BTTN :
      doc_e->type = DOCT_BTTN | (DOC_COLOR_MACRO << 8) | DOCET_UNDERLINE;
      if (doc_e->tag)
        x += StrLen(doc_e->tag);
      doc_e->max_col = 1;
      break;
      case DOCT_DATA :
      doc_e->type = DOCT_DATA | (DOC_COLOR_STR << 8);
      if (doc_e->tag) {
        doc_e->max_col = StrLen(doc_e->tag);
        x += doc_e->max_col;
      }
      break;
      case DOCT_CHECK_BOX :
      doc_e->type = DOCT_CHECK_BOX | (DOC_COLOR_PMT << 8);
      if (doc_e->tag)
        x += StrLen(doc_e->tag);
      doc_e->max_col = 2;
      break;
      case DOCT_MACRO :
      doc_e->type = DOCT_MACRO | (DOC_COLOR_MACRO << 8) | DOCET_UNDERLINE;
      if (doc_e->tag)
        x += StrLen(doc_e->tag);
      doc_e->max_col = 1;
      break;
      case DOCT_TREE :
      doc_e->type = DOCT_TREE | (DOC_COLOR_TREE << 8) | DOCET_UNDERLINE;
      if (doc_e->tag)
        x += StrLen(doc_e->tag);
      doc_e->max_col = 1;
      // Collapse: mark following indent region SKIP
      tree_collapsed = ToBool(doc_e->de_flags & DOCEF_CHECKED_COLLAPSED);
      doc_e2 = doc_e->next;
      while (doc_e2 != doc && doc_e2->type_u8 != DOCT_INDENT && !(doc_e2->de_flags & DOCEF_TREE))
        doc_e2 = doc_e2->next;
      if (doc_e2 != doc && doc_e2->type_u8 == DOCT_INDENT) {
        j = i = indent;
        do {
          if (tree_collapsed)
            doc_e2->de_flags |= DOCEF_SKIP;
          else
            doc_e2->de_flags &= ~DOCEF_SKIP;
          if (doc_e2->type_u8 == DOCT_INDENT)
            j += doc_e2->attr;
          doc_e2 = doc_e2->next;
        } while (doc_e2 != doc && j > i);
      }
      break;
      case DOCT_ANCHOR :
      case DOCT_CURSOR_MOVEMENT :
      case DOCT_WORD_WRAP :
      case DOCT_HIGHLIGHT :
      case DOCT_PAGE_LEN :
      // Markers / settings — no layout advance
      break;
      case DOCT_LEFT_MARGIN :
      if (doc_e->attr != DOC_DFT && doc_e->attr >= 0) {
        indent = doc_e->attr;
        x = indent;
        doc_e->x = x;
      }
      break;
      case DOCT_RIGHT_MARGIN :
      break;
      case DOCT_SHIFTED_X :
      case DOCT_SHIFTED_Y :
      x += 1;
      break;
      case DOCT_MENU_VAL :
      doc_e->type = DOCT_MENU_VAL | (DOC_COLOR_MACRO << 8) | DOCET_UNDERLINE;
      if (doc_e->tag)
        x += StrLen(doc_e->tag);
      doc_e->max_col = 1;
      break;
      case DOCT_LST :
      doc_e->type = DOCT_LST | (DOC_COLOR_DEFINE_STR << 8);
      if (doc_e->tag) {
        doc_e->max_col = StrLen(doc_e->tag);
        x += doc_e->max_col;
      }
      break;
      case DOCT_SPRITE :
      case DOCT_INS_BIN :
      case DOCT_INS_BIN_SIZE :
      doc_e->type = doc_e->type_u8 | (DOC_COLOR_BIN << 8);
      if (doc_e->tag) {
        doc_e->max_col = StrLen(doc_e->tag);
        x += doc_e->max_col;
      }
      break;
      case DOCT_HEX_ED :
      doc_e->type = DOCT_HEX_ED | (DOC_COLOR_BIN << 8);
      if (doc_e->tag) {
        doc_e->max_col = StrLen(doc_e->tag);
        x += doc_e->max_col;
      } else if (doc_e->hex_ed_width > 0) {
        doc_e->max_col = doc_e->hex_ed_width * 3;
        x += doc_e->max_col;
      }
      break;
      case DOCT_SONG :
      doc_e->type = DOCT_SONG | (DOC_COLOR_MACRO << 8);
      if (doc_e->tag) {
        doc_e->max_col = StrLen(doc_e->tag);
        x += doc_e->max_col;
      }
      break;
      case DOCT_HTML_CODE :
      // Invisible on FB (ToHtml path only)
      doc_e->max_col = 0;
      break;
      default:
      break;
    }
    if (x > doc->max_x)
      doc->max_x = x;
    if (y > doc->max_y)
      doc->max_y = y;
    doc_e = doc_e->next;
  }
  if (unlock)
    DocUnlock(doc);
  return TRUE;
}

CDocEntry *RVDocFindAt(CDoc *doc, I64 cx, I64 cy)
{
  //Find clickable entry covering doc cell (cx,cy) — LINK/TREE/BT/CB/MA/DA/MU/LS/SP.
  CDocEntry *doc_e, *best = NULL;
  I64 x1, x2, t;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return NULL;
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->de_flags & DOCEF_SKIP) {
      doc_e = doc_e->next;
      continue;
    }
    t = doc_e->type_u8;
    if (t == DOCT_LINK || t == DOCT_TREE || t == DOCT_BTTN || t == DOCT_CHECK_BOX || t == DOCT_MACRO || t == DOCT_DATA || t == DOCT_MENU_VAL || t == DOCT_LST || t == DOCT_SPRITE || t == DOCT_INS_BIN) {
      if (doc_e->y == cy) {
        x1 = doc_e->x;
        x2 = x1;
        if (doc_e->tag)
          x2 += StrLen(doc_e->tag);
        if (cx >= x1 && cx < x2)
          best = doc_e;
      }
    }
    doc_e = doc_e->next;
  }
  no_warn x1;
  return best;
}

Bool RVDocToggleCheck(CDoc *doc, CDocEntry *doc_e)
{
  U8 *tag, *name, buf[128];
  if (!doc || !doc_e || doc_e->type_u8 != DOCT_CHECK_BOX)
    return FALSE;
  if (doc_e->de_flags & DOCEF_CHECKED_COLLAPSED)
    doc_e->de_flags &= ~DOCEF_CHECKED_COLLAPSED;
  else
    doc_e->de_flags |= DOCEF_CHECKED_COLLAPSED;
  tag = doc_e->tag;
  if (tag) {
    name = tag;
    if (tag[0] == '[' && tag[2] == ']' && tag[3] == ' ')
      name = tag + 4;
    if (doc_e->de_flags & DOCEF_CHECKED_COLLAPSED)
      StrPrint(buf, "[X] %s", name);
    else
      StrPrint(buf, "[ ] %s", name);
    Free(doc_e->tag);
    doc_e->tag = RVDocStrNew(doc, buf);
  }
  DocRecalc(doc);
  return TRUE;
}

Bool RVDocToggleTree(CDoc *doc, CDocEntry *doc_e)
{
  U8 *tag, *name, buf[128];
  if (!doc || !doc_e || doc_e->type_u8 != DOCT_TREE)
    return FALSE;
  if (doc_e->de_flags & DOCEF_CHECKED_COLLAPSED)
    doc_e->de_flags &= ~DOCEF_CHECKED_COLLAPSED;
  else
    doc_e->de_flags |= DOCEF_CHECKED_COLLAPSED;
  // Refresh "+] "/"-] " prefix
  tag = doc_e->tag;
  if (tag) {
    name = tag;
    if (tag[0] && tag[1] == ']' && tag[2] == ' ')
      name = tag + 3;
    if (doc_e->de_flags & DOCEF_CHECKED_COLLAPSED)
      StrPrint(buf, "-] %s", name);
    else
      StrPrint(buf, "+] %s", name);
    Free(doc_e->tag);
    doc_e->tag = RVDocStrNew(doc, buf);
  }
  DocRecalc(doc);
  return TRUE;
}

Bool RVDocSelClickable(I64 t)
{
  //The activatable entry types — same set RVDocFindAt treats as clickable.
  return t == DOCT_LINK || t == DOCT_TREE || t == DOCT_BTTN || t == DOCT_CHECK_BOX || t == DOCT_MACRO || t == DOCT_DATA || t == DOCT_MENU_VAL || t == DOCT_LST || t == DOCT_SPRITE || t == DOCT_INS_BIN;
}

Bool RVDocSelMove(CDoc *doc, I64 dir)
{
  //Move doc->cur_entry to the next (dir>0) / prev (dir<0) clickable entry, wrapping.
  // The list is circular through the doc sentinel (head at offset 0 == doc), so a step
  // that lands on `doc` is the wrap point and is skipped. Returns TRUE if it moved.
  CDocEntry *start, *doc_e;
  I64 guard = 0;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return FALSE;
  start = doc->cur_entry;
  if (!start)
    start = doc;
  doc_e = start;
  while (guard++ < 200000) {
    if (dir < 0)
      doc_e = doc_e->last;
    else
      doc_e = doc_e->next;
    if (doc_e == start)
      break;
    // full circle: no other clickable entry
    if (doc_e == doc)
      continue;
    // skip the sentinel, keep walking
    if (doc_e->de_flags & DOCEF_SKIP)
      continue;
    if (RVDocSelClickable(doc_e->type_u8)) {
      doc->cur_entry = doc_e;
      rv_doc_sel_moves++;
      return TRUE;
    }
  }
  return FALSE;
}

U0 RVDocEdMove(CDoc *doc, I64 dir)
{
  //Editor cursor: cur_entry is the insertion point (DocEdInsChar inserts at ->last, i.e.
  // just before cur_entry; the doc sentinel == end-of-doc). dir: -1 left, +1 right,
  // -2 up, +2 down (nearest column on the target row). DocRecalc has assigned x/y.
  CDocEntry *doc_e, *best;
  I64 cx, cy, ty, bestdx, dx;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return;
  DocRecalc(doc);
  doc_e = doc->cur_entry;
  if (!doc_e)
    doc_e = doc;
  if (dir == -1) {
    if (doc_e->last != doc)
      // don't step past the head sentinel
      doc->cur_entry = doc_e->last;
    return;
  }
  if (dir == 1) {
    if (doc_e != doc)
      // sentinel already means end-of-doc
      doc->cur_entry = doc_e->next;
    return;
  }
  // up/down: current column/row (sentinel → just past the last entry)
  if (doc_e == doc) {
    if (doc->head.last != doc) {
      cx = doc->head.last->x + 1;
      cy = doc->head.last->y;
    } else {
      cx = 0;
      cy = 0;
    }
  } else {
    cx = doc_e->x;
    cy = doc_e->y;
  }
  ty = cy + 1;
  if (dir == -2)
    ty = cy - 1;
  if (ty < 0)
    return;
  best = NULL;
  bestdx = 0x7FFFFFFF;
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (!(doc_e->de_flags & DOCEF_SKIP) && doc_e->y == ty) {
      dx = doc_e->x - cx;
      if (dx < 0)
        dx = -dx;
      if (dx < bestdx) {
        bestdx = dx;
        best = doc_e;
      }
    }
    doc_e = doc_e->next;
  }
  if (best)
    doc->cur_entry = best;
}

I64 RVDocEdExtractText(CDoc *doc, U8 *out, I64 max)
{
  //Serialize the doc's text entries to plain bytes (DOCT_TEXT + \n/\t). Markup entries
  // are dropped — a plain-text editor round-trips plain files exactly; a $-markup .DD is
  // flattened (edit A: scratch, not stock docs). Returns the byte count written.
  CDocEntry *doc_e;
  I64 n = 0, i, l;
  U8 *t;
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL || !out || max < 1)
    return 0;
  doc_e = doc->head.next;
  while (doc_e != doc && n < max - 1) {
    if (doc_e->type_u8 == DOCT_TEXT && doc_e->tag) {
      t = doc_e->tag;
      l = StrLen(t);
      for (i = 0; i < l && n < max - 1; i++)
        out[n++] = t[i];
    } else if (doc_e->type_u8 == DOCT_NEW_LINE || doc_e->type_u8 == DOCT_SOFT_NEW_LINE) {
      out[n++] = '\n';
    } else if (doc_e->type_u8 == DOCT_TAB) {
      out[n++] = '\t';
    }
    doc_e = doc_e->next;
  }
  out[n] = 0;
  return n;
}

Bool RVDocActivate(CDoc *doc, CDocEntry *doc_e)
{
  //LINK/MA/BT/MU → status (+ FI: open); TREE/CB → toggle. Returns TRUE if handled.
  U8 *link;
  if (!doc || !doc_e)
    return FALSE;
  if (doc_e->type_u8 == DOCT_TREE)
    return RVDocToggleTree(doc, doc_e);
  if (doc_e->type_u8 == DOCT_CHECK_BOX)
    return RVDocToggleCheck(doc, doc_e);
  if (doc_e->type_u8 == DOCT_LINK) {
    link = NULL;
    if (doc_e->de_flags & DOCEF_AUX_STR)
      link = doc_e->aux_str;
    else if (doc_e->tag)
      link = doc_e->tag;
    if (!link)
      link = "";
    Print("RVDoc LINK click tag=%s aux=%s\n", doc_e->tag ? doc_e->tag : "", link);
    if (link[0] == 'F' && link[1] == 'I' && link[2] == ':') {
      // Re-entrancy: Welcome/HelpIndex docs contain more FI: links; do not nest OpenLink.
      if (!rv_doc_open_busy) {
        if (RVDocOpenLink(link))
          rv_doc_link_opens++;
      } else
        Print("RVDoc FI: nested skip %s\n", link);
    } else if (link[0] == 'M' && link[1] == 'N' && link[2] == ':') {
      Print("RVDoc MN link %s\n", link);
      rv_doc_link_opens++;
    }
    return TRUE;
  }
  if (doc_e->type_u8 == DOCT_MACRO) {
    link = NULL;
    if (doc_e->de_flags & DOCEF_AUX_STR)
      link = doc_e->aux_str;
    else if (doc_e->left_macro)
      link = doc_e->left_macro;
    if (!link)
      link = "";
    Print("RVDoc MA click tag=%s LM=%s\n", doc_e->tag ? doc_e->tag : "", link);
    return TRUE;
  }
  if (doc_e->type_u8 == DOCT_BTTN || doc_e->type_u8 == DOCT_MENU_VAL) {
    Print("RVDoc BT/MU click tag=%s LE=%d\n", doc_e->tag ? doc_e->tag : "", doc_e->left_exp);
    return TRUE;
  }
  if (doc_e->type_u8 == DOCT_DATA || doc_e->type_u8 == DOCT_LST) {
    Print("RVDoc DA/LS select tag=%s\n", doc_e->tag ? doc_e->tag : "");
    return TRUE;
  }
  if (doc_e->type_u8 == DOCT_SPRITE || doc_e->type_u8 == DOCT_INS_BIN) {
    Print("RVDoc SP/IB tag=%s bin=%d\n", doc_e->tag ? doc_e->tag : "", doc_e->bin_num);
    return TRUE;
  }
  return FALSE;
}

I64 RVDocLineCount(CDoc *doc)
{
  if (!doc || doc->doc_signature != DOC_SIGNATURE_VAL)
    return 0;
  DocRecalc(doc);
  return doc->max_y + 1;
}

CDoc *DocBorderNew(CDoc *pdoc = NULL)
{
  //Lite DocBorderNew: title DA + [X] + MENU as real entries (no CM geometry).
  // WinMgr chrome still paints title-bar cues; this backs DocBorder() / Fs->border_doc.
  CDoc *bdoc;
  CDocEntry *doc_e;
  U8 *title;
  U8 line[96];
  no_warn pdoc;
  bdoc = DocNew("BORDER.DD");
  if (!bdoc)
    return NULL;
  bdoc->flags |= DOCF_BORDER_DOC;
  bdoc->desc = 'Border';
  title = "TempleOS";
  if (Fs && Fs->task_title[0])
    title = Fs->task_title;
  StrPrint(line, "$$DA,\"%s\"$$\n", title);
  DocPutS(bdoc, line);
  DocPutS(bdoc, "$$BT,\"[X]\",LE=0$$\n");
  doc_e = bdoc->cur_entry->last;
  if (doc_e && doc_e->type_u8 == DOCT_BTTN)
    doc_e->user_data = 'X';
  DocPutS(bdoc, "$$BT,\"MENU\",LE=1$$\n");
  doc_e = bdoc->cur_entry->last;
  if (doc_e && doc_e->type_u8 == DOCT_BTTN)
    doc_e->user_data = 'M';
  DocRecalc(bdoc);
  return bdoc;
}

U8 *RVDocDemoInPageBody()
{
  // Host path: Demo/ToHtmlToTXTDemo/DemoInPage.DD shape (WW/FG/TX+HTML=).
  // Host lexer: `$Letter…$` inside a string is copied VERBATIM (\" stays
  // backslash). Emit DolDoc via $$…$$ per fragment so \" → " and adjacent
  // fragments concatenate to $cmd1$$cmd2$ (end+start). Same pattern as HOME.
  return "$$WW,1$$\n" "$$FG,5$$\n" "$$TX+CX,\"TempleOS\",HTML=\"http://www.templeos.org\"$$\n" "$$FG,0$$\n" "$$FG,4$$\n" "$$TX,\"Downloads\",HTML=\"http://www.templeos.org/Downloads\"$$\n" "$$FG$$\n" "TempleOS DemoInPage (RV host embed).\n" "$$TX,\"Hello\",HTML=\"http://example.com/joke\"$$\n" "$$HX,16,4$$\n" "$$SO,\"Demo\",A=\"4CDE\"$$\n" "$$HC,\"rv-demo\"$$\n";
}

I64 RVDocDemoProbe()
{
  // Load DemoInPage (+HX/SO/HC) via DocPutS; return entry count for smoke.
  CDoc *doc;
  I64 n = 0, html0, hx0, so0, hc0, lex0, flag0;
  html0 = rv_doc_html_hits;
  hx0 = rv_doc_hx_hits;
  so0 = rv_doc_song_hits;
  hc0 = rv_doc_hc_hits;
  lex0 = rv_doc_prs_lex_hits;
  flag0 = rv_doc_prs_flag_hits;
  DocInit;
  doc = DocNew("DemoInPage.DD");
  if (!doc)
    return 0;
  DocPutS(doc, RVDocDemoInPageBody());
  DocRecalc(doc);
  n = DocSize(doc);
  rv_doc_demo_entries = n;
  Print("RVDoc DemoInPage entries=%d html=%d hx=%d song=%d hc=%d lex=%d flag=%d\n", n, rv_doc_html_hits - html0, rv_doc_hx_hits - hx0, rv_doc_song_hits - so0, rv_doc_hc_hits - hc0, rv_doc_prs_lex_hits - lex0, rv_doc_prs_flag_hits - flag0);
  DocDel(doc);
  return n;
}

public I64 RVDocPrintFlagsSoft()
{
  // Soft Call: product DocPrint TX+CX → CENTER_X entry + DocRecalc (UART, no FB).
  // Beyond flag/arg Soft tips — DocPrint → DocPutS → PrsDollarCmd → Recalc.
  CDoc *doc;
  CDocEntry *doc_e, *hit;
  I64 guard, n0, n1;
  DocInit;
  doc = DocNew("FLAGS.DD");
  if (!doc)
    return 3;
  n0 = DocSize(doc);
  DocPrint(doc, "$$TX+CX,\"hi\"$$");
  n1 = DocSize(doc);
  if (n1 <= n0) {
    DocDel(doc);
    return 4;
  }
  hit = NULL;
  doc_e = doc->head.next;
  guard = 0;
  while (doc_e && doc_e != doc) {
    if (++guard > 100000)
      break;
    if (doc_e->type_u8 == DOCT_TEXT && (doc_e->de_flags & DOCEF_CENTER_X) && doc_e->tag && !StrCmp(doc_e->tag, "hi")) {
      hit = doc_e;
      break;
    }
    doc_e = doc_e->next;
  }
  if (!hit) {
    DocDel(doc);
    return 5;
  }
  if (!DocRecalc(doc)) {
    DocDel(doc);
    return 6;
  }
  if (!(hit->de_flags & DOCEF_CENTER_X) || hit->max_col != 2) {
    DocDel(doc);
    return 7;
  }
  DocDel(doc);
  return 8;
}

public I64 RVDocEdSoft()
{
  // Soft Call: stock DocEd-lite under UART (no FB) — DOCF_FORM + inject Tab/Enter
  // → BT LE=1; DocMenu-lite MU LE=42. Beyond DocPrintFlags Soft tip.
  CDoc *doc;
  I64 hits0, menu_r;
  DocInit;
  doc = DocNew("ED.DD");
  if (!doc)
    return 3;
  doc->flags |= DOCF_FORM;
  DocPutS(doc, "$$TX,\"Ed\"$$\n$$BT,\"OK\",LE=1$$\n$$BT,\"Cancel\",LE=-1$$\n");
  if (!DocRecalc(doc)) {
    DocDel(doc);
    return 4;
  }
  DocEdKeyInjectClear;
  DocEdKeyInject('\t');
  DocEdKeyInject('\n');
  hits0 = rv_doc_ed_modal_hits;
  if (!DocEd(doc, 0)) {
    DocDel(doc);
    return 5;
  }
  if (rv_doc_ed_result != 1) {
    DocDel(doc);
    return 6;
  }
  if (rv_doc_ed_modal_hits <= hits0) {
    DocDel(doc);
    return 7;
  }
  DocDel(doc);
  doc = DocNew("MENU.DD");
  if (!doc)
    return 9;
  DocPutS(doc, "$$MU,\"Pick\",LE=42$$\n");
  if (!DocRecalc(doc)) {
    DocDel(doc);
    return 10;
  }
  DocEdKeyInjectClear;
  DocEdKeyInject('\n');
  menu_r = DocMenu(doc, 0);
  DocDel(doc);
  if (menu_r != 42)
    return 11;
  return 8;
}
// Mini sprite stream for DocSprite smoke (COLOR+CIRCLE+END — SpriteRaw shape).
class RVDocDemoSprite
{
  CSpriteColor color;
  CSpritePtRad circ;
  CSpriteBase end;
};

CDocBin *DocSpriteBinNew(CDoc *doc, U8 *tag = NULL)
{
  //Attach a paint-able SPT stream as CDocBin (TempleOS DocSprite path).
  RVDocDemoSprite s;
  if (!doc)
    return NULL;
  MemSet(&s, 0, sizeof(s));
  s.color.type = SPT_COLOR;
  s.color.color = YELLOW;
  s.circ.type = SPT_CIRCLE;
  s.circ.x1 = 8;
  s.circ.y1 = 8;
  s.circ.radius = 6;
  s.end.type = SPT_END;
  return DocBinNew(doc, &s, sizeof(s), tag);
}

Bool DocSprite(CDoc *doc, CDocEntry *doc_e, CRVDC *dc, I64 x, I64 y)
{
  //Adam DocRecalc DOCT_SPRITE → Sprite3. Returns TRUE if painted.
  CDocBin *tmpb;
  if (!doc || !doc_e || !dc)
    return FALSE;
  if (doc_e->type_u8 != DOCT_SPRITE)
    return FALSE;
  if (!doc_e->bin_data && (doc_e->de_flags & DOCEF_HAS_BIN))
    doc_e->bin_data = DocBinFindNum(doc, doc_e->bin_num);
  tmpb = doc_e->bin_data;
  if (!tmpb || !tmpb->data || tmpb->size < 1)
    return FALSE;
  Sprite3(dc, x, y, 0, tmpb->data);
  rv_doc_sprite_paints++;
  return TRUE;
}

CDocEntry *DocSpriteIns(CDoc *doc = NULL, U8 *elems, U8 *fmt = NULL)
{
  //Adam/Gr/GrSpritePlot.HC DocSprite — bin + $$SP$$ into DocPut (PsmMenu play/record).
  // Named DocSpriteIns so Bool DocSprite(paint) keeps its WinMgr paint signature.
  I64 size;
  U8 *st;
  Bool unlock;
  CDocEntry *doc_e;
  CDocBin *tmpb;
  if (!elems)
    return NULL;
  if (!doc && !(doc = DocPut))
    return NULL;
  if (doc->doc_signature != DOC_SIGNATURE_VAL)
    return NULL;
  unlock = DocLock(doc);
  size = SpriteSize(elems);
  if (size < 1) {
    if (unlock)
      DocUnlock(doc);
    return NULL;
  }
  tmpb = CAlloc(sizeof(CDocBin), doc->mem_task);
  tmpb->size = size;
  tmpb->data = MAlloc(size, doc->mem_task);
  if (!tmpb->data) {
    Free(tmpb);
    if (unlock)
      DocUnlock(doc);
    return NULL;
  }
  MemCpy(tmpb->data, elems, size);
  tmpb->num = doc->cur_bin_num;
  tmpb->use_cnt = 1;
  if (!doc->bin_head.next)
    QueInit(&doc->bin_head);
  QueIns(tmpb, doc->bin_head.last);
  if (fmt)
    st = MStrPrint(fmt, doc->cur_bin_num++);
  else
    st = MStrPrint("$$SP,\"\",BI=%d$$", doc->cur_bin_num++);
  doc_e = DocPrint(doc, "%s", st);
  Free(st);
  if (doc_e) {
    doc_e->bin_data = tmpb;
    doc_e->de_flags |= DOCEF_HAS_BIN;
    doc_e->bin_num = tmpb->num;
    if ((doc_e->de_flags & DOCEF_TAG) && doc_e->tag && *doc_e->tag)
      tmpb->tag = StrNew(doc_e->tag, doc->mem_task);
  }
  if (unlock)
    DocUnlock(doc);
  return doc_e;
}

CDocEntry *Sprite(U8 *elems, U8 *fmt = NULL)
{
  //Stock Sprite→DocSpriteIns when DocPut exists; else plot on screen DC (chrome).
  // PsmMenu: Sprite($IB,BI=n$) and Sprite($IB, "$$SP,\"\",LM=\"z\",BI=%d$$").
  CDoc *doc;
  if (doc = DocPut)
    return DocSpriteIns(doc, elems, fmt);
  if (elems && rv_gr.dc)
    Sprite3(rv_gr.dc, 0, 0, 0, elems);
  return NULL;
}

U8 *DocBinData(CDoc *doc, I64 bin_num)
{
  //TempleOS $IB → sprite ptr. Return CDocBin.data for BI=n (Psalmody staff).
  CDocBin *b;
  if (!doc || bin_num < 1)
    return NULL;
  b = DocBinFindNum(doc, bin_num);
  if (!b || !b->data || b->size < 1)
    return NULL;
  return b->data;
}

I64 RVDocStaffBinsProbe(U8 *path = NULL)
{
  //DocLoad a DolDoc-with-bins file; count bins + optional Sprite3 BI=1.
  // Host $IB now carries trailing CDocBin; this remains the DocRead runtime path.
  CDoc *doc;
  CDocBin *b;
  I64 n = 0, paints0;
  U8 *elems;
  if (!path)
    path = "Demo/Graphics/SpritePut.HC";
  paints0 = rv_doc_sprite_paints;
  doc = DocRead(path);
  if (!doc) {
    Print("RVDoc StaffBins FAIL read %s\n", path);
    return 0;
  }
  b = doc->bin_head.next;
  while (b != &doc->bin_head) {
    n++;
    b = b->next;
  }
  elems = DocBinData(doc, 1);
  if (elems && rv_gr.dc) {
    Sprite3(rv_gr.dc, 16, 16, 0, elems);
    rv_doc_sprite_paints++;
  }
  Print("RVDoc StaffBins path=%s bins=%d paint=%d\n", path, n, rv_doc_sprite_paints - paints0);
  DocDel(doc);
  return n;
}

U0 DirFileDoc(CDoc *doc, CDirEntry *tmpde)
{
  //Stock Adam/ABlkDev/FileMgr.HC DirFileDoc. Format via StrPrint+DocPutS
  // (DocPrint+StrPrintJoin on $$…%s…$$ was tied to MsgPutKey mepc=0 on RV).
  U8 buf[128];
  CDocEntry *doc_e;
  while (tmpde) {
    if (tmpde->attr & RS_ATTR_DIR) {
      StrPrint(buf, "$$TR,\"%s\",U=0x%X$$", tmpde->name, tmpde);
      doc_e = DocPutS(doc, buf);
      tmpde->user_data = doc_e;
      DocPutS(doc, "\n$$ID,+2$$");
      if (tmpde->sub)
        DirFileDoc(doc, tmpde->sub);
      DocPutS(doc, "$$ID,-2$$");
    } else {
      StrPrint(buf, "$$MU,\"%s\",U=0x%X$$", tmpde->name, tmpde);
      doc_e = DocPutS(doc, buf);
      tmpde->user_data = doc_e;
      DocPutS(doc, "\n");
    }
    tmpde = tmpde->next;
  }
}

U0 RVDirFileDoc(CDoc *doc, U8 *drv_name, U8 **file_names, I64 n_files)
{
  //Legacy synthetic probe — prefer stock DirFileDoc(FilesFind) via RVFileMgrDocProbe.
  I64 i;
  U8 line[128];
  if (!doc || !drv_name)
    return;
  StrPrint(line, "$$TR,\"%s\",U=0x1$$\n", drv_name);
  DocPutS(doc, line);
  DocPutS(doc, "$$ID,+2$$\n");
  for (i = 0; i < n_files; i++) {
    if (file_names && file_names[i]) {
      StrPrint(line, "$$MU,\"%s\",U=0x%X$$\n", file_names[i], i + 2);
      DocPutS(doc, line);
    }
  }
  DocPutS(doc, "$$ID,-2$$\n");
}

I64 RVFileMgrDocProbe()
{
  //Stock FilesFind + DirFileDoc (Adam FileMgr shape). U= via StrPrint+DocPutS.
  CDoc *doc;
  CDocEntry *doc_e;
  CDirEntry *head = NULL, *tmpde, *sub;
  I64 n = 0, u0 = 0, trees = 0, mus = 0, i;
  U8 *names[4], *st, line[128];
  Print("RVDoc FileMgr probe begin\n");
  u0 = rv_doc_filemgr_user_hits;
  names[0] = "HOME.DD";
  names[1] = "Welcome.DD";
  names[2] = "DemoInPage.DD";
  names[3] = "WINDIR.TXT";
  for (i = 0; i < 4; i++) {
    st = MStrPrint("A:/%s", names[i]);
    FileWrite(st, names[i], StrLen(names[i]));
    Free(st);
  }
  doc = DocNew("FileMgr.DD");
  if (!doc)
    return 0;
  DocPutS(doc, "$$TX,\"File Manager\"$$\n\n");
  rv_doc_filemgr_ffind = 0;
  st = MStrPrint("A:/*");
  Print("RVDoc FileMgr probe FilesFind\n");
  sub = FilesFind(st, 0);
  Free(st);
  Print("RVDoc FileMgr probe ffind sub=%d\n", sub != NULL);
  if (sub) {
    rv_doc_filemgr_ffind = 1;
    head = CAlloc(sizeof(CDirEntry));
    head->full_name = StrNew("A:/");
    head->attr = RS_ATTR_DIR;
    head->sub = sub;
    StrPrint(line, "$$TR,\"%s\",U=0x%X$$", head->full_name, head);
    head->user_data = DocPutS(doc, line);
    DocPutS(doc, "\n$$ID,+2$$");
    DirFileDoc(doc, sub);
    tmpde = sub;
    while (tmpde) {
      tmpde->parent = head;
      tmpde = tmpde->next;
    }
    DocPutS(doc, "$$ID,-2$$");
  } else
    RVDirFileDoc(doc, "A:/", names, 4);
  DocRecalc(doc);
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->type_u8 == DOCT_TREE)
      trees++;
    if (doc_e->type_u8 == DOCT_MENU_VAL)
      mus++;
    doc_e = doc_e->next;
  }
  n = DocSize(doc);
  rv_doc_filemgr_entries = n;
  Print("RVDoc FileMgr entries=%d trees=%d mus=%d user=%d ffind=%d lex=%d\n", n, trees, mus, rv_doc_filemgr_user_hits - u0, rv_doc_filemgr_ffind, rv_doc_prs_lex_hits);
  if (head)
    DirTreeDel(head);
  DocDel(doc);
  return n;
}
// DocEd: DocEdIns/BS/undo + modal DOCF_FORM (inject/ScanMsg); DocForm Lex-lite;
// DocMenu-lite; DocBin*; FI: via RVDocOpenLink (RVWinMgr). HX/SO/HC + TX HTML=
// + DemoInPage host embed landed (TX+CX flag= via RVDocPrsFlagsCmp). DocSprite→
// Sprite3 + $$IB size + stock FileMgr DirFileDoc/FilesFind. DocInit_RV HashFind
// PrsDollarCmd + arg/tag T=/HTML= (+docarg) + LE=/LM=/A=/BI= (+docargx) via
// RVDocPrsArgOnce. DocInit seed (+docinitseed): DHT_DOC_* plant + stock seed
// string apply (RVDocInitSeedApply). CmpCtrl PrsDocFlags (+docflaglex): abs-addr
// CmpCtrl Lex + DHT_DOC_FLAG HashFind (RVDocPrsFlagsLex). Soft +doccmdlex:
// one-cmd PrsDollarCmd IDENT+flags+TK_STR via same abs fps. Soft +docarglex:
// one LexExpressionI64 arg LE=/LEN= via RVCmpCtrlAddrsGet[2] (literal fast-path).
// Soft +docextstr: LexExtStr T=/LM= via RVCmpCtrlAddrsGet[4] (TX,T="hi"/MA,LM=).
// Soft +docmultilex: multi-arg PrsDollarCmd TX+CX,T= / LK A=+HTML=+BI= (abs fps).
// Remaining: guest MakeDoc #include Adam/DolDoc/* — G8.
// Soft +docprintflags: product DocPrint TX+CX + DocRecalc (RVDocPrintFlagsSoft).
// Soft +doced: DocEd modal inject Tab/Enter BT LE + DocMenu MU LE (RVDocEdSoft).
// RVDocDrawWin / DocSprite paint pass is in RVWinMgr.HC.
