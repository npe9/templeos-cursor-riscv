//Press <F5> to compile and run.
U0 NetOfDots()
{
  I64 i;
  CDC *dc = DCAlias;
  DocClear;
  dc->color = RED;
  for (i = 0; i < 480; i += 20)
    GrLine(dc, i, 0, 0, 480 - i, 3);
  DCDel(dc);
#ifndef RV_DEMO_KEEP_FRAME
  PressAKey;
  DCFill;
#endif
}
#ifndef RV_NO_DEMO_AUTORUN
NetOfDots;
//Run when #included
#endif
