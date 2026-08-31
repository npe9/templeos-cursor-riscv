// RVTextBase.HC — TempleOS TextChar/TextPrint/TextRect/TextBorder on RVWinMgr text_base.
// Replaces Adam/Gr/GrTextBase.HC x86 asm for DocRecalc / draw_it on RISC-V.
// Cell layout matches Doc/TextBase.DD (ASCII + attr<<8). Task clipping uses win_* fields.
Bool TextChar(CTask *task, Bool allow_border = FALSE, I64 x, I64 y, I64 d)
{
  //Plot one text_base cell in task window coords (TempleOS TextChar).
  I64 xx, yy;
  if (!rv_winmgr.ready || !task)
    return FALSE;
  xx = x + (task->scroll_x >> 3);
  yy = y + (task->scroll_y >> 3);
  if (!allow_border) {
    if (xx < 0 || xx > task->win_right - task->win_left)
      return FALSE;
    if (yy < 0 || yy > task->win_bottom - task->win_top)
      return FALSE;
  }
  xx += task->win_left;
  yy += task->win_top;
  if (xx < 0 || yy < 0 || xx >= rv_winmgr.cols || yy >= rv_winmgr.rows)
    return FALSE;
  RVTextChar(xx, yy, d);
  return TRUE;
}

U0 TextRect(I64 l, I64 r, I64 t, I64 b, I64 d)
{
  RVTextRect(l, r, t, b, d);
}

U0 TextBorder(I64 l, I64 r, I64 t, I64 b, I64 attr, Bool solid = TRUE)
{
  RVTextBorder(l, r, t, b, attr, solid);
}

Bool TextPrint(CTask *task, I64 x, I64 y, I64 attr, U8 *st)
{
  //TempleOS TextPrint (plain string). Use StrPrint then TextPrint for fmt.
  I64 xx, yy, a;
  if (!task || !st || !rv_winmgr.ready)
    return FALSE;
  a = attr << 8;
  xx = x + (task->scroll_x >> 3) + task->win_left;
  yy = y + (task->scroll_y >> 3) + task->win_top;
  while (*st) {
    if (*st == '\n') {
      xx = task->win_left + x + (task->scroll_x >> 3);
      yy++;
      st++;
      continue;
    }
    if (xx >= 0 && yy >= 0 && xx < rv_winmgr.cols && yy < rv_winmgr.rows)
      rv_winmgr.text_base[yy *rv_winmgr.cols + xx] = (*st & 255) + a;
    xx++;
    st++;
  }
  return TRUE;
}
