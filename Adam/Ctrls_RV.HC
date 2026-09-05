// Ctrls_RV.HC — Adam CCtrl queue + DrawCtrls on CRVDC (P3).
// Reuses CtrlsA/Bttn/Slider patterns; draw_it sees CDC* but body is CRVDC.
#ifndef CTRLS_RV_HC
#define CTRLS_RV_HC
#define RV_CTRL_BTTN_BORDER 2
#define BTF_DONT_FREE 1
class CCtrlBttnState
{
  I64 state;
  I64 num_states;
  I64 flags;
  U8 *state_texts;
  I32 *state_colors;
};

class CCtrlSliderState
{
  I64 value;
  I64 range;
  U8 label[16];
};
I64 rv_ctrls_demo_on;
I64 rv_ctrls_hits;
I64 rv_ctrls_n;
I32 rv_ctrl_bttn_colors[2];
U0 RVCtrlsColorInit()
{
  rv_ctrl_bttn_colors[0] = LTRED;
  rv_ctrl_bttn_colors[1] = LTGREEN;
}

public CCtrl *CtrlFindUnique(CTask *haystack_task, I64 needle_type)
{
  CCtrl *c;
  if (!haystack_task)
    return NULL;
  c = haystack_task->next_ctrl;
  while (c != &haystack_task->next_ctrl) {
    if (c->type == needle_type)
      return c;
    c = c->next;
  }
  return NULL;
}

Bool CtrlInsideRect(CCtrl *c, I64 x, I64 y)
{
  if (c->scrn_left <= x <= c->scrn_right && c->scrn_top <= y <= c->scrn_bottom)
    return TRUE;
  return FALSE;
}

public Bool CtrlInside(CCtrl *c, I64 x, I64 y)
{
  if (c->flags & CTRLF_SHOW) {
    if (c->inside_ctrl)
      return (*c->inside_ctrl)(c, x, y);
    return CtrlInsideRect(c, x, y);
  }
  return FALSE;
}

U0 CtrlsUpdate(CTask *task)
{
  CCtrl *c;
  I64 pl, pt;
  if (!TaskValidate(task))
    return;
  pl = task->win_left *FONT_WIDTH;
  pt = task->win_top *FONT_HEIGHT;
  task->pix_left = pl;
  task->pix_top = pt;
  task->pix_width = (task->win_right - task->win_left + 1) * FONT_WIDTH;
  task->pix_height = (task->win_bottom - task->win_top + 1) * FONT_HEIGHT;
  c = task->next_ctrl;
  while (c != &task->next_ctrl) {
    if (c->update_derived_vals)
      (*c->update_derived_vals)(c);
    if (c->flags & CTRLF_BORDER) {
      c->scrn_left = pl + c->left - FONT_WIDTH;
      c->scrn_right = pl + c->right - FONT_WIDTH;
      c->scrn_top = pt + c->top - FONT_HEIGHT;
      c->scrn_bottom = pt + c->bottom - FONT_HEIGHT;
    } else {
      c->scrn_left = pl + c->left;
      c->scrn_right = pl + c->right;
      c->scrn_top = pt + FONT_HEIGHT * 5 + c->top;
      c->scrn_bottom = pt + FONT_HEIGHT * 5 + c->bottom;
    }
    c = c->next;
  }
}

U0 DrawCtrlBttn(CDC *_dc, CCtrl *c)
{
  CRVDC *dc = _dc(CRVDC *);
  CCtrlBttnState *s;
  U8 *st;
  I64 l;
  if (!dc || !c)
    return;
  s = c->state(CCtrlBttnState *);
  if (!s)
    return;
  dc->color = RVColor(BLACK);
  GrRect(dc, c->left, c->top, c->right - c->left + 1, c->bottom - c->top + 1);
  st = LstSub(s->state, s->state_texts);
  if (!st)
    st = s->state_texts;
  if (s->state_colors)
    dc->color = RVColor(s->state_colors[s->state] & 15);
  else if (s->state)
    dc->color = RVColor(LTGREEN);
  else
    dc->color = RVColor(LTRED);
  GrRect(dc, c->left + RV_CTRL_BTTN_BORDER, c->top + RV_CTRL_BTTN_BORDER, c->right - c->left + 1 - RV_CTRL_BTTN_BORDER * 2, c->bottom - c->top + 1 - RV_CTRL_BTTN_BORDER * 2);
  l = StrLen(st);
  dc->color = RVColor(YELLOW);
  GrPrint(dc, (c->left + c->right + 1 - l *FONT_WIDTH) >> 1, (c->top + c->bottom + 1 - FONT_HEIGHT) >> 1, "%s", st);
}

U0 LeftClickCtrlBttn(CCtrl *c, I64, I64, Bool down)
{
  CCtrlBttnState *s;
  if (!down || !c)
    return;
  s = c->state(CCtrlBttnState *);
  if (!s)
    return;
  s->state++;
  if (s->state == s->num_states)
    s->state = 0;
  rv_ctrls_hits++;
  Print("RVCtrls bttn state=%d hits=%d\n", s->state, rv_ctrls_hits);
}

U0 DrawCtrlSlider(CDC *_dc, CCtrl *c)
{
  CRVDC *dc = _dc(CRVDC *);
  CCtrlSliderState *s;
  I64 mid, th, lab_y;
  if (!dc || !c)
    return;
  s = c->state(CCtrlSliderState *);
  if (!s)
    return;
  dc->color = RVColor(LTRED);
  GrRect(dc, c->left, c->top, c->right - c->left + 1, c->bottom - c->top + 1);
  dc->color = RVColor(BLUE);
  GrRect(dc, c->left + 2, c->top + 2, c->right - c->left - 3, c->bottom - c->top - 3);
  dc->color = RVColor(BLACK);
  mid = (c->left + c->right) / 2;
  GrLine(dc, mid, c->top + 4, mid, c->bottom - 4);
  th = s->value;
  if (th < 0)
    th = 0;
  if (th > s->range)
    th = s->range;
  lab_y = c->bottom - 4 - th;
  dc->color = RVColor(LTRED);
  GrRect(dc, mid - 4, lab_y - 2, 9, 5);
  dc->color = RVColor(YELLOW);
  GrPrint(dc, c->left - 2, c->bottom + 2, "%s%d", s->label, th);
}

U0 LeftClickCtrlSlider(CCtrl *c, I64, I64 y, Bool down)
{
  CCtrlSliderState *s;
  I64 th;
  if (!down || !c)
    return;
  s = c->state(CCtrlSliderState *);
  if (!s)
    return;
  th = (c->bottom - 4) - y;
  if (th < 0)
    th = 0;
  if (th > s->range)
    th = s->range;
  s->value = th;
  rv_ctrls_hits++;
  Print("RVCtrls slider val=%d hits=%d\n", s->value, rv_ctrls_hits);
}

public CCtrl *CtrlBttnNew(I64 x, I64 y, I64 width = -1, I64 height = -1, I64 num_states = 2, U8 *state_texts = NULL, I32 *state_colors = NULL, CCtrlBttnState *_s = NULL, CTask *task = NULL)
{
  CCtrl *res;
  CCtrlBttnState *s;
  if (!task)
    task = Fs;
  if (!TaskValidate(task))
    return NULL;
  if (rv_ctrl_bttn_colors[0] == 0 && rv_ctrl_bttn_colors[1] == 0)
    RVCtrlsColorInit;
  if (width < 0)
    width = RV_CTRL_BTTN_BORDER * 4 + 3 * FONT_WIDTH;
  if (height < 0)
    height = RV_CTRL_BTTN_BORDER * 4 + FONT_HEIGHT;
  if (!state_texts)
    state_texts = "Go\0On\0";
  if (!state_colors)
    state_colors = &rv_ctrl_bttn_colors;
  if (num_states < 1)
    num_states = 2;
  res = CAlloc(sizeof(CCtrl));
  if (_s) {
    s = _s;
    MemSet(s, 0, sizeof(CCtrlBttnState));
  } else
    s = CAlloc(sizeof(CCtrlBttnState));
  s->num_states = num_states;
  s->state_texts = state_texts;
  s->state_colors = state_colors;
  res->win_task = task;
  res->flags = CTRLF_SHOW;
  res->type = CTRLT_GENERIC;
  res->state = s;
  res->draw_it = &DrawCtrlBttn;
  res->left_click = &LeftClickCtrlBttn;
  res->left = x;
  res->top = y;
  res->right = x + width - 1;
  res->bottom = y + height - 1;
  if (_s)
    s->flags |= BTF_DONT_FREE;
  QueIns(res, task->last_ctrl);
  rv_ctrls_n++;
  return res;
}

public U0 CtrlBttnDel(CCtrl *c)
{
  //Adam CtrlsBttn CtrlBttnDel — free ctrl; keep external CCtrlBttnState.
  CCtrlBttnState *s;
  if (!c)
    return;
  QueRem(c);
  s = c->state(CCtrlBttnState *);
  if (s && !(s->flags & BTF_DONT_FREE))
    Free(s);
  Free(c);
  if (rv_ctrls_n > 0)
    rv_ctrls_n--;
}

public CCtrl *CtrlSliderNew(I64 x, I64 y, I64 height, I64 range, U8 *label = NULL, CTask *task = NULL)
{
  CCtrl *res;
  CCtrlSliderState *s;
  if (!task)
    task = Fs;
  if (!TaskValidate(task))
    return NULL;
  if (range < 4)
    range = 4;
  res = CAlloc(sizeof(CCtrl));
  s = CAlloc(sizeof(CCtrlSliderState));
  s->range = range;
  s->value = range / 2;
  if (label)
    StrCpy(s->label, label);
  else
    StrCpy(s->label, "Sld");
  res->win_task = task;
  res->flags = CTRLF_SHOW;
  res->type = CTRLT_GENERIC;
  res->state = s;
  res->draw_it = &DrawCtrlSlider;
  res->left_click = &LeftClickCtrlSlider;
  res->left = x;
  res->top = y;
  res->right = x + 12;
  res->bottom = y + height - 1;
  QueIns(res, task->last_ctrl);
  rv_ctrls_n++;
  return res;
}

public U0 DrawCtrls(CTask *task)
{
  CCtrl *c;
  CRVDC *dc = rv_gr.dc;
  I64 ox, oy;
  if (!TaskValidate(task) || !dc)
    return;
  CtrlsUpdate(task);
  ox = task->pix_left;
  oy = task->pix_top + FONT_HEIGHT * 5;
  c = task->next_ctrl;
  while (c != &task->next_ctrl) {
    if (c->flags & CTRLF_SHOW && c->draw_it) {
      dc->x0 = ox;
      dc->y0 = oy;
      (*c->draw_it)(dc(CDC *), c);
    }
    c = c->next;
  }
}

U0 RVCtrlsRst()
{
  rv_ctrls_demo_on = 0;
  rv_ctrls_n = 0;
}

U0 RVCtrlsDemoInstall(I64 win_idx)
{
  CRVWin *w;
  CTask *task;
  CCtrl *c, *c1;
  if (win_idx < 0 || win_idx >= RV_WIN_MAX)
    return;
  w = &rv_winmgr.wins[win_idx];
  task = w->task;
  if (!TaskValidate(task))
    task = Fs;
  c = task->next_ctrl;
  while (c != &task->next_ctrl) {
    c1 = c->next;
    if (c->type == CTRLT_GENERIC) {
      QueRem(c);
      Free(c->state);
      Free(c);
      if (rv_ctrls_n > 0)
        rv_ctrls_n--;
    }
    c = c1;
  }
  CtrlBttnNew(8, 8, 72, 22, 2, "Go\0On\0", &rv_ctrl_bttn_colors, NULL, task);
  CtrlSliderNew(96, 8, 64, 40, "Lvl", task);
  WinScrollsInit(task);
  ViewAnglesNew(task);
  rv_ctrls_demo_on = 1;
  rv_ctrls_hits++;
  Print("RVCtrls demo install win=%d n=%d hits=%d queue=1 scroll=1 view=1\n", win_idx, rv_ctrls_n, rv_ctrls_hits);
}

Bool RVCtrlsActive()
{
  return rv_ctrls_demo_on && rv_ctrls_n > 0;
}

U0 RVCtrlsDrawWin(I64 win_idx, CRVDC *dc)
{
  CRVWin *w;
  no_warn dc;
  if (win_idx < 0 || win_idx >= RV_WIN_MAX || !rv_ctrls_demo_on)
    return;
  w = &rv_winmgr.wins[win_idx];
  if (!w->used || !w->show)
    return;
  if (TaskValidate(w->task))
    DrawCtrls(w->task);
  else if (TaskValidate(Fs))
    DrawCtrls(Fs);
}

Bool RVCtrlsClick(I64 cx, I64 cy)
{
  I64 hit, px, py;
  CRVWin *w;
  CTask *task;
  CCtrl *c;
  if (!rv_ctrls_demo_on)
    return FALSE;
  hit = rv_winmgr.focus;
  if (hit < 0)
    return FALSE;
  w = &rv_winmgr.wins[hit];
  if (!w->used || !w->show)
    return FALSE;
  task = w->task;
  if (!TaskValidate(task))
    task = Fs;
  if (!TaskValidate(task))
    return FALSE;
  CtrlsUpdate(task);
  px = cx *FONT_WIDTH + FONT_WIDTH / 2;
  py = cy *FONT_HEIGHT + FONT_HEIGHT / 2;
  c = task->next_ctrl;
  while (c != &task->next_ctrl) {
    if ((c->flags & CTRLF_SHOW) && CtrlInside(c, px, py)) {
      if (c->left_click) {
        (*c->left_click)(c, px - task->pix_left, py - (task->pix_top + FONT_HEIGHT * 5), TRUE);
        return TRUE;
      }
    }
    c = c->next;
  }
  return FALSE;
}
// ---- WinScroll (Adam/CtrlsA shape on CRVDC) ----
#define WIN_SCROLL_SIZE         8
#define WIN_SCROLL_BORDER_BONUS 4
I64 rv_winscroll_hits;
U0 DrawWinScroll(CDC *_dc, CCtrl *c)
{
  CRVDC *dc = _dc(CRVDC *);
  CWinScroll *s;
  I64 col;
  if (!dc || !c)
    return;
  s = c->state(CWinScroll *);
  if (!s)
    return;
  if (c->flags & CTRLF_CLICKED)
    col = s->color >> 4;
  else
    col = s->color & 15;
  dc->color = RVColor(col);
  GrRect(dc, c->left, c->top, c->right - c->left + 1, c->bottom - c->top + 1);
  if (c->flags & CTRLF_CLICKED)
    col = s->color & 15;
  else
    col = s->color >> 4;
  dc->color = RVColor(col);
  GrRect(dc, c->left + 2, c->top + 2, c->right - c->left - 3, c->bottom - c->top - 3);
}

U0 WinDerivedScrollValsUpdate(CCtrl *c)
{
  CWinScroll *s;
  I64 range;
  if (!c || !c->win_task)
    return;
  s = c->state(CWinScroll *);
  if (!s)
    return;
  if (s->max < s->min)
    s->max = s->min;
  if (s->pos < s->min)
    s->pos = s->min;
  if (s->pos > s->max)
    s->pos = s->max;
  s->color = c->win_task->border_attr & 15 ^ 15 + (c->win_task->border_attr & 15) << 4;
  range = s->max - s->min;
  if (!range)
    range = 1;
  switch (c->type) {
    case CTRLT_WIN_HSCROLL :
    c->left = FONT_WIDTH - WIN_SCROLL_BORDER_BONUS + (s->pos - s->min) * (c->win_task->pix_width + 2 * WIN_SCROLL_BORDER_BONUS - WIN_SCROLL_SIZE) / range;
    c->right = c->left + WIN_SCROLL_SIZE - 1;
    c->top = FONT_HEIGHT + (FONT_WIDTH - WIN_SCROLL_SIZE) / 2 + c->win_task->pix_height;
    c->bottom = c->top + WIN_SCROLL_SIZE - 1;
    break;
    case CTRLT_WIN_VSCROLL :
    c->left = FONT_WIDTH + (FONT_WIDTH - WIN_SCROLL_SIZE) / 2 + c->win_task->pix_width;
    c->right = c->left + WIN_SCROLL_SIZE - 1;
    c->top = FONT_HEIGHT - WIN_SCROLL_BORDER_BONUS + (s->pos - s->min) * (c->win_task->pix_height + 2 * WIN_SCROLL_BORDER_BONUS - WIN_SCROLL_SIZE) / range;
    c->bottom = c->top + WIN_SCROLL_SIZE - 1;
    break;
  }
}

U0 LeftClickHWinScroll(CCtrl *c, I64 x, I64, Bool down)
{
  CTask *task;
  CWinScroll *s;
  I64 range;
  if (!c)
    return;
  task = c->win_task;
  s = c->state(CWinScroll *);
  if (!task || !s)
    return;
  range = task->pix_width + 2 * WIN_SCROLL_BORDER_BONUS - WIN_SCROLL_SIZE;
  if (range < 1)
    range = 1;
  LBts(&s->flags, WSSf_SET_TO_POS);
  s->pos = ((x - (FONT_WIDTH - WIN_SCROLL_BORDER_BONUS)) * (s->max - s->min + 1) + range / 2) / range + s->min;
  if (down)
    c->flags |= CTRLF_CLICKED;
  else
    c->flags &= ~CTRLF_CLICKED;
  rv_winscroll_hits++;
  if (c->update_derived_vals)
    (*c->update_derived_vals)(c);
}

U0 LeftClickVWinScroll(CCtrl *c, I64, I64 y, Bool down)
{
  CTask *task;
  CWinScroll *s;
  I64 range;
  if (!c)
    return;
  task = c->win_task;
  s = c->state(CWinScroll *);
  if (!task || !s)
    return;
  range = task->pix_height + 2 * WIN_SCROLL_BORDER_BONUS - WIN_SCROLL_SIZE;
  if (range < 1)
    range = 1;
  LBts(&s->flags, WSSf_SET_TO_POS);
  s->pos = ((y - (FONT_HEIGHT - WIN_SCROLL_BORDER_BONUS)) * (s->max - s->min + 1) + range / 2) / range + s->min;
  if (down)
    c->flags |= CTRLF_CLICKED;
  else
    c->flags &= ~CTRLF_CLICKED;
  rv_winscroll_hits++;
  if (c->update_derived_vals)
    (*c->update_derived_vals)(c);
}

U0 WheelChangeWinScroll(CCtrl *c, I64 delta)
{
  CWinScroll *s;
  if (!c)
    return;
  s = c->state(CWinScroll *);
  if (!s)
    return;
  LBts(&s->flags, WSSf_SET_TO_POS);
  s->pos += delta;
  rv_winscroll_hits++;
  if (c->update_derived_vals)
    (*c->update_derived_vals)(c);
}

public U0 WinScrollsInit(CTask *task)
{
  //Adam CtrlsA WinScrollsInit — horz/vert border thumbs on task.
  CCtrl *c;
  if (!task)
    task = Fs;
  if (!TaskValidate(task))
    return;
  if (!CtrlFindUnique(task, CTRLT_WIN_HSCROLL)) {
    c = CAlloc(sizeof(CCtrl));
    c->win_task = task;
    c->flags = CTRLF_SHOW | CTRLF_BORDER | CTRLF_CAPTURE_LEFT_MS;
    c->type = CTRLT_WIN_HSCROLL;
    c->state = &task->horz_scroll;
    c->update_derived_vals = &WinDerivedScrollValsUpdate;
    c->draw_it = &DrawWinScroll;
    c->left_click = &LeftClickHWinScroll;
    QueIns(c, task->last_ctrl);
    rv_ctrls_n++;
  }
  if (!CtrlFindUnique(task, CTRLT_WIN_VSCROLL)) {
    c = CAlloc(sizeof(CCtrl));
    c->win_task = task;
    c->flags = CTRLF_SHOW | CTRLF_BORDER | CTRLF_CAPTURE_LEFT_MS;
    c->type = CTRLT_WIN_VSCROLL;
    c->state = &task->vert_scroll;
    c->update_derived_vals = &WinDerivedScrollValsUpdate;
    c->draw_it = &DrawWinScroll;
    c->left_click = &LeftClickVWinScroll;
    c->wheel_chg = &WheelChangeWinScroll;
    QueIns(c, task->last_ctrl);
    rv_ctrls_n++;
  }
  TaskDerivedValsUpdate(task);
}
// ---- ViewAngles (Adam/CtrlsA shape on CRVDC) ----
#define VIEWANGLES_SPACING  22
#define VIEWANGLES_RANGE    360
#define VIEWANGLES_BORDER   2
#define VIEWANGLES_SNAP     1
I64 rv_viewangles_hits;
U0 DrawViewAnglesCtrl(CDC *_dc, CCtrl *c)
{
  CRVDC *dc = _dc(CRVDC *);
  CViewAngles *s;
  I64 i, j;
  U8 buf[8];
  if (!dc || !c)
    return;
  s = c->state(CViewAngles *);
  if (!s)
    return;
  dc->color = RVColor(s->cbd & 15);
  GrRect(dc, c->left, c->top, VIEWANGLES_SPACING * 4 + 3, VIEWANGLES_SPACING * 2 + VIEWANGLES_RANGE);
  dc->color = RVColor(s->cbg & 15);
  GrRect(dc, c->left + VIEWANGLES_BORDER, c->top + VIEWANGLES_BORDER, VIEWANGLES_SPACING * 4 + 3 - 2 * VIEWANGLES_BORDER, VIEWANGLES_SPACING * 2 + VIEWANGLES_RANGE - 2 * VIEWANGLES_BORDER);
  dc->color = RVColor(s->cfg & 15);
  GrLine(dc, c->left + VIEWANGLES_SPACING, c->top + VIEWANGLES_SPACING, c->left + VIEWANGLES_SPACING, c->top + VIEWANGLES_SPACING + VIEWANGLES_RANGE - 1);
  GrLine(dc, c->left + 2 * VIEWANGLES_SPACING + 1, c->top + VIEWANGLES_SPACING, c->left + 2 * VIEWANGLES_SPACING + 1, c->top + VIEWANGLES_SPACING + VIEWANGLES_RANGE - 1);
  GrLine(dc, c->left + 3 * VIEWANGLES_SPACING + 2, c->top + VIEWANGLES_SPACING, c->left + 3 * VIEWANGLES_SPACING + 2, c->top + VIEWANGLES_SPACING + VIEWANGLES_RANGE - 1);
  dc->color = RVColor(s->cx & 15);
  GrPrint(dc, c->left + VIEWANGLES_SPACING - FONT_WIDTH / 2, c->top + VIEWANGLES_SPACING - (1 + FONT_HEIGHT), "X");
  StrPrint(buf, "%3d", s->sx * 360 / VIEWANGLES_RANGE);
  GrPrint(dc, c->left + VIEWANGLES_SPACING - 3 * FONT_WIDTH / 2, c->top + VIEWANGLES_SPACING + VIEWANGLES_RANGE + 3, buf);
  i = c->left + VIEWANGLES_SPACING;
  if (s->sx > VIEWANGLES_RANGE / 2)
    j = -VIEWANGLES_RANGE / 2 + s->sx;
  else
    j = s->sx + VIEWANGLES_RANGE / 2;
  j = c->top + VIEWANGLES_SPACING + VIEWANGLES_RANGE - 1 - j;
  GrRect(dc, i - 3, j - 2, 7, 5);
  dc->color = RVColor ((s->cx & 15) ^ 8);
  GrRect(dc, i - 2, j - 1, 5, 3);
  dc->color = RVColor(s->cy & 15);
  GrPrint(dc, c->left + 2 * VIEWANGLES_SPACING + 1 - FONT_WIDTH / 2, c->top + VIEWANGLES_SPACING - (1 + FONT_HEIGHT), "Y");
  StrPrint(buf, "%3d", s->sy * 360 / VIEWANGLES_RANGE);
  GrPrint(dc, c->left + 2 * VIEWANGLES_SPACING + 1 - 3 * FONT_WIDTH / 2, c->top + VIEWANGLES_SPACING + VIEWANGLES_RANGE + 3, buf);
  i = c->left + 2 * VIEWANGLES_SPACING + 1;
  if (s->sy > VIEWANGLES_RANGE / 2)
    j = -VIEWANGLES_RANGE / 2 + s->sy;
  else
    j = s->sy + VIEWANGLES_RANGE / 2;
  j = c->top + VIEWANGLES_SPACING + VIEWANGLES_RANGE - 1 - j;
  GrRect(dc, i - 3, j - 2, 7, 5);
  dc->color = RVColor ((s->cy & 15) ^ 8);
  GrRect(dc, i - 2, j - 1, 5, 3);
  dc->color = RVColor(s->cz & 15);
  GrPrint(dc, c->left + 3 * VIEWANGLES_SPACING + 2 - FONT_WIDTH / 2, c->top + VIEWANGLES_SPACING - (1 + FONT_HEIGHT), "Z");
  StrPrint(buf, "%3d", s->sz * 360 / VIEWANGLES_RANGE);
  GrPrint(dc, c->left + 3 * VIEWANGLES_SPACING + 2 - 3 * FONT_WIDTH / 2, c->top + VIEWANGLES_SPACING + VIEWANGLES_RANGE + 3, buf);
  i = c->left + 3 * VIEWANGLES_SPACING + 2;
  if (s->sz > VIEWANGLES_RANGE / 2)
    j = -VIEWANGLES_RANGE / 2 + s->sz;
  else
    j = s->sz + VIEWANGLES_RANGE / 2;
  j = c->top + VIEWANGLES_SPACING + VIEWANGLES_RANGE - 1 - j;
  GrRect(dc, i - 3, j - 2, 7, 5);
  dc->color = RVColor ((s->cz & 15) ^ 8);
  GrRect(dc, i - 2, j - 1, 5, 3);
}

U0 UpdateDerivedViewAnglesCtrl(CCtrl *c)
{
  CViewAngles *s;
  if (!c || !c->win_task)
    return;
  s = c->state(CViewAngles *);
  if (!s)
    return;
  c->left = c->win_task->pix_width - (VIEWANGLES_SPACING * 4 + 3);
  c->right = c->left + VIEWANGLES_SPACING * 4 + 3;
  c->top = c->win_task->pix_height - (VIEWANGLES_SPACING * 2 + VIEWANGLES_RANGE);
  c->bottom = c->top + VIEWANGLES_SPACING * 2 + VIEWANGLES_RANGE;
  s->sx = ClampI64(s->sx, 0, VIEWANGLES_RANGE - 1);
  s->sy = ClampI64(s->sy, 0, VIEWANGLES_RANGE - 1);
  s->sz = ClampI64(s->sz, 0, VIEWANGLES_RANGE - 1);
  s->ax = 2 * pi *s->sx / VIEWANGLES_RANGE;
  s->ay = 2 * pi *s->sy / VIEWANGLES_RANGE;
  s->az = 2 * pi *s->sz / VIEWANGLES_RANGE;
}

U0 LeftClickViewAngles(CCtrl *c, I64 x, I64 y, Bool)
{
  CViewAngles *s;
  I64 i;
  if (!c)
    return;
  s = c->state(CViewAngles *);
  if (!s)
    return;
  i = VIEWANGLES_RANGE - 1 - (y - (c->top + VIEWANGLES_SPACING));
  if (i >= VIEWANGLES_RANGE / 2)
    i -= VIEWANGLES_RANGE / 2;
  else
    i += VIEWANGLES_RANGE / 2;
  if (x < c->left + (c->right - c->left) / 3)
    s->sx = i;
  else if (x < c->left + 2 * (c->right - c->left) / 3)
    s->sy = i;
  else
    s->sz = i;
  rv_viewangles_hits++;
  if (c->update_derived_vals)
    (*c->update_derived_vals)(c);
}

public CCtrl *ViewAnglesNew(CTask *task = NULL)
{
  //Adam CtrlsA ViewAnglesNew — XYZ angle sliders.
  CCtrl *c;
  CViewAngles *s;
  if (!task)
    task = Fs;
  if (!TaskValidate(task))
    return NULL;
  if (!(c = CtrlFindUnique(task, CTRLT_VIEWING_ANGLES))) {
    s = CAlloc(sizeof(CViewAngles), task);
    c = CAlloc(sizeof(CCtrl));
    s->cbd = BLUE;
    s->cbg = LTBLUE;
    s->cfg = BLACK;
    s->cx = LTGREEN;
    s->cy = GREEN;
    s->cz = LTGREEN;
    c->win_task = task;
    c->flags = CTRLF_SHOW | CTRLF_CAPTURE_LEFT_MS;
    c->type = CTRLT_VIEWING_ANGLES;
    c->state = s;
    c->draw_it = &DrawViewAnglesCtrl;
    c->left_click = &LeftClickViewAngles;
    c->update_derived_vals = &UpdateDerivedViewAnglesCtrl;
    QueIns(c, task->last_ctrl);
    rv_ctrls_n++;
    TaskDerivedValsUpdate(task);
  }
  return c;
}

public U0 ViewAnglesDel(CTask *task = NULL)
{
  CCtrl *c;
  if (!task)
    task = Fs;
  if (!TaskValidate(task))
    return;
  if (c = CtrlFindUnique(task, CTRLT_VIEWING_ANGLES)) {
    QueRem(c);
    Free(c->state);
    Free(c);
    if (rv_ctrls_n > 0)
      rv_ctrls_n--;
  }
}
#endif
