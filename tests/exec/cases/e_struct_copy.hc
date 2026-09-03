// Whole-struct assignment `b = a` copies ALL fields of a class instance larger than one word
// (previously only the first 8 bytes were copied). Pointers and 8-byte classes keep single-word
// assignment; a source field changed afterwards must not affect the copy (independent copy).
class P
{
  I64 x, y, z;
};

class M
{
  I64 a;
  I32 b;
  I16 c;
  U8 d;
};
// 15 bytes of payload — exercises the byte tail
P gsrc;
P gdst;
I64 main()
{
  P a;
  a.x = 1;
  a.y = 2;
  a.z = 3;
  P b;
  b.x = b.y = b.z = 0;
  b = a;
  b.x = 99;
  // independent copy
  I64 local = (b.x == 99) & (b.y == 2) & (b.z == 3) & (a.x == 1);
  gsrc.x = 7;
  gsrc.y = 8;
  gsrc.z = 9;
  gdst = gsrc;
  gsrc.x = 0;
  I64 glob = (gdst.x == 7) & (gdst.y == 8) & (gdst.z == 9);
  M s;
  s.a = 100;
  s.b = 200;
  s.c = 300;
  s.d = 44;
  M t;
  t = s;
  I64 mix = (t.a == 100) & (t.b == 200) & (t.c == 300) & (t.d == 44);
  P *p;
  P *q = &a;
  p = q;
  // pointer assignment stays 8-byte
  I64 ptr = (p == &a) & (p->x == 1);
  return local * 1 + glob * 2 + mix * 4 + ptr * 8;
  // 0xf
}
