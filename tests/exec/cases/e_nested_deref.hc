// Nested pointer deref: *(U8 **) and load-then-call through I64 slot.
U8 g_ch;
U8 *g_p;
U8 **g_pp;
I64 Add(I64 a, I64 b)
{
  return a + b;
}
I64 g_slot;
I64 main()
{
  I64 (*fp)(I64, I64);
  I64 r;
  g_ch = 7;
  g_p = &g_ch;
  g_pp = &g_p;
  // classic double deref of U8**
  if (*g_pp != &g_ch)
    return 1;
  if (**g_pp != 7)
    return 2;
  // cast form used at host slots
  if (*(U8 **)(&g_p) != &g_ch)
    return 3;
  if (**(U8 **)(&g_p) != 7)
    return 4;
  // funptr via slot (once-indirect call)
  g_slot = &Add;
  fp = *(I64 *)(&g_slot);
  r = fp(10, 20);
  if (r != 30)
    return 5;
  // (*(*(I64*)&slot))(a,b) — load then call
  r = (*(*(I64 *)(&g_slot)))(11, 22);
  if (r != 33)
    return 6;
  return 0;
}
