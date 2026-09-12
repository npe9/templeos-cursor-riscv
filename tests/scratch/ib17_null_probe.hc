#include "/tos/Apps/Psalmody/PsalmodyDraw.HC"
I64 main() {
  U8 *p = $IB,"<17>",BI=17$;
  U8 *p3 = $IB,"<3>",BI=3$;
  I64 r = 0;
  r += (p != NULL) * 1;
  r += (p3 != NULL) * 2;
  if (p) r += (*p == 1) * 4; // COLOR
  if (p3) r += (*p3 == 10) * 8; // LINE
  return r;
}
