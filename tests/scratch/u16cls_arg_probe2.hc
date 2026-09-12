// scratch: when does `CONST + ptr->u8_member` get scaled by sizeof(*ptr)?
class TNode
{
  I64 a, b, c;
  U8 pt;
};

U16 class TProbe
{
  U8 raw, mode;
};

I64 g_t1;
I64 g_t2;

U0 SinkCls(TNode *n, TProbe t1, I64 r1, I64 d1, TProbe t2, I64 r2, I64 d2, I64 rip)
{
  n = n;
  r1 = r1;
  d1 = d1;
  r2 = r2;
  d2 = d2;
  rip = rip;
  g_t1 = t1(U16);
  g_t2 = t2(U16);
}

U0 SinkI64(TNode *n, I64 t1, I64 r1, I64 d1, I64 t2, I64 r2, I64 d2, I64 rip)
{
  n = n;
  r1 = r1;
  d1 = d1;
  r2 = r2;
  d2 = d2;
  rip = rip;
  g_t1 = t1;
  g_t2 = t2;
}

I64 PlainAdd(TNode *n)
{
  return 0x800 + n->pt;
}

U0 BumpPtr(TNode *n, I64 rip)
{
  SinkCls(n, 0x800 + n->pt, 10, 0, 0x400 + 10, 6, 0, rip);
  n->a = g_t1;
  SinkCls(n, 0x400 + 10, 10, 0, 0x800 + n->pt, 6, 0, rip);
  n->b = g_t2;
  SinkI64(n, 0x800 + n->pt, 10, 0, 0x400 + 10, 6, 0, rip);
  n->c = g_t1;
}

I64 main()
{
  I64 r = 0;
  TNode n;
  MemSet(&n, 0, sizeof(TNode));
  n.pt = 10;
  // 1) plain return of the same expression
  r += (PlainAdd(&n) == 0x080A) * 1;
  // 2) computed expr in the I64 slot 2 of an 8-arg call
  SinkI64(&n, 0x800 + n.pt, 10, 0, 0x400 + 10, 6, 0, 0);
  r += (g_t1 == 0x080A) * 2;
  // 3) computed expr in the U16-class slot 5 (load shape) - class slot 2 const
  SinkCls(&n, 0x400 + 10, 10, 0, 0x800 + n.pt, 6, 0, 0);
  r += (g_t2 == 0x080A) * 4;
  // 4) computed expr in the U16-class slot 2 (write-back shape)
  SinkCls(&n, 0x800 + n.pt, 10, 0, 0x400 + 10, 6, 0, 0);
  r += (g_t1 == 0x080A) * 8;
  // 5) same three shapes, but `n` is a TNode* parameter and member is `n->pt`
  BumpPtr(&n, 0);
  r += (n.a == 0x080A) * 16;
  r += (n.b == 0x080A) * 32;
  r += (n.c == 0x080A) * 64;
  return r;
}
