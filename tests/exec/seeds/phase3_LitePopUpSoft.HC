import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
import U8 *StrCpy(U8 *dst, U8 *src);
import I64 StrCmp(U8 *a, U8 *b);
#define RV_SOFT_POPUP_NONE 0
#define RV_SOFT_POPUP_OK 1
#define RV_SOFT_WIN_MAX 4
class CRVSoftWin
{
  I64 used;
  I64 show;
  U8 title[16];
};
I64 g_popup_mode;
I64 g_popup_idx;
I64 g_popup_hits;
I64 g_popup_result;
I64 g_n_wins;
CRVSoftWin g_wins[4];
U0 SoftPopUpClose()
{
  I64 idx;
  idx = g_popup_idx;
  if (g_popup_mode == RV_SOFT_POPUP_NONE) {
    g_popup_idx = -1;
    return;
  }
  if (idx >= 0 && idx < RV_SOFT_WIN_MAX) {
    g_wins[idx].used = 0;
    g_wins[idx].show = 0;
  }
  g_popup_idx = -1;
  g_popup_mode = RV_SOFT_POPUP_NONE;
}

I64 SoftPopUpOk(U8 *header)
{
  I64 i;
  I64 idx;
  if (!header)
    return 0;
  SoftPopUpClose;
  idx = -1;
  for (i = 0; i < RV_SOFT_WIN_MAX; i++) {
    if (!g_wins[i].used) {
      idx = i;
      break;
    }
  }
  if (idx < 0)
    return 0;
  g_wins[idx].used = 1;
  g_wins[idx].show = 1;
  StrCpy(g_wins[idx].title, "PopUp");
  g_popup_mode = RV_SOFT_POPUP_OK;
  g_popup_idx = idx;
  g_popup_hits++;
  g_n_wins++;
  return 1;
}

I64 SoftPopUpResolve(I64 val)
{
  if (g_popup_mode == RV_SOFT_POPUP_NONE)
    return 0;
  g_popup_result = val;
  SoftPopUpClose;
  return 1;
}

public I64 RVPopUpSoftSelfTest()
{
  I64 idx;
  CRVSoftWin *w;
  g_popup_mode = RV_SOFT_POPUP_NONE;
  g_popup_idx = -1;
  g_popup_hits = 0;
  g_popup_result = -1;
  g_n_wins = 0;
  g_wins[0].used = 0;
  g_wins[1].used = 0;
  g_wins[2].used = 0;
  g_wins[3].used = 0;
  if (!SoftPopUpOk("SoftCRV"))
    return 3;
  if (g_popup_mode != RV_SOFT_POPUP_OK)
    return 4;
  idx = g_popup_idx;
  if (idx < 0 || idx >= RV_SOFT_WIN_MAX)
    return 5;
  w = &g_wins[idx];
  if (!w->used || !w->show)
    return 6;
  if (StrCmp(w->title, "PopUp"))
    return 7;
  if (!SoftPopUpResolve(1))
    return 9;
  if (g_popup_mode != RV_SOFT_POPUP_NONE || g_popup_idx >= 0)
    return 10;
  if (w->used || w->show)
    return 11;
  if (g_popup_result != 1)
    return 12;
  return 8;
}
