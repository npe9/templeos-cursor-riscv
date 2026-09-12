// Host typed EmitIncDec: U32 member++ as HolyC vararg must not ld/sd into adjacent I64
// (stock DocSprite MStrPrint(fmt, doc->cur_bin_num++); CDoc packs cur_bin_num next to max_entries).
class CDocLike
{
  U32 sig, cur_bin_num;
  I64 max_entries;
};

class CU32Pad
{
  U32 n;
  I64 pad;
};

I64 Take(I64 a,...)
{
  if (argc < 1)
    return a;
  return argv[0];
}

I64 main()
{
  CDocLike d;
  CDocLike *p = &d;
  CU32Pad u;
  CU32Pad *q = &u;
  I64 r = 0, v;
  d.sig = 0xAABBCCDD;
  d.cur_bin_num = 3;
  d.max_entries = 0x1111111122222222;
  v = Take(0, p->cur_bin_num++);
  r += (v == 3) * 1;
  r += (p->cur_bin_num == 4) * 2;
  r += (p->sig == 0xAABBCCDD) * 4;
  r += (p->max_entries == 0x1111111122222222) * 8;
  v = Take(0, p->cur_bin_num++);
  r += (v == 4) * 16;
  r += (p->cur_bin_num == 5) * 32;
  r += (p->max_entries == 0x1111111122222222) * 64;
  u.n = 9;
  u.pad = -1;
  v = Take(0, q->n++);
  r += (v == 9 && q->n == 10 && q->pad == -1) * 128;
  return r;
  // 0xFF
}
