// F64 through pointers/address-of: `&x` is a pointer (not F64), `*p` of an F64* is F64.
class Pt
{
  F64 x, y;
};

I64 main()
{
  F64 v = 3.5;
  F64 *p = &v;
  Pt s;
  s.x = 2.5;
  F64 *m = &s.x;
  return (p == &v) * 1 + (ToI64 (*p * 2.0) == 7) * 2 + (*p == 3.5) * 4 + ((&v) > 0x1000) * 8 + (ToI64 (*m * 4.0) == 10) * 16 + (m == &s.x) * 32;
  // 0x3f
}
