// math.hc -- F64 / bit helpers in HolyC (+ FPU/rdtime asm). No C RuntimeRegister.
#define RT_LN2 0.6931471805599453
#define RT_PI 3.141592653589793
#define RT_PI2 1.5707963267948966
asm {
	HcRdTime::
	rdtime	a0
	ret
}

F64 Sqrt(F64 x)
{
  F64 r;
  I64 i;
  if (x <= 0)
    return 0;
  r = x;
  if (r < 1)
    r = 1;
  for (i = 0; i < 24; i++)
    r = 0.5 * (r + x / r);
  return r;
}

F64 Abs(F64 x)
{
  if (x < 0)
    return -x;
  return x;
}

I64 Sign(F64 x)
{
  if (x > 0)
    return 1;
  if (x < 0)
    return -1;
  return 0;
}

F64 Floor(F64 x)
{
  I64 i;
  if (x >= 0)
    return ToI64(x);
  i = ToI64(x);
  if (x == i)
    return i;
  return i - 1;
}

F64 Ceil(F64 x)
{
  I64 i;
  if (x <= 0)
    return ToI64(x);
  i = ToI64(x);
  if (x == i)
    return i;
  return i + 1;
}

F64 Trunc(F64 x)
{
  return ToI64(x);
}

F64 Round(F64 x)
{
  if (x >= 0)
    return Floor(x + 0.5);
  return Ceil(x - 0.5);
}

F64 Ln(F64 x)
{
  I64 e, k;
  F64 t, t2, s, p;
  if (x <= 0)
    return 0;
  e = 0;
  while (x >= 2.0) {
    x = x * 0.5;
    e++;
  }
  while (x < 1.0) {
    x = x * 2.0;
    e--;
  }
  t = (x - 1) / (x + 1);
  t2 = t *t;
  s = 0;
  p = t;
  for (k = 1; k < 60; k = k + 2) {
    s = s + p / k;
    p = p *t2;
  }
  return 2 * s + e *RT_LN2;
}

F64 Exp(F64 x)
{
  I64 k, i;
  F64 r, s, term;
  if (x > 700)
    return x;
  if (x < -700)
    return 0;
  k = ToI64(x / RT_LN2 + (x >= 0 ? 0.5 : -0.5));
  r = x - k *RT_LN2;
  s = 1;
  term = 1;
  for (i = 1; i < 30; i++) {
    term = term *r / i;
    s = s + term;
  }
  while (k > 0) {
    s = s * 2;
    k--;
  }
  while (k < 0) {
    s = s * 0.5;
    k++;
  }
  return s;
}

F64 Pow(F64 a, F64 b)
{
  if (b == 0)
    return 1;
  if (a == 0) {
    if (b > 0)
      return 0;
    return 1;
  }
  if (a < 0)
    return 0;
  return Exp(b *Ln(a));
}

F64 Log10(F64 x)
{
  return Ln(x) / 2.302585092994046;
}

F64 Log2(F64 x)
{
  return Ln(x) / RT_LN2;
}

F64 Pow10(F64 x)
{
  return Exp(x * 2.302585092994046);
}

F64 Sin(F64 x)
{
  F64 t, s, x2;
  I64 i;
  x = x - 2 * RT_PI *ToI64(x / (2 * RT_PI));
  if (x > RT_PI)
    x = x - 2 * RT_PI;
  if (x < -RT_PI)
    x = x + 2 * RT_PI;
  t = x;
  s = x;
  x2 = x *x;
  for (i = 1; i < 12; i++) {
    t = -t *x2 / ((2 * i) * (2 * i + 1));
    s = s + t;
  }
  return s;
}

F64 Cos(F64 x)
{
  return Sin(x + RT_PI2);
}

F64 Tan(F64 x)
{
  return Sin(x) / Cos(x);
}

F64 ATan(F64 x)
{
  F64 y, y2, t, s;
  I64 i;
  if (x > 1)
    return RT_PI2 - ATan(1 / x);
  if (x < -1)
    return -RT_PI2 - ATan(1 / x);
  y = x / (1 + Sqrt(1 + x *x));
  y2 = y *y;
  t = y;
  s = y;
  for (i = 1; i < 40; i++) {
    t = -t *y2;
    s = s + t / (2 * i + 1);
  }
  return 2 * s;
}

I64 Bt(I64 *bitfield, I64 bit)
{
  return (bitfield[bit >> 6] >> (bit & 63)) & 1;
}

I64 Bts(I64 *bitfield, I64 bit)
{
  I64 old = Bt(bitfield, bit);
  bitfield[bit >> 6] |= 1 << (bit & 63);
  return old;
}

I64 Btr(I64 *bitfield, I64 bit)
{
  I64 old = Bt(bitfield, bit);
  bitfield[bit >> 6] &= ~(1 << (bit & 63));
  return old;
}

I64 Btc(I64 *bitfield, I64 bit)
{
  I64 old = Bt(bitfield, bit);
  bitfield[bit >> 6] ^= 1 << (bit & 63);
  return old;
}
// LBts/LBtr/LBtc/LXchgI64 — A-ext atomics (byte bitfields + amoswap.d). See Man("LXchgI64").
asm {
	LBts::
	srai	t0,a1,3
	add	t0,a0,t0
	andi	t1,t0,3
	sub	t2,t0,t1
	slli	t1,t1,3
	andi	t3,a1,7
	add	t1,t1,t3
	li	t3,1
	sll	t3,t3,t1
	math_lbts_r:
	lr.w	t4,(t2)
	and	t5,t4,t3
	sltu	t5,zero,t5
	or	t6,t4,t3
	sc.w	t0,t6,(t2)
	bnez	t0,math_lbts_r
	mv	a0,t5
	ret
}

asm {
	LBtr::
	srai	t0,a1,3
	add	t0,a0,t0
	andi	t1,t0,3
	sub	t2,t0,t1
	slli	t1,t1,3
	andi	t3,a1,7
	add	t1,t1,t3
	li	t3,1
	sll	t3,t3,t1
	math_lbtr_r:
	lr.w	t4,(t2)
	and	t5,t4,t3
	sltu	t5,zero,t5
	not	t6,t3
	and	t6,t4,t6
	sc.w	t0,t6,(t2)
	bnez	t0,math_lbtr_r
	mv	a0,t5
	ret
}

asm {
	LBtc::
	srai	t0,a1,3
	add	t0,a0,t0
	andi	t1,t0,3
	sub	t2,t0,t1
	slli	t1,t1,3
	andi	t3,a1,7
	add	t1,t1,t3
	li	t3,1
	sll	t3,t3,t1
	math_lbtc_r:
	lr.w	t4,(t2)
	and	t5,t4,t3
	sltu	t5,zero,t5
	xor	t6,t4,t3
	sc.w	t0,t6,(t2)
	bnez	t0,math_lbtc_r
	mv	a0,t5
	ret
}

asm {
	LXchgI64::
	amoswap.d	a0,a1,(a0)
	ret
}

I64 Bsf(I64 x)
{
  I64 i;
  if (!x)
    return -1;
  for (i = 0; i < 64; i++)
    if ((x >> i) & 1)
      return i;
  return -1;
}

I64 Bsr(I64 x)
{
  I64 i;
  if (!x)
    return -1;
  for (i = 63; i >= 0; i--)
    if ((x >> i) & 1)
      return i;
  return -1;
}

I64 SwapI64(I64 *a, I64 *b)
{
  I64 t = *a;
  *a = *b;
  *b = t;
  return 0;
}

I64 ModU64(U64 a, U64 b)
{
  if (!b)
    return 0;
  return a % b;
}
I64 g_rand1 = 0x9E3779B97F4A7C15;
I64 g_rand2 = 0x123456789ABCDEF;
I64 RandU16()
{
  g_rand1 ^= g_rand1 << 13;
  g_rand1 ^= g_rand1 >> 7;
  g_rand1 ^= g_rand1 << 17;
  return (g_rand1 >> 48) & 0xFFFF;
}

I64 RandI64()
{
  g_rand2 ^= g_rand2 << 13;
  g_rand2 ^= g_rand2 >> 7;
  g_rand2 ^= g_rand2 << 17;
  return g_rand2;
}

U0 Seed(I64 n)
{
  if (!n)
    n = 1;
  g_rand1 = n;
  g_rand2 = n ^ 0x9E3779B97F4A7C15;
}

F64 tS()
{
  return HcRdTime() / 10000000.0;
}
