// scratch: does a runtime I64 expression survive as a `U16 class` by-value arg?
// Mirrors Compiler/BackA_RV.HC ICMov(CICType t1, ..., CICType t2, ...) called
// from ICPostIncDec with `MDF_DISP + tmpi->arg1_type_pointed_to` inline.
U16 class TProbe
{
  U8 raw, mode;
};

class TNode
{
  TNode *next, *last;
  U16 a, b;
  I16 c, d;
  I64 flags, data, line;
  U8 *cls, *cls2;
  I64 pad0, pad1, pad2, pad3, pad4, pad5;
  U8 pt;
};

I64 g_seen1;
I64 g_seen2;
I64 g_seenr1;

U0 Sink(TNode *n, TProbe t1, I64 r1, I64 d1, TProbe t2, I64 r2, I64 d2, I64 rip)
{
  n = n;
  d1 = d1;
  r2 = r2;
  d2 = d2;
  rip = rip;
  g_seen1 = t1(U16);
  g_seen2 = t2(U16);
  g_seenr1 = r1;
}

U0 Bump(TNode *n, I64 rip)
{
  TProbe staged;
  // Inline computed U16-class arg in slot 2 (the ICPostIncDec write-back shape).
  Sink(n, 0x0800 + n->pt, 10, 0, 0x0400 + 10, 6, 0, rip);
  n->data = g_seen1;
  // Same value staged into a typed local first (the ICAssign tloc shape).
  staged = 0x0800 + n->pt;
  Sink(n, staged, 10, 0, 0x0400 + 10, 6, 0, rip);
  n->line = g_seen1;
}

I64 main()
{
  I64 r = 0;
  TNode n;
  MemSet(&n, 0, sizeof(TNode));
  n.pt = 10;
  Bump(&n, 0x1000);
  return n.data;
  // staged local: expected to pass
  r += (n.data == 0x080A) * 2;
  // inline expression: the suspect
  r += (g_seen2 == 0x040A) * 4;
  r += (g_seenr1 == 10) * 8;
  return r;
}
