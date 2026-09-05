// RVAC.HC — AutoComplete lite toward TempleOS ACTask / Doc-complete.
// Seeds a small HolyC keyword hash; refreshes fill-ins from focused body partial
// word; F1–F10 insert via RVACFillIn. Not full ACTask Spawn / dict / KeyMap.
#ifndef RV_AC_HC
#define RV_AC_HC
I64 rv_ac_ready;
I64 rv_ac_hits;
I64 rv_ac_fill_hits;
I64 rv_ac_refresh_hits;
U8 rv_ac_line[80];
CHashAC *RVACHashAdd(U8 *w)
{
  CHashAC *tmpw;
  if (!w || !*w || !ac.hash_table)
    return NULL;
  tmpw = HashFind(w, ac.hash_table, HTT_WORD);
  if (tmpw) {
    tmpw->hits++;
    return tmpw;
  }
  tmpw = CAlloc(sizeof(CHashAC));
  tmpw->str = AStrNew(w);
  tmpw->type = HTT_WORD;
  tmpw->use_cnt = 1;
  tmpw->hits = 1;
  HashAdd(tmpw, ac.hash_table);
  ac.num_words++;
  return tmpw;
}

U0 RVACFillInAdd(CHashAC *tmpw)
{
  I64 k;
  if (!tmpw)
    return;
  if (ac.num_fillins < AC_FILLINS_NUM || tmpw->hits > ac.fillin_hits[ac.num_fillins - 1]) {
    for (k = ac.num_fillins - 1; k >= 0; k--) {
      if (tmpw->hits <= ac.fillin_hits[k])
        break;
      else {
        ac.fillin_matches[k + 1] = ac.fillin_matches[k];
        ac.fillin_hits[k + 1] = ac.fillin_hits[k];
      }
    }
    ac.fillin_matches[k + 1] = tmpw;
    ac.fillin_hits[k + 1] = tmpw->hits;
    if (ac.num_fillins < AC_FILLINS_NUM)
      ac.num_fillins++;
  }
}

I64 RVACPriorWord(U8 *src, U8 *dst, I64 len, I64 buf_size)
{
  I64 i, j = 0, k;
  if (!src || !dst || buf_size < 2)
    return 0;
  i = len - 1;
  while (i >= 0) {
    if (src[i] >= '0' && src[i] <= '9' || src[i] >= 'A' && src[i] <= 'Z' || src[i] >= 'a' && src[i] <= 'z' || src[i] == '_')
      i--;
    else
      break;
  }
  if (len > 0)
    for (k = i + 1; k < len && j < buf_size - 1; k++)
      dst[j++] = src[k];
  dst[j] = 0;
  return j;
}

U0 RVACSeedKeywords()
{
  //Common HolyC / Doc / WinMgr tokens — stand-in for ACInit file walk.
  RVACHashAdd("Print");
  RVACHashAdd("U0");
  RVACHashAdd("I64");
  RVACHashAdd("U8");
  RVACHashAdd("Bool");
  RVACHashAdd("F64");
  RVACHashAdd("class");
  RVACHashAdd("public");
  RVACHashAdd("return");
  RVACHashAdd("while");
  RVACHashAdd("for");
  RVACHashAdd("if");
  RVACHashAdd("else");
  RVACHashAdd("include");
  RVACHashAdd("DocPrint");
  RVACHashAdd("DocNew");
  RVACHashAdd("DocPut");
  RVACHashAdd("Spawn");
  RVACHashAdd("Yield");
  RVACHashAdd("Sleep");
  RVACHashAdd("MemCpy");
  RVACHashAdd("MemSet");
  RVACHashAdd("StrLen");
  RVACHashAdd("StrCmp");
  RVACHashAdd("StrPrint");
  RVACHashAdd("ExePutS");
  RVACHashAdd("WinFocus");
  RVACHashAdd("WinToTop");
  RVACHashAdd("TaskValidate");
  RVACHashAdd("CAlloc");
  RVACHashAdd("MAlloc");
  RVACHashAdd("Free");
  RVACHashAdd("TRUE");
  RVACHashAdd("FALSE");
  RVACHashAdd("NULL");
}

U0 RVACInit()
{
  if (rv_ac_ready)
    return;
  if (!ac.hash_table)
    ac.hash_table = HashTableNew(256);
  ac.num_words = 0;
  Free(ac.cur_word);
  ac.cur_word = NULL;
  ac.num_fillins = 0;
  ac.partial_len = 0;
  RVACSeedKeywords;
  LBts(&sys_run_level, RLf_AUTO_COMPLETE);
  rv_ac_ready = 1;
  rv_ac_line[0] = 0;
  StrCpy(rv_ac_line, "AC: (idle)");
}

Bool AutoComplete(Bool val = OFF)
{
  //RV soft AutoComplete ON/OFF — no ACTask Spawn (needs full DolDoc).
  Bool old = rv_ac_ready && Bt(&sys_run_level, RLf_AUTO_COMPLETE);
  if (val) {
    RVACInit;
    LBts(&sys_run_level, RLf_AUTO_COMPLETE);
  } else
    LBtr(&sys_run_level, RLf_AUTO_COMPLETE);
  return old;
}

U0 RVACRefresh(U8 *body)
{
  I64 i, len, plen;
  U8 buf[64];
  CHashAC *tmpw;
  U8 *st;
  if (!rv_ac_ready || !Bt(&sys_run_level, RLf_AUTO_COMPLETE))
    return;
  if (!body)
    body = "";
  len = StrLen(body);
  while (len > 0 && (body[len - 1] == '\n' || body[len - 1] == '\r'))
    len--;
  plen = RVACPriorWord(body, buf, len, 64);
  ac.partial_len = plen;
  st = ac.cur_word;
  ac.cur_word = AStrNew(buf);
  Free(st);
  ac.num_fillins = 0;
  if (*buf && ac.hash_table) {
    for (i = 0; i <= ac.hash_table->mask; i++) {
      tmpw = ac.hash_table->body[i];
      while (tmpw) {
        if (tmpw->type & HTT_WORD && tmpw->str && !MemCmp(buf, tmpw->str, plen))
          RVACFillInAdd(tmpw);
        tmpw = tmpw->next;
      }
    }
  }
  rv_ac_refresh_hits++;
  if (ac.num_fillins > 0 && ac.fillin_matches[0] && ac.fillin_matches[0]->str)
    StrPrint(rv_ac_line, "AC:%s F1=%s n=%d", buf, ac.fillin_matches[0]->str, ac.num_fillins);
  else if (*buf)
    StrPrint(rv_ac_line, "AC:%s (none)", buf);
  else
    StrCpy(rv_ac_line, "AC: (idle)");
  rv_ac_hits++;
}

U0 ACFillIn(I64 n)
{
  //Insert fill-in #n (1-based) — TempleOS DocPutKey F-key shape.
  U8 *s, *body;
  I64 i, rem, idx;
  if (!rv_ac_ready)
    return;
  if (0 <= --n && n < ac.num_fillins && ac.fillin_matches[n]) {
    s = ac.fillin_matches[n]->str;
    if (s && StrLen(s) > ac.partial_len) {
      rem = StrLen(s) - ac.partial_len;
      for (i = 0; i < rem; i++)
        RVWinBodyPutChar(s[ac.partial_len + i]);
      rv_ac_fill_hits++;
      idx = rv_winmgr.focus;
      body = "";
      if (idx >= 0 && idx < RV_WIN_MAX && rv_winmgr.wins[idx].used)
        body = rv_winmgr.wins[idx].body;
      RVACRefresh(body);
    }
  }
}

U0 RVACFillIn(I64 n)
{
  ACFillIn(n);
}

U0 RVACDraw(I64 row)
{
  //Paint AC status on wallpaper row (right of heap/idle strip).
  if (!rv_ac_ready || row < 0 || row >= rv_winmgr.rows)
    return;
  RVTextPrint(1, row, BLUE << 4 + LTGREEN, rv_ac_line);
}
#endif
