// KMathA_RV — HolyC D3* replacing x86 FPU asm in KMathA.HC (skipped on RV).
// Abs/Sqr native asm live in KUtilsRV; Sign/Ceil still holy_rt / later port.
CD3 *D3Zero(CD3 *dst)
{
  dst->x = 0.0;
  dst->y = 0.0;
  dst->z = 0.0;
  return dst;
}

CD3 *D3Copy(CD3 *dst, CD3 *src)
{
  dst->x = src->x;
  dst->y = src->y;
  dst->z = src->z;
  return dst;
}

CD3 *D3Equ(CD3 *dst, F64 x = 0, F64 y = 0, F64 z = 0)
{
  dst->x = x;
  dst->y = y;
  dst->z = z;
  return dst;
}

CD3 *D3Add(CD3 *sum, CD3 *d1, CD3 *d2)
{
  sum->x = d1->x + d2->x;
  sum->y = d1->y + d2->y;
  sum->z = d1->z + d2->z;
  return sum;
}

CD3 *D3Sub(CD3 *diff, CD3 *d1, CD3 *d2)
{
  diff->x = d1->x - d2->x;
  diff->y = d1->y - d2->y;
  diff->z = d1->z - d2->z;
  return diff;
}

CD3 *D3Mul(CD3 *prod, F64 s, CD3 *d)
{
  prod->x = s *d->x;
  prod->y = s *d->y;
  prod->z = s *d->z;
  return prod;
}

CD3 *D3Div(CD3 *quot, CD3 *d, F64 s)
{
  quot->x = d->x / s;
  quot->y = d->y / s;
  quot->z = d->z / s;
  return quot;
}

CD3 *D3AddEqu(CD3 *sum, CD3 *d)
{
  sum->x += d->x;
  sum->y += d->y;
  sum->z += d->z;
  return sum;
}

CD3 *D3SubEqu(CD3 *diff, CD3 *d)
{
  diff->x -= d->x;
  diff->y -= d->y;
  diff->z -= d->z;
  return diff;
}

CD3 *D3MulEqu(CD3 *prod, F64 s)
{
  prod->x *= s;
  prod->y *= s;
  prod->z *= s;
  return prod;
}

CD3 *D3DivEqu(CD3 *quot, F64 s)
{
  quot->x /= s;
  quot->y /= s;
  quot->z /= s;
  return quot;
}

F64 D3NormSqr(CD3 *d)
{
  return d->x *d->x + d->y *d->y + d->z *d->z;
}

F64 D3Norm(CD3 *d)
{
  return Sqrt(D3NormSqr(d));
}

F64 D3DistSqr(CD3 *d1, CD3 *d2)
{
  F64 dx = d1->x - d2->x, dy = d1->y - d2->y, dz = d1->z - d2->z;
  return dx *dx + dy *dy + dz *dz;
}

F64 D3Dist(CD3 *d1, CD3 *d2)
{
  return Sqrt(D3DistSqr(d1, d2));
}

F64 D3Dot(CD3 *d1, CD3 *d2)
{
  return d1->x *d2->x + d1->y *d2->y + d1->z *d2->z;
}

CD3 *D3Cross(CD3 *prod, CD3 *d1, CD3 *d2)
{
  prod->x = d1->y *d2->z - d1->z *d2->y;
  prod->y = d1->z *d2->x - d1->x *d2->z;
  prod->z = d1->x *d2->y - d1->y *d2->x;
  return prod;
}

CD3 *D3Unit(CD3 *d)
{
  F64 n = D3Norm(d);
  if (n)
    D3DivEqu(d, n);
  return d;
}
