// Verifies native RISC-V QueInit/QueIns/QueRem in KUtilsRV.HC (doubly-linked circular queue).
#include "/Kernel/Kernel_RV.PRJ"
class QN
{
  QN *next, *last;
  I64 val;
};

I64 main()
{
  QN h, a, b;
  QueInit(&h);
  QueIns(&a, &h);
  // h <-> a
  QueIns(&b, &h);
  // h -> b -> a -> h
  I64 r = 0;
  QN *p = h.next;
  r += (p == &b) * 1;
  r += (p->next == &a) * 2;
  r += (p->next->next == &h) * 4;
  r += (h.last == &a) * 8;
  QueRem(&b);
  // h -> a -> h
  r += (h.next == &a) * 16;
  r += (a.last == &h) * 32;
  return r;
  // 0x3F
}
