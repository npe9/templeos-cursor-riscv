// F64 compound assignment (`d *= x`, `+= -= /=`) uses F64 arithmetic, not integer bit ops.
class V
{
  F64 s;
};

I64 main()
{
  F64 d = 10.0;
  d += 2.5;
  d -= 0.5;
  d /= 3.0;
  // 4.0
  F64 e = 3.25;
  e *= 1000.0;
  // 3250
  F64 a[2];
  a[0] = 2.0;
  a[0] *= 1.5;
  // 3.0
  V v;
  v.s = 8.0;
  v.s /= 2.0;
  // 4.0
  return (ToI64(d) == 4) * 1 + (ToI64(e) == 3250) * 2 + (ToI64(a[0]) == 3) * 4 + (ToI64(v.s) == 4) * 8 + (ToI64(d * 100.0) == 400) * 16 + (e > 3249.0) * 32;
  // 0x3f
}
