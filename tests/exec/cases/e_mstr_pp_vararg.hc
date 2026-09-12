// MStrPrint-shaped call: U8 *fmt string + U32 member++ as HolyC vararg.
// Take(I64,...) alone was green; FRAME_SLOT used to fold `v=MStrPrint(fmt,p->n++)`
// onto v and poison argv (DocSpriteIns / PsmMenu BI=17).
class CDocLike
{
  U32 sig, cur_bin_num;
  I64 max_entries;
};

U8 *Join1(U8 *fmt,...)
{
  no_warn fmt;
  if (argc < 1)
    return 0;
  return argv[0];
}

I64 main()
{
  CDocLike d;
  CDocLike *p = &d;
  U8 *st;
  I64 r = 0;
  d.sig = 0xAABBCCDD;
  d.cur_bin_num = 17;
  d.max_entries = 0x1111111122222222;
  st = Join1("$$SP,\"\",BI=%d$$", p->cur_bin_num++);
  r += (st(I64) == 17) * 1;
  r += (p->cur_bin_num == 18) * 2;
  r += (p->max_entries == 0x1111111122222222) * 4;
  st = Join1("%d", p->cur_bin_num++);
  r += (st(I64) == 18) * 8;
  r += (p->cur_bin_num == 19) * 16;
  r += (p->max_entries == 0x1111111122222222) * 32;
  r += (p->sig == 0xAABBCCDD) * 64;
  return r;
  // 0x7F
}
