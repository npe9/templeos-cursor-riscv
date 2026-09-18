/* Bare-metal HolyC runtime, shared by the REPL image and the exec harness.
 * Before including, define:
 *   HOLY_RT_PUTC(c)      write one byte to the console
 *   HOLY_RT_MALLOC(sz)   allocate sz bytes (never freed by the runtime itself)
 * Everything else is self-contained (no libc). */
#ifndef HOLY_RT_H
#define HOLY_RT_H
#include <stdarg.h>
#include <stddef.h>
#include "holy_rt_names.h"
typedef long long HRT_I64;
typedef unsigned long long HRT_U64;
typedef unsigned int HRT_U32;
typedef unsigned short HRT_U16;
typedef unsigned char HRT_U8;

static HRT_I64 rt_strlen(const char *s) { HRT_I64 n = 0; while (s[n]) n++; return n; }
static char *rt_strcpy(char *d, const char *s) { char *o = d; while ((*d++ = *s++)) {} return o; }
static void rt_puts(const char *s) { while (*s) HOLY_RT_PUTC(*s++); }

static void rt_putnum(HRT_U64 v, int base, int upper, int neg, int width, char pad, int commas) {
  char b[40]; int n = 0, digits = 0;
  if (v == 0) b[n++] = '0';
  while (v) {
    if (commas && digits && digits % 3 == 0) b[n++] = ',';
    HRT_U64 d = v % (HRT_U64)base;
    b[n++] = (char)(d < 10 ? '0' + d : (upper ? 'A' : 'a') + d - 10);
    v /= (HRT_U64)base; digits++;
  }
  if (neg) b[n++] = '-';
  while (n < width) b[n++] = pad;
  while (n) HOLY_RT_PUTC(b[--n]);
}
static void rt_putf64(double fv, int prec, int width) {
  char b[64]; int n = 0;
  int neg = fv < 0; if (neg) fv = -fv;
  HRT_U64 ip = (HRT_U64)fv; double frac = fv - (double)ip;
  HRT_U64 scale = 1; for (int i = 0; i < prec; i++) scale *= 10;
  HRT_U64 fr = (HRT_U64)(frac * (double)scale + 0.5);
  if (fr >= scale) { fr = 0; ip++; }
  /* build reversed */
  for (int i = 0; i < prec; i++) { b[n++] = (char)('0' + fr % 10); fr /= 10; }
  if (prec) b[n++] = '.';
  if (ip == 0) b[n++] = '0';
  while (ip) { b[n++] = (char)('0' + ip % 10); ip /= 10; }
  if (neg) b[n++] = '-';
  while (n < width) b[n++] = ' ';
  while (n) HOLY_RT_PUTC(b[--n]);
}

/* PrintJoin: same conversions as Print, but argc/argv (HolyC varargs ABI). Registered as
 * StrPrintJoin so seed print.hc can implement Print without a dual __boot_* hash name. */
static HRT_I64 HolyPrintJoin(char *fmt, HRT_I64 argc, HRT_I64 *argv) {
  HRT_I64 ai = 0;
  if (!fmt) return 0;
  for (const char *p = fmt; *p; p++) {
    if (*p != '%') { HOLY_RT_PUTC(*p); continue; }
    p++;
    char pad = ' '; int width = 0, prec = -1, commas = 0, rep = 1;
    for (;;) {
      if (*p == '-') p++;
      else if (*p == '0') { pad = '0'; p++; }
      else if (*p == ',') { commas = 1; p++; }
      else break;
    }
    while (*p >= '0' && *p <= '9') width = width * 10 + (*p++ - '0');
    if (*p == ',') { commas = 1; p++; }
    if (*p == '.') { p++; prec = 0; while (*p >= '0' && *p <= '9') prec = prec * 10 + (*p++ - '0'); }
    while (*p == 'h') {
      p++;
      if (*p == '?') p++;
      else if (*p == '*') { rep = (int)(ai < argc ? argv[ai++] : 0); p++; }
      else if (*p == '-') { p++; while (*p >= '0' && *p <= '9') p++; }
      else { int v = 0; while (*p >= '0' && *p <= '9') v = v * 10 + (*p++ - '0'); rep = v ? v : 1; }
    }
    #define PJ_ARG() (ai < argc ? argv[ai++] : 0)
    switch (*p) {
    case 'd': { HRT_I64 v = PJ_ARG(); rt_putnum(v < 0 ? (HRT_U64)(-v) : (HRT_U64)v, 10, 0, v < 0, width, pad, commas); break; }
    case 'u': rt_putnum((HRT_U64)PJ_ARG(), 10, 0, 0, width, pad, commas); break;
    case 'x': rt_putnum((HRT_U64)PJ_ARG(), 16, 0, 0, width, pad, 0); break;
    case 'X': rt_putnum((HRT_U64)PJ_ARG(), 16, 1, 0, width, pad, 0); break;
    case 'p': case 'P': rt_puts("0x"); rt_putnum((HRT_U64)PJ_ARG(), 16, 0, 0, 16, '0', 0); break;
    case 's': { char *sv = (char *)PJ_ARG(); HRT_I64 l = sv ? rt_strlen(sv) : 6; for (HRT_I64 i = l; i < width; i++) HOLY_RT_PUTC(' '); rt_puts(sv ? sv : "(null)"); break; }
    case 'c': { HRT_I64 cv = PJ_ARG();
                for (int r = 0; r < rep; r++) { HRT_I64 c = cv; while (c) { HOLY_RT_PUTC((char)(c & 0xFF)); c >>= 8; } }
                break; }
    case 'f': case 'n': { HRT_I64 bits = PJ_ARG(); double fv; HRT_U8 *bp = (HRT_U8 *)&bits, *fp = (HRT_U8 *)&fv;
                          for (int i = 0; i < 8; i++) fp[i] = bp[i];
                          rt_putf64(fv, prec < 0 ? 3 : prec, width); break; }
    case '%': HOLY_RT_PUTC('%'); break;
    case 0: return 0;
    default: HOLY_RT_PUTC('%'); HOLY_RT_PUTC(*p); break;
    }
    #undef PJ_ARG
  }
  return 0;
}
/* Print: %[flags][width][.prec][h<n>|h*|h?]<conv>. C-varargs path for AOT import table. */
static HRT_I64 HolyPrint(char *fmt, ...) {
  va_list ap; va_start(ap, fmt);
  for (const char *p = fmt; *p; p++) {
    if (*p != '%') { HOLY_RT_PUTC(*p); continue; }
    p++;
    char pad = ' '; int width = 0, prec = -1, commas = 0, rep = 1;
    for (;;) {
      if (*p == '-') p++;
      else if (*p == '0') { pad = '0'; p++; }
      else if (*p == ',') { commas = 1; p++; }
      else break;
    }
    while (*p >= '0' && *p <= '9') width = width * 10 + (*p++ - '0');
    if (*p == ',') { commas = 1; p++; }   /* HolyC also accepts the ',' flag after the width */
    if (*p == '.') { p++; prec = 0; while (*p >= '0' && *p <= '9') prec = prec * 10 + (*p++ - '0'); }
    while (*p == 'h') {           /* aux format: h? (auto), h<n> (repeat / sig. digits), h* (from args) */
      p++;
      if (*p == '?') p++;
      else if (*p == '*') { rep = (int)va_arg(ap, HRT_I64); p++; }
      else if (*p == '-') { p++; while (*p >= '0' && *p <= '9') p++; }
      else { int v = 0; while (*p >= '0' && *p <= '9') v = v * 10 + (*p++ - '0'); rep = v ? v : 1; }
    }
    switch (*p) {
    case 'd': { HRT_I64 v = va_arg(ap, HRT_I64); rt_putnum(v < 0 ? (HRT_U64)(-v) : (HRT_U64)v, 10, 0, v < 0, width, pad, commas); break; }
    case 'u': rt_putnum(va_arg(ap, HRT_U64), 10, 0, 0, width, pad, commas); break;
    case 'x': rt_putnum(va_arg(ap, HRT_U64), 16, 0, 0, width, pad, 0); break;
    case 'X': rt_putnum(va_arg(ap, HRT_U64), 16, 1, 0, width, pad, 0); break;
    case 'p': case 'P': rt_puts("0x"); rt_putnum(va_arg(ap, HRT_U64), 16, 0, 0, 16, '0', 0); break;
    case 's': { char *sv = va_arg(ap, char *); HRT_I64 l = sv ? rt_strlen(sv) : 6; for (HRT_I64 i = l; i < width; i++) HOLY_RT_PUTC(' '); rt_puts(sv ? sv : "(null)"); break; }
    case 'c': { HRT_I64 cv = va_arg(ap, HRT_I64);
                for (int r = 0; r < rep; r++) { HRT_I64 c = cv; while (c) { HOLY_RT_PUTC((char)(c & 0xFF)); c >>= 8; } }
                break; }
    case 'f': case 'n': { HRT_I64 bits = va_arg(ap, HRT_I64); double fv; HRT_U8 *bp = (HRT_U8 *)&bits, *fp = (HRT_U8 *)&fv;
                          for (int i = 0; i < 8; i++) fp[i] = bp[i];
                          rt_putf64(fv, prec < 0 ? 3 : prec, width); break; }
    case '%': HOLY_RT_PUTC('%'); break;
    case 0: va_end(ap); return 0;
    default: HOLY_RT_PUTC('%'); HOLY_RT_PUTC(*p); break;
    }
  }
  va_end(ap);
  return 0;
}
static HRT_I64 HolyPutS(char *s) { rt_puts(s); return 0; }
static HRT_I64 HolyPutChars(HRT_I64 ch) { while (ch) { HOLY_RT_PUTC((char)(ch & 0xFF)); ch >>= 8; } return 0; }
/* MAlloc/Free: 16-byte header {size, next}; freed blocks go on a first-fit free list, fresh
 * blocks come from the host allocator (never returned to it). */
typedef struct HolyBlk { HRT_I64 size; struct HolyBlk *next; } HolyBlk;
static HolyBlk *rt_free_list;
static HRT_I64 HolyMAlloc(HRT_I64 sz) {
  if (sz <= 0) sz = 1;
  sz = (sz + 15) & ~(HRT_I64)15;
  for (HolyBlk **pp = &rt_free_list; *pp; pp = &(*pp)->next) {
    if ((*pp)->size >= sz) { HolyBlk *b = *pp; *pp = b->next; b->next = 0; return (HRT_I64)(b + 1); }
  }
  HolyBlk *b = (HolyBlk *)HOLY_RT_MALLOC(sizeof(HolyBlk) + (size_t)sz);
  if (!b) return 0;
  b->size = sz; b->next = 0;
  return (HRT_I64)(b + 1);
}
static HRT_I64 HolyCAlloc(HRT_I64 sz) { HRT_U8 *p = (HRT_U8 *)HolyMAlloc(sz); if (p) for (HRT_I64 i = 0; i < sz; i++) p[i] = 0; return (HRT_I64)p; }
static HRT_I64 HolyFree(HRT_I64 p) { if (!p) return 0; HolyBlk *b = (HolyBlk *)p - 1; b->next = rt_free_list; rt_free_list = b; return 0; }
static HRT_I64 HolyStrLen(char *s) { return rt_strlen(s); }
static HRT_I64 HolyStrCpy(char *d, char *s) { rt_strcpy(d, s); return (HRT_I64)d; }
static HRT_I64 HolyStrCmp(char *a, char *b) { while (*a && *a == *b) { a++; b++; } return (HRT_I64)(HRT_U8)*a - (HRT_I64)(HRT_U8)*b; }
static HRT_I64 HolyStrCat(char *d, char *s) { rt_strcpy(d + rt_strlen(d), s); return (HRT_I64)d; }
static HRT_I64 HolyStrNew(char *s) { char *d = (char *)HolyMAlloc(rt_strlen(s) + 1); rt_strcpy(d, s); return (HRT_I64)d; }
static HRT_I64 HolyMemCpy(HRT_U8 *d, HRT_U8 *s, HRT_I64 n) { for (HRT_I64 i = 0; i < n; i++) d[i] = s[i]; return (HRT_I64)d; }
static HRT_I64 HolyMemSet(HRT_U8 *d, HRT_I64 c, HRT_I64 n) { for (HRT_I64 i = 0; i < n; i++) d[i] = (HRT_U8)c; return (HRT_I64)d; }
static HRT_I64 HolyMemCmp(HRT_U8 *a, HRT_U8 *b, HRT_I64 n) { for (HRT_I64 i = 0; i < n; i++) if (a[i] != b[i]) return (HRT_I64)a[i] - (HRT_I64)b[i]; return 0; }
static HRT_I64 HolyMemSetI64(HRT_I64 *d, HRT_I64 v, HRT_I64 n) { for (HRT_I64 i = 0; i < n; i++) d[i] = v; return (HRT_I64)d; }
static HRT_I64 HolyAbsI64(HRT_I64 v) { return v < 0 ? -v : v; }
static HRT_I64 HolyMaxI64(HRT_I64 a, HRT_I64 b) { return a > b ? a : b; }
static HRT_I64 HolyMinI64(HRT_I64 a, HRT_I64 b) { return a < b ? a : b; }
static HRT_I64 HolyToUpper(HRT_I64 c) { return (c >= 'a' && c <= 'z') ? c - 32 : c; }
static HRT_I64 HolyToLower(HRT_I64 c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }
static HRT_U64 rt_rand_state = 0x9E3779B97F4A7C15ULL;
static HRT_I64 HolyRandI64(void) { HRT_U64 x = rt_rand_state; x ^= x << 13; x ^= x >> 7; x ^= x << 17; rt_rand_state = x; return (HRT_I64)x; }
static HRT_I64 HolyRandU16(void) { return (HRT_I64)((HRT_U64)HolyRandI64() >> 48); }
static HRT_I64 HolyYorN(void) { return 0; }   /* no keyboard: answer "no" */
/* tS: seconds since boot as F64 (returned as raw bits; the compiler types it F64) */
static HRT_I64 HolytS(void) {
  HRT_U64 t;
  __asm__ volatile("rdtime %0" : "=r"(t));
  double s = (double)t / 10000000.0;   /* QEMU virt timebase 10 MHz */
  HRT_I64 bits; HRT_U8 *sp = (HRT_U8 *)&s, *bp = (HRT_U8 *)&bits;
  for (int i = 0; i < 8; i++) bp[i] = sp[i];
  return bits;
}
/* F64 math (no libm on bare metal): values cross the call boundary as raw bit patterns. */
static double rt_b2f(HRT_I64 b) { double f; HRT_U8 *s = (HRT_U8 *)&b, *d = (HRT_U8 *)&f; for (int i = 0; i < 8; i++) d[i] = s[i]; return f; }
static HRT_I64 rt_f2b(double f) { HRT_I64 b; HRT_U8 *s = (HRT_U8 *)&f, *d = (HRT_U8 *)&b; for (int i = 0; i < 8; i++) d[i] = s[i]; return b; }
static double rt_sqrt(double x) { double r; __asm__("fsqrt.d %0, %1" : "=f"(r) : "f"(x)); return r; }
#define RT_LN2 0.6931471805599453
#define RT_PI 3.141592653589793
static double rt_ln(double x) {
  if (x <= 0) return x == 0 ? -(1.0 / 0.0) : (0.0 / 0.0);
  int e = 0;
  while (x >= 2.0) { x *= 0.5; e++; }
  while (x < 1.0) { x *= 2.0; e--; }
  double t = (x - 1) / (x + 1), t2 = t * t, s = 0, p = t;   /* x in [1,2): atanh series */
  for (int k = 1; k < 60; k += 2) { s += p / k; p *= t2; }
  return 2 * s + e * RT_LN2;
}
static double rt_exp(double x) {
  if (x > 709) return 1.0 / 0.0;
  if (x < -745) return 0;
  int k = (int)(x / RT_LN2 + (x >= 0 ? 0.5 : -0.5));
  double r = x - k * RT_LN2, s = 1, term = 1;
  for (int i = 1; i < 30; i++) { term *= r / i; s += term; }
  while (k > 0) { s *= 2; k--; }
  while (k < 0) { s *= 0.5; k++; }
  return s;
}
static double rt_pow(double a, double b) {
  if (b == 0) return 1;
  if (a == 0) return b > 0 ? 0 : 1.0 / 0.0;
  if (b == (double)(HRT_I64)b && b > -1024 && b < 1024) {
    HRT_I64 n = (HRT_I64)b; int neg = n < 0; if (neg) n = -n;
    double r = 1, base = a;
    while (n) { if (n & 1) r *= base; base *= base; n >>= 1; }
    return neg ? 1 / r : r;
  }
  if (a < 0) return 0.0 / 0.0;
  return rt_exp(b * rt_ln(a));
}
static double rt_sin(double x) {
  x = x - 2 * RT_PI * (double)(HRT_I64)(x / (2 * RT_PI));
  if (x > RT_PI) x -= 2 * RT_PI;
  if (x < -RT_PI) x += 2 * RT_PI;
  double t = x, s = x, x2 = x * x;
  for (int i = 1; i < 12; i++) { t *= -x2 / ((2 * i) * (2 * i + 1)); s += t; }
  return s;
}
static double rt_cos(double x) { return rt_sin(x + RT_PI / 2); }
static double rt_atan(double x) {
  if (x > 1) return RT_PI / 2 - rt_atan(1 / x);
  if (x < -1) return -RT_PI / 2 - rt_atan(1 / x);
  double y = x / (1 + rt_sqrt(1 + x * x)), y2 = y * y, t = y, s = y;   /* atan x = 2 atan y */
  for (int i = 1; i < 40; i++) { t *= -y2; s += t / (2 * i + 1); }
  return 2 * s;
}
static double rt_floor(double x) { double f = (double)(HRT_I64)x; if (f > x) f -= 1; return f; }
static double rt_ceil(double x) { double f = (double)(HRT_I64)x; if (f < x) f += 1; return f; }
static HRT_I64 HolyPow(HRT_I64 a, HRT_I64 b) { return rt_f2b(rt_pow(rt_b2f(a), rt_b2f(b))); }
static HRT_I64 HolySqrt(HRT_I64 a) { return rt_f2b(rt_sqrt(rt_b2f(a))); }
static HRT_I64 HolyExp(HRT_I64 a) { return rt_f2b(rt_exp(rt_b2f(a))); }
static HRT_I64 HolyLn(HRT_I64 a) { return rt_f2b(rt_ln(rt_b2f(a))); }
static HRT_I64 HolyLog10(HRT_I64 a) { return rt_f2b(rt_ln(rt_b2f(a)) / 2.302585092994046); }
static HRT_I64 HolyLog2(HRT_I64 a) { return rt_f2b(rt_ln(rt_b2f(a)) / RT_LN2); }
static HRT_I64 HolyFloor(HRT_I64 a) { return rt_f2b(rt_floor(rt_b2f(a))); }
static HRT_I64 HolyCeil(HRT_I64 a) { return rt_f2b(rt_ceil(rt_b2f(a))); }
static HRT_I64 HolyRound(HRT_I64 a) { double x = rt_b2f(a); return rt_f2b(x >= 0 ? (double)(HRT_I64)(x + 0.5) : -(double)(HRT_I64)(-x + 0.5)); }
static HRT_I64 HolyTrunc(HRT_I64 a) { return rt_f2b((double)(HRT_I64)rt_b2f(a)); }
static HRT_I64 HolySin(HRT_I64 a) { return rt_f2b(rt_sin(rt_b2f(a))); }
static HRT_I64 HolyCos(HRT_I64 a) { return rt_f2b(rt_cos(rt_b2f(a))); }
static HRT_I64 HolyTan(HRT_I64 a) { double x = rt_b2f(a); return rt_f2b(rt_sin(x) / rt_cos(x)); }
static HRT_I64 HolyATan(HRT_I64 a) { return rt_f2b(rt_atan(rt_b2f(a))); }
static HRT_I64 HolyAbs(HRT_I64 a) { double x = rt_b2f(a); return rt_f2b(x < 0 ? -x : x); }
static HRT_I64 HolySign(HRT_I64 a) { double x = rt_b2f(a); return x > 0 ? 1 : x < 0 ? -1 : 0; }
/* x86 intrinsics the kernel declares `_intern`/`_extern` (KernelB.HH, KUtils.HC asm):
 * bit tests on bit arrays, queues (CQue {next,last}), port I/O (no port space here: no-ops),
 * register/flag accessors (0), time stamp (rdtime), string matching. */
static HRT_I64 HolyBt(HRT_U8 *bf, HRT_I64 n) { return (bf[n >> 3] >> (n & 7)) & 1; }
static HRT_I64 HolyBts(HRT_U8 *bf, HRT_I64 n) { HRT_I64 o = (bf[n >> 3] >> (n & 7)) & 1; bf[n >> 3] |= (HRT_U8)(1 << (n & 7)); return o; }
static HRT_I64 HolyBtr(HRT_U8 *bf, HRT_I64 n) { HRT_I64 o = (bf[n >> 3] >> (n & 7)) & 1; bf[n >> 3] &= (HRT_U8)~(1 << (n & 7)); return o; }
static HRT_I64 HolyBtc(HRT_U8 *bf, HRT_I64 n) { HRT_I64 o = (bf[n >> 3] >> (n & 7)) & 1; bf[n >> 3] ^= (HRT_U8)(1 << (n & 7)); return o; }
/* Locked bit ops: GCC emits A-ext LR/SC (or AMO) for sub-word atomics on rv64ima. */
static HRT_I64 HolyLBts(HRT_U8 *bf, HRT_I64 n) {
  HRT_U8 *p = bf + (n >> 3);
  HRT_U8 mask = (HRT_U8)(1u << (n & 7));
  return (__atomic_fetch_or(p, mask, __ATOMIC_SEQ_CST) & mask) != 0;
}
static HRT_I64 HolyLBtr(HRT_U8 *bf, HRT_I64 n) {
  HRT_U8 *p = bf + (n >> 3);
  HRT_U8 mask = (HRT_U8)(1u << (n & 7));
  return (__atomic_fetch_and(p, (HRT_U8)~mask, __ATOMIC_SEQ_CST) & mask) != 0;
}
static HRT_I64 HolyLBtc(HRT_U8 *bf, HRT_I64 n) {
  HRT_U8 *p = bf + (n >> 3);
  HRT_U8 mask = (HRT_U8)(1u << (n & 7));
  return (__atomic_fetch_xor(p, mask, __ATOMIC_SEQ_CST) & mask) != 0;
}
static HRT_I64 HolyBsf(HRT_I64 v) { if (!v) return -1; HRT_I64 i = 0; while (!((HRT_U64)v >> i & 1)) i++; return i; }
static HRT_I64 HolyBsr(HRT_I64 v) { if (!v) return -1; HRT_I64 i = 63; while (!((HRT_U64)v >> i & 1)) i--; return i; }
static HRT_I64 HolyBEqu(HRT_U8 *bf, HRT_I64 n, HRT_I64 val) { if (val) HolyBts(bf, n); else HolyBtr(bf, n); return val; }
static HRT_I64 HolyBFieldOrU32(HRT_U8 *bf, HRT_I64 lo, HRT_I64 hi) { for (HRT_I64 i = lo; i <= hi; i++) HolyBts(bf, i); return 0; }
static HRT_I64 HolySwapI64(HRT_I64 *a, HRT_I64 *b) { HRT_I64 t = *a; *a = *b; *b = t; return 0; }
static HRT_I64 HolyLXchgI64(HRT_I64 *d, HRT_I64 v) {
  return __atomic_exchange_n(d, v, __ATOMIC_SEQ_CST);
}
/* HolyC `lock` stmt spinlock (amoswap). Fixed RAM slot near SYS_FIXED_AREA. */
#ifndef HOLYC_STMT_LOCK_ADDR
#define HOLYC_STMT_LOCK_ADDR 0x87001F00UL
#endif
static HRT_I64 HolyLock(void) {
  volatile HRT_I64 *lk = (volatile HRT_I64 *)HOLYC_STMT_LOCK_ADDR;
  while (__atomic_exchange_n(lk, (HRT_I64)1, __ATOMIC_ACQUIRE))
    __asm__ volatile("nop");
  return 0;
}
static HRT_I64 HolyUnlock(void) {
  volatile HRT_I64 *lk = (volatile HRT_I64 *)HOLYC_STMT_LOCK_ADDR;
  __atomic_store_n(lk, (HRT_I64)0, __ATOMIC_RELEASE);
  return 0;
}
static HRT_I64 HolySqrI64(HRT_I64 x) { return x * x; }
static HRT_I64 HolyClampI64(HRT_I64 x, HRT_I64 lo, HRT_I64 hi) { return x < lo ? lo : x > hi ? hi : x; }
static HRT_I64 HolyMSize(HRT_U8 *p) { return p ? ((HolyBlk *)p - 1)->size : 0; }
static HRT_I64 HolyMSize2(HRT_U8 *p) { return HolyMSize(p); }
static HRT_I64 HolyInU8(HRT_I64 port) { (void)port; return 0; }
static HRT_I64 HolyOutU8(HRT_I64 port, HRT_I64 v) { (void)port; (void)v; return 0; }
static HRT_I64 HolyInU16(HRT_I64 port) { (void)port; return 0; }
static HRT_I64 HolyOutU16(HRT_I64 port, HRT_I64 v) { (void)port; (void)v; return 0; }
static HRT_I64 HolyInU32(HRT_I64 port) { (void)port; return 0; }
static HRT_I64 HolyOutU32(HRT_I64 port, HRT_I64 v) { (void)port; (void)v; return 0; }
static HRT_I64 HolyRepInU32(HRT_U8 *buf, HRT_I64 cnt, HRT_I64 port) { (void)port; for (HRT_I64 i = 0; i < cnt * 4; i++) buf[i] = 0; return 0; }
static HRT_I64 HolyRepOutU32(HRT_U8 *buf, HRT_I64 cnt, HRT_I64 port) { (void)buf; (void)cnt; (void)port; return 0; }
static HRT_I64 HolyGetRAX(void) { return 0; }
static HRT_I64 HolyGetRBP(void) { HRT_I64 v; __asm__ volatile("mv %0, s0" : "=r"(v)); return v; }
static HRT_I64 HolyGetRFlags(void) { return 0; }
static HRT_I64 HolySetRFlags(HRT_I64 f) { (void)f; return 0; }
static HRT_I64 HolyCPUId(HRT_I64 rax, HRT_U8 *res) { (void)rax; for (int i = 0; i < 32; i++) res[i] = 0; return 0; }
static HRT_I64 HolyInvlPg(HRT_U8 *a) { (void)a; return 0; }
static HRT_I64 HolySysHlt(void) { __asm__ volatile("wfi"); return 0; }
static HRT_I64 HolyGetTSC(void) { HRT_U64 t; __asm__ volatile("rdtime %0" : "=r"(t)); return (HRT_I64)t; }
static HRT_I64 HolyCaller(HRT_I64 n) { (void)n; return 0; }
typedef struct HolyQue { struct HolyQue *next, *last; } HolyQue;
static HRT_I64 HolyQueInit(HolyQue *h) { h->next = h->last = h; return 0; }
/* QueIns(entry, pred): insert entry AFTER pred (KernelB.HH). QueInsRev(entry, succ): before succ. */
static HRT_I64 HolyQueIns(HolyQue *e, HolyQue *pred) { e->next = pred->next; e->last = pred; pred->next->last = e; pred->next = e; return 0; }
static HRT_I64 HolyQueInsRev(HolyQue *e, HolyQue *succ) { e->last = succ->last; e->next = succ; succ->last->next = e; succ->last = e; return 0; }
static HRT_I64 HolyQueRem(HolyQue *e) { e->last->next = e->next; e->next->last = e->last; return 0; }
static int rt_lc(int c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }
static HRT_I64 HolyStrMatch(char *needle, char *hay, HRT_I64 flags) { (void)flags; if (!needle || !hay) return 0; for (char *h = hay; *h; h++) { char *a = needle, *b = h; while (*a && *a == *b) { a++; b++; } if (!*a) return (HRT_I64)h; } return 0; }
static HRT_I64 HolyStrIMatch(char *needle, char *hay, HRT_I64 flags) { (void)flags; if (!needle || !hay) return 0; for (char *h = hay; *h; h++) { char *a = needle, *b = h; while (*a && rt_lc(*a) == rt_lc(*b)) { a++; b++; } if (!*a) return (HRT_I64)h; } return 0; }
static HRT_I64 HolyStrICmp(char *a, char *b) { while (*a && rt_lc(*a) == rt_lc(*b)) { a++; b++; } return rt_lc(*a) - rt_lc(*b); }
static HRT_I64 HolyPow10(HRT_I64 x) { return rt_f2b(rt_exp(rt_b2f(x) * 2.302585092994046)); }
/* KHashA.HC asm: CHash {next, str, U32 type, U32 use_cnt}; CHashTable {next, mask, locked_flags, body}. */
typedef struct HolyHash { struct HolyHash *next; char *str; HRT_U32 type, use_cnt; } HolyHash;
typedef struct HolyHashTable { struct HolyHashTable *next; HRT_I64 mask, locked_flags; HolyHash **body; } HolyHashTable;
/* TempleOS SYS_HASH_STR (KHashA / KHashRV) — must match guest HashStr or HashAdd/Find diverge. */
static HRT_I64 HolyHashStr(char *st) {
  HRT_U64 h = 0, c, carry;
  if (!st) return 0;
  while ((c = (HRT_U8)*st++)) {
    carry = h >> 63;
    h = (h << 1) + c + carry;
  }
  carry = (h >> 15) & 1;
  return (HRT_I64)(h + (h >> 16) + carry);
}
static HRT_I64 HolyHashSingleTableFind(char *needle, HolyHashTable *t, HRT_I64 mask) {
  if (!needle || !t) return 0;
  for (HolyHash *e = t->body[(HRT_U64)HolyHashStr(needle) & (HRT_U64)t->mask]; e; e = e->next) {
    if ((e->type & mask) && e->str) { char *a = e->str, *b = needle; while (*a && *a == *b) { a++; b++; } if (!*a && !*b) return (HRT_I64)e; }
  }
  return 0;
}
static HRT_I64 HolyHashFind(char *needle, HolyHashTable *t, HRT_I64 mask) {
  for (; t; t = t->next) { HRT_I64 r = HolyHashSingleTableFind(needle, t, mask); if (r) return r; }
  return 0;
}
static HRT_I64 HolyHashAdd(HolyHash *e, HolyHashTable *t) {
  if (!e || !t) return 0;
  HRT_U64 i = (HRT_U64)HolyHashStr(e->str) & (HRT_U64)t->mask;
  e->next = t->body[i]; t->body[i] = e;
  return 0;
}
static HRT_I64 HolyHashRemDel(HolyHash *e, HolyHashTable *t, HRT_I64 mask) {
  (void)mask;
  if (!e || !t) return 0;
  HRT_U64 i = (HRT_U64)HolyHashStr(e->str) & (HRT_U64)t->mask;
  for (HolyHash **pp = &t->body[i]; *pp; pp = &(*pp)->next) if (*pp == e) { *pp = e->next; return 1; }
  return 0;
}
static HRT_I64 HolyStrNCmp(char *a, char *b, HRT_I64 n) { for (HRT_I64 i = 0; i < n; i++) { if (a[i] != b[i]) return (HRT_U8)a[i] - (HRT_U8)b[i]; if (!a[i]) return 0; } return 0; }
/* ModU64(&q, d): divide *q by d in place, return the remainder (KernelB.HH IC_MOD_U64). */
static HRT_I64 HolyModU64(HRT_U64 *q, HRT_I64 d) {
  if (!d) return 0;
  HRT_U64 v = *q; *q = v / (HRT_U64)d; return (HRT_I64)(v % (HRT_U64)d);
}
static HRT_I64 HolyLBEqu(HRT_U8 *bf, HRT_I64 n, HRT_I64 val) { return HolyBEqu(bf, n, val); }
static HRT_I64 HolyBFieldExtU32(HRT_U8 *bf, HRT_I64 lo, HRT_I64 hi) { HRT_I64 r = 0; for (HRT_I64 i = hi; i >= lo; i--) r = (r << 1) | HolyBt(bf, i); return r; }
static HRT_I64 HolyRepInU16(HRT_U8 *buf, HRT_I64 cnt, HRT_I64 port) { (void)port; for (HRT_I64 i = 0; i < cnt * 2; i++) buf[i] = 0; return 0; }
static HRT_I64 HolyGetRSP(void) { HRT_I64 v; __asm__ volatile("mv %0, sp" : "=r"(v)); return v; }
static HRT_I64 HolySaveExceptRegs(void) { return 0; }
/* RISC-V has no coherent instruction cache: after writing instructions you MUST
 * fence.i before executing them. The JIT path never did. On a freshly-MAlloc'd block
 * this usually survives, but a nested compile (PrsVarInit's eval-during-parse of an
 * initialiser) reuses memory that was just freed after being executed, so the stale
 * decode wins and you land on whatever was there before — the `illegal instruction,
 * insn@mepc=0` at a heap address. Mandatory on real silicon regardless. */
static HRT_I64 HolyCall(HRT_I64 addr) {
  if (!addr) return 0;
  /* Raw encoding: -march=rv64imafdc does not enable Zifencei, so the mnemonic will
   * not assemble. 0x0000100f IS fence.i and is accepted everywhere. */
  __asm__ volatile(".word 0x0000100f" ::: "memory");
  return ((HRT_I64 (*)(void))addr)();
}
static HRT_I64 HolyFarCall32(HRT_I64 a, HRT_I64 b, HRT_I64 c, HRT_I64 d) { (void)a; (void)b; (void)c; (void)d; return 0; }
/* --- RISC-V machine-mode traps + CLINT timer (QEMU virt) -----------------------------------------
 * A trap vector that saves the caller-saved registers, calls a C dispatcher, restores, and mrets.
 * The dispatcher counts machine-timer interrupts and re-arms mtimecmp; this is the interrupt-driven
 * foundation a preemptive scheduler needs. */
#ifndef HOLY_UART_BASE
#define HOLY_UART_BASE       0x10000000ULL
#endif
#ifndef HOLY_CLINT_BASE
#define HOLY_CLINT_BASE      0x02000000ULL
#endif
#ifndef HOLY_CLINT_MTIME_OFF
#define HOLY_CLINT_MTIME_OFF 0xBFF8ULL
#endif
#ifndef HOLY_CLINT_MTIMECMP_OFF
#define HOLY_CLINT_MTIMECMP_OFF 0x4000ULL
#endif
#define HOLY_MTIME           (HOLY_CLINT_BASE + HOLY_CLINT_MTIME_OFF)
#define HOLY_MTIMECMP        (HOLY_CLINT_BASE + HOLY_CLINT_MTIMECMP_OFF)
#ifndef HOLY_VIRTIO_MMIO_BASE
#define HOLY_VIRTIO_MMIO_BASE 0x10001000ULL
#endif
#ifndef HOLY_VIRTIO_MMIO_STRIDE
#define HOLY_VIRTIO_MMIO_STRIDE 0x1000ULL
#endif
/* Slot-0 window (UART on virt); virtio IRQ N maps to HOLY_UART_BASE + N*STRIDE. */
#define HOLY_VIRTIO_SLOT0_BASE (HOLY_VIRTIO_MMIO_BASE - HOLY_VIRTIO_MMIO_STRIDE)

static void HolyServiceExternal(void);
static HRT_I64 HolyRVTrapInit(void);
static volatile HRT_I64 holy_ticks = 0;
static HRT_I64 holy_timer_interval = 0;
/* UART crash monitor for FB/Win dual-console (RVCrashMonInit). Off by default so
 * existing RVTrapInit smokes keep silent skip-on-fault. */
static int holy_crash_mon_en = 0;
static HRT_I64 holy_crash_mcause, holy_crash_mepc, holy_crash_mtval;
/* Frozen at trap entry by HolyTrapVector. Non-static so the vector's `la` resolves.
 * ra is the single most useful one: a fault inside a leaf (MemCpy, StrLen, a stub)
 * traps before that function has saved ra, so ra still holds its caller — which is
 * the question "who passed the bad pointer?" that mepc alone cannot answer. */
HRT_I64 holy_crash_ra, holy_crash_fp, holy_crash_sp;

static void holy_crash_puthex(HRT_U64 v) {
  const char *hx = "0123456789abcdef";
  int i;
  for (i = 60; i >= 0; i -= 4)
    HOLY_RT_PUTC(hx[(v >> i) & 0xF]);
}

static void holy_crash_putdec(HRT_U64 v) {
  char buf[24];
  int n = 0;
  if (!v) {
    HOLY_RT_PUTC('0');
    return;
  }
  while (v && n < (int)sizeof(buf)) {
    buf[n++] = (char)('0' + (v % 10));
    v /= 10;
  }
  while (n > 0)
    HOLY_RT_PUTC(buf[--n]);
}

/* Mirror bootstrap/seed/csr.hc McauseCauseName for FB/Win UART crash dumps. */
static const char *holy_mcause_name(HRT_I64 v) {
  int intr = (int)((v >> 63) & 1);
  HRT_I64 code = v & (HRT_I64)0x7FFFFFFFFFFFFFFFLL;
  if (intr) {
    switch ((int)code) {
      case 0: return "user soft interrupt";
      case 1: return "supervisor soft interrupt";
      case 3: return "machine soft interrupt";
      case 4: return "user timer interrupt";
      case 5: return "supervisor timer interrupt";
      case 7: return "machine timer interrupt";
      case 8: return "user external interrupt";
      case 9: return "supervisor external interrupt";
      case 11: return "machine external interrupt";
      default: return "interrupt";
    }
  }
  switch ((int)code) {
    case 0: return "insn address misaligned";
    case 1: return "insn access fault";
    case 2: return "illegal instruction";
    case 3: return "breakpoint";
    case 4: return "load address misaligned";
    case 5: return "load access fault";
    case 6: return "store address misaligned";
    case 7: return "store access fault";
    case 8: return "ecall from U-mode";
    case 9: return "ecall from S-mode";
    case 11: return "ecall from M-mode";
    case 12: return "insn page fault";
    case 13: return "load page fault";
    case 15: return "store page fault";
    default: return "exception";
  }
}

static void holy_crash_put_mcause(HRT_I64 mcause) {
  int intr = (int)((mcause >> 63) & 1);
  HRT_I64 code = mcause & (HRT_I64)0x7FFFFFFFFFFFFFFFLL;
  rt_puts("mcause=");
  holy_crash_puthex((HRT_U64)mcause);
  if (intr)
    rt_puts(" Interrupt code=");
  else
    rt_puts(" Exception code=");
  holy_crash_putdec((HRT_U64)code);
  rt_puts(" (");
  rt_puts(holy_mcause_name(mcause));
  rt_puts(")");
}

static int holy_crash_in_ram(HRT_I64 a) {
  return a >= (HRT_I64)0x80000000LL && a < (HRT_I64)0x88000000LL;
}

static HRT_I64 holy_crash_getc(void) {
  volatile HRT_U8 *rbr = (volatile HRT_U8 *)HOLY_UART_BASE;
  volatile HRT_U8 *lsr = (volatile HRT_U8 *)(HOLY_UART_BASE + 5);
  while (!(*lsr & 1))
    ;
  return (HRT_I64)(*rbr & 0xFF);
}

static void holy_crash_gets(char *buf, int max) {
  int n = 0;
  HRT_I64 ch;
  while (n < max - 1) {
    ch = holy_crash_getc();
    if (ch == '\r' || ch == '\n') {
      HOLY_RT_PUTC('\n');
      break;
    }
    if (ch == 8 || ch == 127) {
      if (n > 0) {
        n--;
        rt_puts("\b \b");
      }
      continue;
    }
    if (ch == 3) {
      buf[0] = 0;
      rt_puts("^C\n");
      return;
    }
    if (ch >= 32 && ch < 127) {
      buf[n++] = (char)ch;
      HOLY_RT_PUTC((char)ch);
    }
  }
  buf[n] = 0;
}

static int holy_crash_cmd_eq(const char *line, const char *cmd) {
  int i = 0;
  if (!line || !cmd) return 0;
  while (cmd[i] && line[i] == cmd[i]) i++;
  if (cmd[i]) return 0;
  return !line[i] || line[i] == ' ' || line[i] == '\t';
}

static const char *holy_crash_skip(const char *p) {
  if (!p) return p;
  while (*p == ' ' || *p == '\t') p++;
  return p;
}

static const char *holy_crash_skip_tok(const char *p) {
  p = holy_crash_skip(p);
  while (*p && *p != ' ' && *p != '\t') p++;
  return holy_crash_skip(p);
}

static HRT_I64 holy_crash_parse_i64(const char *p) {
  HRT_I64 v = 0, neg = 0, base = 10;
  p = holy_crash_skip(p);
  if (*p == '-') { neg = 1; p++; }
  if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) { base = 16; p += 2; }
  while (*p) {
    int d;
    if (*p >= '0' && *p <= '9') d = *p - '0';
    else if (base == 16 && *p >= 'a' && *p <= 'f') d = *p - 'a' + 10;
    else if (base == 16 && *p >= 'A' && *p <= 'F') d = *p - 'A' + 10;
    else break;
    v = v * base + d;
    p++;
  }
  return neg ? -v : v;
}

static void holy_crash_md(HRT_I64 addr, HRT_I64 n) {
  HRT_I64 i;
  if (!holy_crash_in_ram(addr) || n <= 0) {
    rt_puts("md: bad addr/len\n");
    return;
  }
  if (n > 0x1000) n = 0x1000;
  for (i = 0; i < n; i++) {
    if ((i & 15) == 0) {
      holy_crash_puthex((HRT_U64)(addr + i));
      HOLY_RT_PUTC(':');
    }
    HOLY_RT_PUTC(' ');
    {
      HRT_U8 b = *(volatile HRT_U8 *)(addr + i);
      const char *hx = "0123456789abcdef";
      HOLY_RT_PUTC(hx[(b >> 4) & 0xF]);
      HOLY_RT_PUTC(hx[b & 0xF]);
    }
    if ((i & 15) == 15) HOLY_RT_PUTC('\n');
  }
  if (n & 15) HOLY_RT_PUTC('\n');
}

static int holy_crash_in_code(HRT_I64 a) {
  /* Code is the harness text plus the AOT blob — NOT the whole low 112 MB.
   * The old test (< 0x87000000) swallowed the guest heap (0x82000400..0x86000000),
   * so every heap pointer on the stack was reported as a candidate frame and the two
   * or three real ones were buried in noise. Bound it by the blob instead. */
  extern unsigned char _binary_blob_bin_start[], _binary_blob_bin_end[];
  HRT_I64 blob0 = (HRT_I64)_binary_blob_bin_start;
  HRT_I64 blob1 = (HRT_I64)_binary_blob_bin_end;
  if (a & 1) return 0;
  if (a >= (HRT_I64)0x80000000LL && a < blob0 && a < (HRT_I64)0x80100000LL)
    return 1;                       /* crt0 / oracle_out text */
  return a >= blob0 && a < blob1;   /* the AOT blob */
}

static void holy_crash_bt(void) {
  /* #0 is mepc. #1 is the ra frozen at trap entry — exact when the faulting function
   * is a leaf (it had not saved ra yet), stale if it had. Deeper frames come from a
   * CONSERVATIVE stack scan, not a frame walk: this codegen emits
   *   addi sp,sp,-N / sd ra,0(sp) / sd s0,8(sp) / addi s0,sp,N
   * with N varying per function (16/24/32/56/120 observed), so ra sits at s0-N and
   * there is no fixed offset to chase. The scan therefore prints every stack word
   * that looks like a code address; some are stale. Labelled so, rather than dressed
   * up as a real backtrace. */
  HRT_U32 insn = 0;
  HRT_I64 *p, *end, v; int hits = 0;
  rt_puts("bt (mepc + trap-frozen ra, then conservative stack scan)\n");
  if (holy_crash_in_code(holy_crash_mepc)) {
    rt_puts("  #0 ");
    holy_crash_puthex((HRT_U64)holy_crash_mepc);
    HOLY_RT_PUTC('\n');
    insn = *(volatile HRT_U32 *)holy_crash_mepc;
    rt_puts("  insn=");
    holy_crash_puthex((HRT_U64)insn);
    if (!insn)
      rt_puts(" (word 0 — null/unmapped code)");
    else if ((insn >> 16) == 0)
      rt_puts(" (halfword/trunc ptr? — jump-into-data)");
    HOLY_RT_PUTC('\n');
  } else {
    rt_puts("  (mepc not in code range");
    if (holy_crash_mepc & 1)
      rt_puts(" — odd PC");
    rt_puts(")\n");
    rt_puts("  mepc=");
    holy_crash_puthex((HRT_U64)holy_crash_mepc);
    HOLY_RT_PUTC('\n');
  }
  if (holy_crash_ra) {
    rt_puts("  #1 ");
    holy_crash_puthex((HRT_U64)holy_crash_ra);
    if (holy_crash_in_code(holy_crash_ra))
      rt_puts("  <- ra at trap (caller, if the faulting fn is a leaf)");
    else
      rt_puts("  (ra not in code range — already clobbered)");
    HOLY_RT_PUTC('\n');
  }
  /* Conservative scan: stack words that look like code. Stale entries are expected. */
  p = (HRT_I64 *)holy_crash_sp;
  if (p && holy_crash_fp > holy_crash_sp) {
    end = (HRT_I64 *)holy_crash_fp;
    if (end - p > 512) end = p + 512;
    rt_puts("  -- stack scan (may include stale frames) --\n");
    while (p < end && hits < 12) {
      v = *p++;
      if (holy_crash_in_code(v)) {
        rt_puts("     ");
        holy_crash_puthex((HRT_U64)v);
        HOLY_RT_PUTC('\n');
        hits++;
      }
    }
    if (!hits)
      rt_puts("     (none)\n");
  }
  rt_puts("  map: HOLYC_MAP=f holyc-riscv <case> -o b.bin; addr-0x80800000 -> fn\n");
}

static void HolyCrashMonEnter(HRT_I64 mcause, HRT_I64 mepc, HRT_I64 mtval) {
  char line[128];
  holy_crash_mcause = mcause;
  holy_crash_mepc = mepc;
  holy_crash_mtval = mtval;
  rt_puts("\n*** UART crash dump (FB/Win serial)\n");
  holy_crash_put_mcause(mcause);
  HOLY_RT_PUTC('\n');
  rt_puts("mepc=");
  holy_crash_puthex((HRT_U64)mepc);
  rt_puts(" mtval=");
  holy_crash_puthex((HRT_U64)mtval);
  HOLY_RT_PUTC('\n');
  if (holy_crash_in_code(mepc)) {
    HRT_U32 insn = *(volatile HRT_U32 *)mepc;
    rt_puts("insn@mepc=");
    holy_crash_puthex((HRT_U64)insn);
    if (!insn)
      rt_puts(" (0 — often jump-to-null / freed JIT)");
    else if ((insn >> 16) == 0)
      rt_puts(" (halfword/trunc ptr? — jump-into-data)");
    HOLY_RT_PUTC('\n');
  } else if (mepc & 1) {
    rt_puts("mepc odd — misaligned PC / corrupt return\n");
  }
  rt_puts("crash> cmds: md mw regs bt dump go reboot help\n");
  for (;;) {
    rt_puts("crash> ");
    holy_crash_gets(line, (int)sizeof line);
    if (!line[0]) continue;
    if (holy_crash_cmd_eq(line, "go") || holy_crash_cmd_eq(line, "c")) {
      rt_puts("crash: leave monitor\n");
      return;
    }
    if (holy_crash_cmd_eq(line, "reboot") || holy_crash_cmd_eq(line, "reset")) {
      rt_puts("crash: reboot (halt)\n");
      for (;;) __asm__ volatile("wfi");
    }
    if (holy_crash_cmd_eq(line, "help") || holy_crash_cmd_eq(line, "?")) {
      rt_puts("md ADDR [N]  mw ADDR VAL  regs  bt  dump  go  reboot\n");
      continue;
    }
    if (holy_crash_cmd_eq(line, "regs") || holy_crash_cmd_eq(line, "dump")) {
      holy_crash_put_mcause(holy_crash_mcause);
      HOLY_RT_PUTC('\n');
      rt_puts("mepc=");
      holy_crash_puthex((HRT_U64)holy_crash_mepc);
      rt_puts(" mtval=");
      holy_crash_puthex((HRT_U64)holy_crash_mtval);
      HOLY_RT_PUTC('\n');
      continue;
    }
    if (holy_crash_cmd_eq(line, "bt")) {
      holy_crash_bt();
      continue;
    }
    if (holy_crash_cmd_eq(line, "md")) {
      const char *p = holy_crash_skip_tok(line);
      HRT_I64 addr = holy_crash_parse_i64(p);
      p = holy_crash_skip_tok(p);
      HRT_I64 n = *p ? holy_crash_parse_i64(p) : 64;
      holy_crash_md(addr, n);
      continue;
    }
    if (holy_crash_cmd_eq(line, "mw")) {
      const char *p = holy_crash_skip_tok(line);
      HRT_I64 addr = holy_crash_parse_i64(p);
      p = holy_crash_skip_tok(p);
      HRT_I64 val = holy_crash_parse_i64(p);
      if (!holy_crash_in_ram(addr)) {
        rt_puts("mw: bad addr\n");
        continue;
      }
      *(volatile HRT_I64 *)addr = val;
      rt_puts("mw ok\n");
      continue;
    }
    rt_puts("?\n");
  }
}

/* Fault -> back to the REPL prompt instead of the blocking crash> monitor.
 * setjmp/longjmp in two naked stubs: RVTrapRecoverArm() stores ra/sp/fp and returns 0;
 * after a synchronous exception the trap dispatcher points mepc at the trampoline, which
 * reloads ra/sp/fp and returns 1 to that same call site. The REPL re-arms per line, so a
 * fault costs one line, not the session. `crash` still enters the monitor on demand. */
HRT_I64 holy_repl_recover_ra, holy_repl_recover_sp, holy_repl_recover_fp;
HRT_I64 holy_repl_recover_armed;
/* Fault info handed to the REPL for its one-line report (mcause/mepc/mtval at the trap). */
HRT_I64 holy_repl_recover_cause, holy_repl_recover_epc, holy_repl_recover_tval;

__attribute__((naked, aligned(4))) static void HolyReplRecoverTramp(void) {
  __asm__ volatile(
    "la t0, holy_repl_recover_sp\n ld sp,0(t0)\n"
    "la t0, holy_repl_recover_fp\n ld s0,0(t0)\n"
    "la t0, holy_repl_recover_ra\n ld ra,0(t0)\n"
    "li a0,1\n"
    "ret\n"
  );
}

__attribute__((naked, aligned(4))) static HRT_I64 HolyRVTrapRecoverArm(void) {
  __asm__ volatile(
    "la t0, holy_repl_recover_ra\n sd ra,0(t0)\n"
    "la t0, holy_repl_recover_sp\n sd sp,0(t0)\n"
    "la t0, holy_repl_recover_fp\n sd s0,0(t0)\n"
    "la t0, holy_repl_recover_armed\n li t1,1\n sd t1,0(t0)\n"
    "li a0,0\n"
    "ret\n"
  );
}

/* Ctrl-C out of a wedged evaluation. `while(1) wfi;` never returns to the REPL's input pump,
 * so the polled UART path can never see the ^C. With the 16550 RX interrupt enabled the IRQ
 * still fires (wfi wakes on an interrupt), and we mret into the recovery trampoline instead of
 * back into the loop. Chars that are NOT the break go to the kernel's own soft RX ring through
 * a registered sink — the runtime's holy_urx ring is a different buffer and the REPL never
 * reads it, so buffering there would silently eat keystrokes. */
HRT_I64 holy_break_req;
/* Debugger hook: called on a synchronous exception once the freeze is published, before the
 * recover/crash-mon decision. Returns 0 to fall through to the existing behaviour, or an
 * address to resume at — which is what lets a debugger's G() continue the stopped context
 * (register edits are already applied by HolyTrapSnapApply on the way out). */
static HRT_I64 (*holy_dbg_hook)(HRT_I64 cause, HRT_I64 epc, HRT_I64 tval);
static HRT_I64 HolyRVSetDbgHook(HRT_I64 fn) {
  holy_dbg_hook = (HRT_I64 (*)(HRT_I64, HRT_I64, HRT_I64))fn;
  return 0;
}
static void (*holy_urx_sink)(HRT_I64);
static HRT_I64 HolyRVSetRxSink(HRT_I64 fn) { holy_urx_sink = (void (*)(HRT_I64))fn; return 0; }

static HRT_I64 HolyRVTrapRecoverDisarm(void) {
  holy_repl_recover_armed = 0;
  return 0;
}
/* ra frozen by HolyTrapVector at the trap: for a fault in a leaf (or a raw asm{} blob)
 * this is the caller, which mepc alone cannot tell you. */
static HRT_I64 HolyRVTrapRecoverRa(void) { return holy_crash_ra; }
static HRT_I64 HolyRVTrapRecoverCause(void) { return holy_repl_recover_cause; }
static HRT_I64 HolyRVTrapRecoverEpc(void)   { return holy_repl_recover_epc; }
static HRT_I64 HolyRVTrapRecoverTval(void)  { return holy_repl_recover_tval; }

static HRT_I64 HolyRVCrashMonInit(void) {
  holy_crash_mon_en = 1;
  HolyRVTrapInit();
  return 0;
}

static HRT_I64 HolyRVCrashMon(void) {
  HRT_I64 mcause, mepc, mtval;
  if (!holy_crash_mon_en)
    holy_crash_mon_en = 1;
  __asm__ volatile("csrr %0, mcause" : "=r"(mcause));
  __asm__ volatile("csrr %0, mepc" : "=r"(mepc));
  __asm__ volatile("csrr %0, mtval" : "=r"(mtval));
  HolyCrashMonEnter(mcause, mepc, mtval);
  return 0;
}

/* Fault freeze, byte-compatible with the seed image's (bootstrap/seed/trap.hc
 * TrapSnapPublish + debug.hc's index map) so one debugger core reads either image:
 *   legacy slots 0..21 at HOLY_TRAP_SNAP  — ra,t0..t6,a0..a7,sp,fp,mcause,mepc,mtval,mstatus
 *   canonical x0..x31 at HOLY_TRAP_SNAP_X — every GPR, indexed by register number
 * HolyTrapVector's frame is indexed the same way (xN at N*8, 256 bytes; x2 implicit).
 * 0x87000400 is NOT MEM_TRAP_SNAP+0x100: 0x87000200/0x208 are the live-Bt ra/s0 scratch
 * (Kernel/RVWinSerial.HC:1023). mstatus is the POST-trap value (MIE clear, MPP/MPIE hold
 * the trapped state). Keep these addresses in step with bootstrap/seed/trap.hc. */
#define HOLY_TRAP_SNAP   0x87000100UL
#define HOLY_TRAP_SNAP_X 0x87000400UL
#define HOLY_TRAP_SNAP_F 0x87000E00UL   /* f0..f31 at the trap */
#define HOLY_TRAP_SNAP_FV 0x87000F00UL  /* [0] = fresh flag, [1] = fcsr */
static void HolyTrapSnapPublish(HRT_I64 *frame, HRT_I64 cause, HRT_I64 epc, HRT_I64 tval) {
  volatile HRT_I64 *leg = (volatile HRT_I64 *)HOLY_TRAP_SNAP;
  volatile HRT_I64 *xs  = (volatile HRT_I64 *)HOLY_TRAP_SNAP_X;
  HRT_I64 sp_at_trap = (HRT_I64)frame + 256, mstatus;
  int i;
  if (!frame) return;
  xs[0] = 0;
  for (i = 1; i < 32; i++) xs[i] = (i == 2) ? sp_at_trap : frame[i];
  leg[0] = frame[1];                                   /* ra */
  for (i = 0; i < 3; i++) leg[1 + i] = frame[5 + i];   /* t0..t2 */
  for (i = 0; i < 4; i++) leg[4 + i] = frame[28 + i];  /* t3..t6 */
  for (i = 0; i < 8; i++) leg[8 + i] = frame[10 + i];  /* a0..a7 */
  leg[16] = sp_at_trap;
  leg[17] = frame[8];                                  /* fp = s0 */
  leg[18] = cause;
  leg[19] = epc;
  leg[20] = tval;
  __asm__ volatile("csrr %0, mstatus" : "=r"(mstatus));
  leg[21] = mstatus;
  /* Slots 22..31: the rest of the machine as it was WHEN IT STOPPED. These are all readable
   * live, but a live read answers about now, not about the fault — mie and mip in particular
   * change under you while you sit at the prompt looking at them. Ten slots is exactly the room
   * between mstatus and the live-Bt scratch at 0x87000200, which is why the list ends here.
   * Index order must match DBG_I_* in bootstrap/seed/debug.hc. */
  {
    HRT_I64 v;
    __asm__ volatile("csrr %0, mtvec"      : "=r"(v)); leg[22] = v;
    __asm__ volatile("csrr %0, mie"        : "=r"(v)); leg[23] = v;
    __asm__ volatile("csrr %0, mip"        : "=r"(v)); leg[24] = v;
    __asm__ volatile("csrr %0, misa"       : "=r"(v)); leg[25] = v;
    __asm__ volatile("csrr %0, mscratch"   : "=r"(v)); leg[26] = v;
    __asm__ volatile("csrr %0, mhartid"    : "=r"(v)); leg[27] = v;
    __asm__ volatile("csrr %0, satp"       : "=r"(v)); leg[28] = v;
    __asm__ volatile("csrr %0, mcounteren" : "=r"(v)); leg[29] = v;
    __asm__ volatile("csrr %0, medeleg"    : "=r"(v)); leg[30] = v;
    __asm__ volatile("csrr %0, mideleg"    : "=r"(v)); leg[31] = v;
  }
  /* The float registers, which no trap path has ever saved — so a debugger showing f0..f31
   * after a fault was showing whatever the asm stepper last left in its own file. Saved here in
   * the dispatcher rather than in the vector: the vector is asm that must not grow a fault of
   * its own, and by here we are in ordinary C with a stack.
   *
   * GUARDED on mstatus.FS. With FS=Off an fsd is an illegal instruction, so saving float state
   * unconditionally would fault inside the trap handler — a loop, not a message. FS=0 leaves the
   * block stale and says so through the fresh flag. */
  {
    volatile HRT_I64 *fs = (volatile HRT_I64 *)HOLY_TRAP_SNAP_F;
    volatile HRT_I64 *fv = (volatile HRT_I64 *)HOLY_TRAP_SNAP_FV;
    if (((mstatus >> 13) & 3) == 0) { fv[0] = 0; }
    else {
      HRT_I64 fcsr;
      __asm__ volatile(
        "fsd f0,   0(%0)\n fsd f1,   8(%0)\n fsd f2,  16(%0)\n fsd f3,  24(%0)\n"
        "fsd f4,  32(%0)\n fsd f5,  40(%0)\n fsd f6,  48(%0)\n fsd f7,  56(%0)\n"
        "fsd f8,  64(%0)\n fsd f9,  72(%0)\n fsd f10, 80(%0)\n fsd f11, 88(%0)\n"
        "fsd f12, 96(%0)\n fsd f13,104(%0)\n fsd f14,112(%0)\n fsd f15,120(%0)\n"
        "fsd f16,128(%0)\n fsd f17,136(%0)\n fsd f18,144(%0)\n fsd f19,152(%0)\n"
        "fsd f20,160(%0)\n fsd f21,168(%0)\n fsd f22,176(%0)\n fsd f23,184(%0)\n"
        "fsd f24,192(%0)\n fsd f25,200(%0)\n fsd f26,208(%0)\n fsd f27,216(%0)\n"
        "fsd f28,224(%0)\n fsd f29,232(%0)\n fsd f30,240(%0)\n fsd f31,248(%0)\n"
        :: "r"(fs) : "memory");
      __asm__ volatile("csrr %0, fcsr" : "=r"(fcsr));
      fv[1] = fcsr;
      fv[0] = 1;   /* the block belongs to this trap, not to the last stepped line */
    }
  }
}

/* Copy the canonical array back into the frame before the vector reloads it, so a register
 * edited while stopped is live on resume (stock TempleOS assigns _RAX/_RIP in the debugger).
 * x0 is hardwired and x2 is the frame's own address, so both are skipped. */
static void HolyTrapSnapApply(HRT_I64 *frame) {
  volatile HRT_I64 *xs = (volatile HRT_I64 *)HOLY_TRAP_SNAP_X;
  int i;
  if (!frame) return;
  for (i = 1; i < 32; i++) {
    if (i == 2) continue;
    frame[i] = xs[i];
  }
}

__attribute__((used)) static HRT_I64 HolyTrapDispatch(HRT_I64 *frame) {
  HRT_I64 mcause;
  __asm__ volatile("csrr %0, mcause" : "=r"(mcause));
  if (mcause == (HRT_I64)0x8000000000000007ULL) {          /* machine timer interrupt */
    holy_ticks++;
    volatile HRT_I64 *mtime    = (volatile HRT_I64 *)HOLY_MTIME;
    volatile HRT_I64 *mtimecmp = (volatile HRT_I64 *)HOLY_MTIMECMP;
    *mtimecmp = *mtime + holy_timer_interval;              /* re-arm */
  } else if (mcause == (HRT_I64)0x800000000000000BULL) {    /* machine external (PLIC) interrupt */
    HolyServiceExternal();
    if (holy_break_req && holy_repl_recover_armed) {
      holy_break_req = 0;
      holy_repl_recover_armed = 0;              /* one-shot, same as the fault path */
      holy_repl_recover_cause = -1;             /* -1 = user break, not a trap */
      holy_repl_recover_epc = 0;
      holy_repl_recover_tval = 0;
      __asm__ volatile("csrw mepc, %0" :: "r"(&HolyReplRecoverTramp));
      /* The REPL lives in M-mode; if the fault came from S/U (e.g. an `sret` typed at
       * the prompt), the trampoline must still run in M-mode: MPP=3, MPIE=1. */
      __asm__ volatile("li t0, 0x1880\n csrs mstatus, t0" ::: "t0");
    }
  } else if (mcause >= 0) {                                 /* synchronous exception */
    HRT_I64 mepc, mtval;
    __asm__ volatile("csrr %0, mepc" : "=r"(mepc));
    __asm__ volatile("csrr %0, mtval" : "=r"(mtval));
    /* Freeze first: the recover trampoline and the crash monitor both want it, and a
     * debugger attached later reads the same two views as in the seed image. */
    HolyTrapSnapPublish(frame, mcause, mepc, mtval);
    if (holy_dbg_hook) {
      HRT_I64 resume = holy_dbg_hook(mcause, mepc, mtval);
      if (resume) {                       /* the debugger says continue here */
        __asm__ volatile("csrw mepc, %0" :: "r"(resume));
        HolyTrapSnapApply(frame);
        return 0;
      }
    }
    if (holy_repl_recover_armed) {
      /* One-shot: disarm before returning, so a fault inside the REPL's own recovery
       * path falls through to the monitor instead of looping through the trampoline. */
      holy_repl_recover_armed = 0;
      holy_repl_recover_cause = mcause;
      holy_repl_recover_epc = mepc;
      holy_repl_recover_tval = mtval;
      __asm__ volatile("csrw mepc, %0" :: "r"(&HolyReplRecoverTramp));
      /* The REPL lives in M-mode; if the fault came from S/U (e.g. an `sret` typed at
       * the prompt), the trampoline must still run in M-mode: MPP=3, MPIE=1. */
      __asm__ volatile("li t0, 0x1880\n csrs mstatus, t0" ::: "t0");
    } else if (holy_crash_mon_en) {
      HolyCrashMonEnter(mcause, mepc, mtval);
      __asm__ volatile("csrr %0, mepc" : "=r"(mepc));
      __asm__ volatile("csrw mepc, %0" :: "r"(mepc + 4)); /* skip faulting insn after go */
    } else {
      __asm__ volatile("csrw mepc, %0" :: "r"(mepc + 4)); /* best-effort skip */
    }
    HolyTrapSnapApply(frame);
  }
  return 0;
}

__attribute__((naked, aligned(4))) static void HolyTrapVector(void) {
  __asm__ volatile(
    "addi sp,sp,-256\n"
    "sd x1,8(sp)\n"
    "sd x3,24(sp)\n"
    "sd x4,32(sp)\n"
    "sd x5,40(sp)\n"
    "sd x6,48(sp)\n"
    "sd x7,56(sp)\n"
    "sd x8,64(sp)\n"
    "sd x9,72(sp)\n"
    "sd x10,80(sp)\n"
    "sd x11,88(sp)\n"
    "sd x12,96(sp)\n"
    "sd x13,104(sp)\n"
    "sd x14,112(sp)\n"
    "sd x15,120(sp)\n"
    "sd x16,128(sp)\n"
    "sd x17,136(sp)\n"
    "sd x18,144(sp)\n"
    "sd x19,152(sp)\n"
    "sd x20,160(sp)\n"
    "sd x21,168(sp)\n"
    "sd x22,176(sp)\n"
    "sd x23,184(sp)\n"
    "sd x24,192(sp)\n"
    "sd x25,200(sp)\n"
    "sd x26,208(sp)\n"
    "sd x27,216(sp)\n"
    "sd x28,224(sp)\n"
    "sd x29,232(sp)\n"
    "sd x30,240(sp)\n"
    "sd x31,248(sp)\n"
    /* Freeze ra/fp/sp for the crash backtrace before the dispatcher's own frame
     * buries them. t0/t1 are already spilled above, so they are free to clobber. */
    "la t0, holy_crash_ra\n sd ra,0(t0)\n"
    "la t0, holy_crash_fp\n sd s0,0(t0)\n"
    "addi t1, sp, 256\n"
    "la t0, holy_crash_sp\n sd t1,0(t0)\n"
    "mv a0, sp\n"                       /* frame pointer: HolyTrapDispatch publishes the freeze */
    "call HolyTrapDispatch\n"
    "ld x1,8(sp)\n"
    "ld x3,24(sp)\n"
    "ld x4,32(sp)\n"
    "ld x5,40(sp)\n"
    "ld x6,48(sp)\n"
    "ld x7,56(sp)\n"
    "ld x8,64(sp)\n"
    "ld x9,72(sp)\n"
    "ld x10,80(sp)\n"
    "ld x11,88(sp)\n"
    "ld x12,96(sp)\n"
    "ld x13,104(sp)\n"
    "ld x14,112(sp)\n"
    "ld x15,120(sp)\n"
    "ld x16,128(sp)\n"
    "ld x17,136(sp)\n"
    "ld x18,144(sp)\n"
    "ld x19,152(sp)\n"
    "ld x20,160(sp)\n"
    "ld x21,168(sp)\n"
    "ld x22,176(sp)\n"
    "ld x23,184(sp)\n"
    "ld x24,192(sp)\n"
    "ld x25,200(sp)\n"
    "ld x26,208(sp)\n"
    "ld x27,216(sp)\n"
    "ld x28,224(sp)\n"
    "ld x29,232(sp)\n"
    "ld x30,240(sp)\n"
    "ld x31,248(sp)\n"
    "addi sp,sp,256\n"
    "mret\n"
  );
}

static HRT_I64 HolyRVTrapInit(void) {
  /* Set the vector and enable interrupts globally, but NOT the timer source: mtimecmp still reads 0
   * here, so enabling MTIE now would fire an immediate, self-perpetuating timer interrupt. MTIE is
   * turned on by RVTimerArm once mtimecmp points at a future time. */
  __asm__ volatile("csrw mtvec, %0" :: "r"(&HolyTrapVector));   /* direct mode (aligned, low bits 0) */
  __asm__ volatile("csrs mstatus, %0" :: "r"((HRT_I64)(1<<3))); /* MIE: global machine interrupt enable */
  return 0;
}
static HRT_I64 HolyRVTimerArm(HRT_I64 interval) {
  holy_timer_interval = interval;
  volatile HRT_I64 *mtime    = (volatile HRT_I64 *)HOLY_MTIME;
  volatile HRT_I64 *mtimecmp = (volatile HRT_I64 *)HOLY_MTIMECMP;
  *mtimecmp = *mtime + interval;                                /* future deadline first */
  __asm__ volatile("csrs mie, %0" :: "r"((HRT_I64)(1<<7)));     /* then enable MTIE */
  return 0;
}
static HRT_I64 HolyRVGetTicks(void) { return holy_ticks; }


/* --- Preemptive scheduler (timer-driven full-context switch) --------------------------------------
 * Distinct from the cooperative RVTaskSwitch: here a machine-timer interrupt saves the ENTIRE
 * interrupted context (x1..x31 + mepc) to the running task's 32-word slot, the picker round-robins
 * to the next runnable task, and mret resumes it at its saved mepc. mscratch always points at the
 * running task's save slot. Layout: word i = x(i+1) for i in 0..30, word 31 = mepc. */
#define HOLY_PMAX 8
static HRT_I64 holy_pctx[HOLY_PMAX*32];
static HRT_I64 holy_pdone[HOLY_PMAX];
static HRT_I64 holy_pwake[HOLY_PMAX];   /* tick at which a sleeping task becomes runnable */
static int holy_pn = 1, holy_pcur = 0;

__attribute__((used)) static void *HolyPreemptPick(void *cur) {
  (void)cur;
  HRT_I64 mcause; __asm__ volatile("csrr %0, mcause" : "=r"(mcause));
  if (mcause == (HRT_I64)0x8000000000000007ULL) {
    holy_ticks++;
    volatile HRT_I64 *mtime=(volatile HRT_I64*)HOLY_MTIME, *mtimecmp=(volatile HRT_I64*)HOLY_MTIMECMP;
    *mtimecmp = *mtime + holy_timer_interval;
  } else if (mcause == (HRT_I64)0x800000000000000BULL) {
    HolyServiceExternal();
  }
  for (int i=0;i<holy_pn;i++) { holy_pcur=(holy_pcur+1)%holy_pn; if(!holy_pdone[holy_pcur] && holy_pwake[holy_pcur] <= holy_ticks) break; }
  return &holy_pctx[holy_pcur*32];
}

__attribute__((naked, aligned(4))) static void HolyPreemptVector(void) {
  __asm__ volatile(
    "csrrw t0, mscratch, t0\n"
    "sd x1,0(t0)\n"
    "sd x2,8(t0)\n"
    "sd x3,16(t0)\n"
    "sd x4,24(t0)\n"
    "sd x6,40(t0)\n"
    "csrr x6, mscratch\n"
    "sd x6,32(t0)\n"
    "sd x7,48(t0)\n"
    "sd x8,56(t0)\n"
    "sd x9,64(t0)\n"
    "sd x10,72(t0)\n"
    "sd x11,80(t0)\n"
    "sd x12,88(t0)\n"
    "sd x13,96(t0)\n"
    "sd x14,104(t0)\n"
    "sd x15,112(t0)\n"
    "sd x16,120(t0)\n"
    "sd x17,128(t0)\n"
    "sd x18,136(t0)\n"
    "sd x19,144(t0)\n"
    "sd x20,152(t0)\n"
    "sd x21,160(t0)\n"
    "sd x22,168(t0)\n"
    "sd x23,176(t0)\n"
    "sd x24,184(t0)\n"
    "sd x25,192(t0)\n"
    "sd x26,200(t0)\n"
    "sd x27,208(t0)\n"
    "sd x28,216(t0)\n"
    "sd x29,224(t0)\n"
    "sd x30,232(t0)\n"
    "sd x31,240(t0)\n"
    "csrr x6, mepc\n"
    "sd x6,248(t0)\n"
    "mv a0, t0\n"
    "call HolyPreemptPick\n"
    "mv t0, a0\n"
    "csrw mscratch, t0\n"
    "ld x6, 248(t0)\n" "csrw mepc, x6\n"
    "ld x1,0(t0)\n"
    "ld x2,8(t0)\n"
    "ld x3,16(t0)\n"
    "ld x4,24(t0)\n"
    "ld x6,40(t0)\n"
    "ld x7,48(t0)\n"
    "ld x8,56(t0)\n"
    "ld x9,64(t0)\n"
    "ld x10,72(t0)\n"
    "ld x11,80(t0)\n"
    "ld x12,88(t0)\n"
    "ld x13,96(t0)\n"
    "ld x14,104(t0)\n"
    "ld x15,112(t0)\n"
    "ld x16,120(t0)\n"
    "ld x17,128(t0)\n"
    "ld x18,136(t0)\n"
    "ld x19,144(t0)\n"
    "ld x20,152(t0)\n"
    "ld x21,160(t0)\n"
    "ld x22,168(t0)\n"
    "ld x23,176(t0)\n"
    "ld x24,184(t0)\n"
    "ld x25,192(t0)\n"
    "ld x26,200(t0)\n"
    "ld x27,208(t0)\n"
    "ld x28,216(t0)\n"
    "ld x29,224(t0)\n"
    "ld x30,232(t0)\n"
    "ld x31,240(t0)\n"
    "ld x5,32(t0)\n"
    "mret\n"
  );
}

static HRT_I64 HolyRVPreemptInit(HRT_I64 interval) {
  holy_pn = 1; holy_pcur = 0; holy_pdone[0] = 0; holy_pwake[0] = 0;
  holy_timer_interval = interval;
  __asm__ volatile("csrw mscratch, %0" :: "r"(&holy_pctx[0]));   /* main = slot 0 */
  __asm__ volatile("csrw mtvec, %0" :: "r"(&HolyPreemptVector));
  __asm__ volatile("csrs mstatus, %0" :: "r"((HRT_I64)(1<<3))); /* MIE */
  volatile HRT_I64 *mtime=(volatile HRT_I64*)HOLY_MTIME, *mtimecmp=(volatile HRT_I64*)HOLY_MTIMECMP;
  *mtimecmp = *mtime + interval;
  __asm__ volatile("csrs mie, %0" :: "r"((HRT_I64)(1<<7)));     /* MTIE last */
  return 0;
}
static HRT_I64 HolyRVPreemptSpawn(void *fn, void *stack_top) {
  if (holy_pn >= HOLY_PMAX) return -1;
  int s = holy_pn;
  for (int i=0;i<32;i++) holy_pctx[s*32+i]=0;
  holy_pctx[s*32+1] = (HRT_I64)stack_top;   /* x2 = sp */
  holy_pctx[s*32+31] = (HRT_I64)fn;         /* mepc = entry */
  holy_pdone[s] = 0;
  holy_pwake[s] = 0;
  holy_pn++;
  return s;
}
static HRT_I64 HolyRVPreemptExit(void) { holy_pdone[holy_pcur]=1; for(;;){} }
static HRT_I64 HolyRVSleep(HRT_I64 ticks) {
  HRT_I64 wake = holy_ticks + (ticks > 0 ? ticks : 1);
  holy_pwake[holy_pcur] = wake;         /* the picker skips this slot until holy_ticks reaches wake */
  while (holy_ticks < wake) { }          /* spins only until the next preemption deschedules us */
  return 0;
}

/* --- Interrupt-driven UART input (QEMU virt 16550 + PLIC) -----------------------------------------
 * A machine external interrupt (PLIC) fires when the UART has a received byte; the handler claims it,
 * drains the RX FIFO into a ring buffer, and completes. A task can then wait on RVUartHasInput while
 * the scheduler runs others, instead of polling the device. UART IRQ is 10 on the virt PLIC. */
#ifndef HOLY_PLIC
#define HOLY_PLIC       0x0C000000
#endif
#ifndef HOLY_PLIC_ENABLE_OFF
#define HOLY_PLIC_ENABLE_OFF     0x2000
#endif
#ifndef HOLY_PLIC_THRESHOLD_OFF
#define HOLY_PLIC_THRESHOLD_OFF  0x200000
#endif
#ifndef HOLY_PLIC_CLAIM_OFF
#define HOLY_PLIC_CLAIM_OFF      0x200004
#endif
#define HOLY_UART_IRQ   10
static char holy_urx[4096];   /* pasted REPL lines burst well past the 16-byte 16550 FIFO */
static int  holy_urx_head = 0, holy_urx_tail = 0;

static volatile HRT_I64 holy_virtio_irqs = 0;   /* count of serviced virtio mmio/PCI completion IRQs */

/* PCI INTx on QEMU virt → PLIC 32..35 (shared). HolyC IrqInit registers virtio ISR status
 * MMIO pointers here so the trap can clear INTx (read clears). MSI-X→IMSIC stays deferred. */
#define HOLY_VIRTIO_PCI_ISR_MAX 8
#define HOLY_PCIE_IRQ_BASE 32
#define HOLY_PCIE_IRQ_COUNT 4
static volatile HRT_U8 *holy_virtio_pci_isr[HOLY_VIRTIO_PCI_ISR_MAX];
static int holy_virtio_pci_isr_n = 0;

static HRT_I64 HolyRVVirtioPciIsrReg(HRT_I64 isr_addr) {
  int i;
  if (!isr_addr) return -1;
  for (i = 0; i < holy_virtio_pci_isr_n; i++)
    if (holy_virtio_pci_isr[i] == (volatile HRT_U8 *)isr_addr) return 0;
  if (holy_virtio_pci_isr_n >= HOLY_VIRTIO_PCI_ISR_MAX) return -1;
  holy_virtio_pci_isr[holy_virtio_pci_isr_n++] = (volatile HRT_U8 *)isr_addr;
  return 0;
}

static void HolyServiceExternal(void) {
  volatile HRT_U32 *claim = (volatile HRT_U32 *)(HOLY_PLIC + HOLY_PLIC_CLAIM_OFF);
  HRT_U32 irq = *claim;
  if (irq == HOLY_UART_IRQ) {
    volatile HRT_U8 *rbr = (volatile HRT_U8 *)HOLY_UART_BASE;
    volatile HRT_U8 *lsr = (volatile HRT_U8 *)(HOLY_UART_BASE + 5);
    while (*lsr & 1) {                                                     /* drain the RX FIFO */
      char c = (char)*rbr;
      if (c == 3 && holy_repl_recover_armed) { holy_break_req = 1; continue; }  /* ^C: break out */
      if (holy_urx_sink) { holy_urx_sink((HRT_I64)(HRT_U8)c); continue; }       /* kernel's ring */
      int nh = (holy_urx_head + 1) & 4095;
      if (nh != holy_urx_tail) { holy_urx[holy_urx_head] = c; holy_urx_head = nh; }
    }
  } else if (irq >= 1 && irq <= 8) {
    /* virtio-mmio slot (HOLY_VIRTIO_MMIO_BASE.. map to PLIC IRQ 1..8). The device keeps asserting
     * the line until its InterruptStatus is acknowledged, so completing the PLIC claim WITHOUT this
     * ack would re-fire forever. Read InterruptStatus (0x60), write it back to InterruptACK (0x64). */
    volatile HRT_U32 *isr  = (volatile HRT_U32 *)(HOLY_VIRTIO_SLOT0_BASE + (HRT_I64)irq*HOLY_VIRTIO_MMIO_STRIDE + 0x60);
    volatile HRT_U32 *iack = (volatile HRT_U32 *)(HOLY_VIRTIO_SLOT0_BASE + (HRT_I64)irq*HOLY_VIRTIO_MMIO_STRIDE + 0x64);
    *iack = *isr;
    holy_virtio_irqs++;
  } else if (irq >= HOLY_PCIE_IRQ_BASE && irq < HOLY_PCIE_IRQ_BASE + HOLY_PCIE_IRQ_COUNT) {
    /* virtio-pci INTx: read each registered ISR status byte (clears the line). */
    int i;
    for (i = 0; i < holy_virtio_pci_isr_n; i++) {
      if (!holy_virtio_pci_isr[i]) continue;
      if (*holy_virtio_pci_isr[i])
        holy_virtio_irqs++;
    }
  }
  if (irq) *claim = irq;                                                   /* complete */
}
static HRT_I64 HolyRVVirtioIrqs(void) { return holy_virtio_irqs; }

static HRT_I64 HolyRVUartIrqInit(void) {
  *(volatile HRT_U8 *)(HOLY_UART_BASE + 1) = 1;                                      /* UART IER: RX-data interrupt */
  *(volatile HRT_U32 *)(HOLY_PLIC + HOLY_UART_IRQ*4) = 1;                  /* PLIC priority[irq] = 1 */
  *(volatile HRT_U32 *)(HOLY_PLIC + HOLY_PLIC_ENABLE_OFF) |= (1u << HOLY_UART_IRQ);
  *(volatile HRT_U32 *)(HOLY_PLIC + HOLY_PLIC_THRESHOLD_OFF) = 0;
  __asm__ volatile("csrs mie, %0" :: "r"((HRT_I64)(1<<11)));              /* MEIE: machine external int */
  return 0;
}
/* Turn the 16550 RX interrupt back off. The REPL enables it only while a command runs (when
 * nothing is polling) and disables it again before returning to the input pump: with both
 * active the ISR and the poller race for the same FIFO and keystrokes vanish — the more the
 * kernel printed, the more often the ISR won. */
static HRT_I64 HolyRVUartIrqOff(void) {
  *(volatile HRT_U8 *)(HOLY_UART_BASE + 1) = 0;                            /* IER: RX int off */
  *(volatile HRT_U32 *)(HOLY_PLIC + HOLY_PLIC_ENABLE_OFF) &= ~(1u << HOLY_UART_IRQ);
  return 0;
}
static HRT_I64 HolyRVUartHasInput(void) { return holy_urx_head != holy_urx_tail; }
static HRT_I64 HolyRVUartGetBuffered(void) {
  if (holy_urx_head == holy_urx_tail) return -1;
  char c = holy_urx[holy_urx_tail]; holy_urx_tail = (holy_urx_tail + 1) & 4095; return (HRT_U8)c;
}

/* --- virtio-blk (legacy virtio-mmio v1) storage driver -------------------------------------------
 * QEMU virt exposes 8 virtio-mmio slots at HOLY_VIRTIO_MMIO_BASE..; a -device virtio-blk-device lands
 * in one with DeviceID 2. Legacy setup uses one page-aligned queue region (descriptors+avail, then
 * the used ring at QueueAlign) addressed by QueuePFN. A block request is a 3-descriptor chain:
 * header (type+sector), the 512-byte data buffer, and a status byte. We submit on the avail ring,
 * notify, and poll the used ring for completion (no IRQ needed). */
#define VBLK_QSIZE 8
typedef struct { HRT_U64 addr; HRT_U32 len; HRT_U16 flags; HRT_U16 next; } HolyVqDesc;
typedef struct { HRT_U32 type; HRT_U32 reserved; HRT_U64 sector; } HolyVblkReq;
static char holy_virtq[8192] __attribute__((aligned(4096)));
static volatile HRT_U32 *holy_vblk = 0;
static HolyVblkReq holy_vhdr;
static volatile HRT_U8 holy_vstatus;

static HRT_I64 HolyRVBlkInit(void) {
  for (int slot=1; slot<=8; slot++) {
    volatile HRT_U32 *b = (volatile HRT_U32 *)(HOLY_VIRTIO_SLOT0_BASE + slot*HOLY_VIRTIO_MMIO_STRIDE);
    if (b[0]==0x74726976 && b[2]==2) { holy_vblk = b; break; }
  }
  if (!holy_vblk) return -1;
  volatile HRT_U32 *b = holy_vblk;
  b[0x70/4] = 0;                 /* reset */
  b[0x70/4] = b[0x70/4] | 1;     /* ACKNOWLEDGE */
  b[0x70/4] = b[0x70/4] | 2;     /* DRIVER */
  b[0x14/4] = 0; (void)b[0x10/4];/* features sel 0 */
  b[0x24/4] = 0; b[0x20/4] = 0;  /* accept no optional features */
  b[0x28/4] = 4096;              /* guest page size */
  b[0x30/4] = 0;                 /* queue sel 0 */
  b[0x38/4] = VBLK_QSIZE;        /* queue num */
  b[0x3c/4] = 4096;              /* queue align */
  for (int i=0;i<8192;i++) holy_virtq[i]=0;
  b[0x40/4] = (HRT_U32)(((HRT_U64)holy_virtq) / 4096);  /* queue PFN */
  b[0x70/4] = b[0x70/4] | 4;     /* DRIVER_OK */
  return 0;
}

static HRT_I64 HolyBlkOp(HRT_I64 sector, void *buf, int write) {
  if (!holy_vblk) return -1;
  volatile HRT_U32 *b = holy_vblk;
  HolyVqDesc *desc = (HolyVqDesc *)holy_virtq;
  volatile HRT_U16 *avail = (volatile HRT_U16 *)(holy_virtq + VBLK_QSIZE*16);
  volatile HRT_U16 *used  = (volatile HRT_U16 *)(holy_virtq + 4096);
  holy_vhdr.type = write ? 1 : 0; holy_vhdr.reserved = 0; holy_vhdr.sector = (HRT_U64)sector;
  holy_vstatus = 0xff;
  desc[0].addr=(HRT_U64)&holy_vhdr;   desc[0].len=16;  desc[0].flags=1;               desc[0].next=1; /* NEXT */
  desc[1].addr=(HRT_U64)buf;          desc[1].len=512; desc[1].flags=1|(write?0:2);   desc[1].next=2; /* NEXT|WRITE? */
  desc[2].addr=(HRT_U64)&holy_vstatus;desc[2].len=1;   desc[2].flags=2;               desc[2].next=0; /* WRITE */
  HRT_U16 uidx = used[1];
  HRT_U16 aidx = avail[1];
  avail[2 + (aidx % VBLK_QSIZE)] = 0;             /* ring[idx] = head descriptor 0 */
  __asm__ volatile("fence" ::: "memory");
  avail[1] = aidx + 1;
  __asm__ volatile("fence" ::: "memory");
  b[0x50/4] = 0;                                  /* QueueNotify = queue 0 */
  while (used[1] == uidx) { __asm__ volatile("fence" ::: "memory"); }
  b[0x64/4] = b[0x60/4];                          /* InterruptACK */
  return holy_vstatus;                            /* 0 = VIRTIO_BLK_S_OK */
}
static HRT_I64 HolyRVBlkRead(HRT_I64 sector, void *buf)  { return HolyBlkOp(sector, buf, 0); }
static HRT_I64 HolyRVBlkWrite(HRT_I64 sector, void *buf) { return HolyBlkOp(sector, buf, 1); }

/* --- Authentic TempleOS-style context switch --------------------------------------------------
 * Save the RISC-V callee-saved registers (s0..s11) + ra onto the CURRENT task's stack, store the new
 * sp into *from_rsp_slot (that is `&CTask.rsp`), then load *to_rsp_slot into sp and pop — resuming the
 * target task where it last yielded, or, for a freshly spawned task whose stack was pre-loaded with a
 * {zeroed s0..s11, ra=entry} frame, jumping straight to its entry. Mirrors how TempleOS saves the
 * register frame on the task's own stack with CTask.rsp pointing at it (Sched.HC TASK_CONTEXT_*). */
__attribute__((naked)) static HRT_I64 HolyRVCtxSw(void *from_rsp_slot, void *to_rsp_slot) {
  __asm__ volatile(
    "addi sp,sp,-104\n"
    "sd s0,0(sp)\n"
    "sd s1,8(sp)\n"
    "sd s2,16(sp)\n"
    "sd s3,24(sp)\n"
    "sd s4,32(sp)\n"
    "sd s5,40(sp)\n"
    "sd s6,48(sp)\n"
    "sd s7,56(sp)\n"
    "sd s8,64(sp)\n"
    "sd s9,72(sp)\n"
    "sd s10,80(sp)\n"
    "sd s11,88(sp)\n"
    "sd ra,96(sp)\n"
    "sd sp,0(a0)\n"
    "ld sp,0(a1)\n"
    "ld s0,0(sp)\n"
    "ld s1,8(sp)\n"
    "ld s2,16(sp)\n"
    "ld s3,24(sp)\n"
    "ld s4,32(sp)\n"
    "ld s5,40(sp)\n"
    "ld s6,48(sp)\n"
    "ld s7,56(sp)\n"
    "ld s8,64(sp)\n"
    "ld s9,72(sp)\n"
    "ld s10,80(sp)\n"
    "ld s11,88(sp)\n"
    "ld ra,96(sp)\n"
    "addi sp,sp,104\n"
    "ret\n"
  );
}

/* Critical section for the preemptive scheduler: disable/restore the machine interrupt-enable so a
 * read-modify-write on shared state can't be split by a timer preemption. Nesting-safe — Enter
 * returns the previous MIE state, Leave takes it back. Single-core; not an SMP lock. */
static HRT_I64 HolyRVCritEnter(void) {
  HRT_I64 old;
  __asm__ volatile("csrrci %0, mstatus, 8" : "=r"(old));   /* clear MIE (bit 3), return old mstatus */
  return old & 8;                                          /* nonzero if interrupts were enabled */
}
static HRT_I64 HolyRVCritLeave(HRT_I64 was_enabled) {
  if (was_enabled) __asm__ volatile("csrsi mstatus, 8");   /* re-enable MIE */
  return 0;
}


/* Cooperative context switch: save the current callee-saved regs + sp + ra into *save (a 14-word
 * HolyTaskCtx: ra, sp, s0..s11), load them from *load, and `ret` into load's saved ra. A task
 * spawned with ra=entry and sp=fresh-stack-top starts there on its first switch-in. */
__attribute__((naked)) static HRT_I64 HolyRVTaskSwitch(void *save, void *load) {
  __asm__ volatile(
    "sd ra,0(a0)\n sd sp,8(a0)\n"
    "sd s0,16(a0)\n sd s1,24(a0)\n sd s2,32(a0)\n sd s3,40(a0)\n sd s4,48(a0)\n sd s5,56(a0)\n"
    "sd s6,64(a0)\n sd s7,72(a0)\n sd s8,80(a0)\n sd s9,88(a0)\n sd s10,96(a0)\n sd s11,104(a0)\n"
    "ld ra,0(a1)\n ld sp,8(a1)\n"
    "ld s0,16(a1)\n ld s1,24(a1)\n ld s2,32(a1)\n ld s3,40(a1)\n ld s4,48(a1)\n ld s5,56(a1)\n"
    "ld s6,64(a1)\n ld s7,72(a1)\n ld s8,80(a1)\n ld s9,88(a1)\n ld s10,96(a1)\n ld s11,104(a1)\n"
    "ret\n"
  );
}
/* Authentic kernel Yield: walk Fs->next_task (the real CTask list), skip TASKf_KILL_TASK tasks, and
 * context-switch on the real CTask.rsp — the same shape as Sched.HC _YIELD. The runtime learns where
 * Fs lives (a CTask** slot) and the CTask field offsets via RVYieldInit; before that it is a no-op so
 * single-task code runs unchanged. */
static HRT_I64 HolyRVCtxSw(void *from_rsp_slot, void *to_rsp_slot);
static void **holy_fs_slot = 0;              /* &Fs : points at the current-CTask pointer */
#define HOLY_CTASK_WAKE   16                 /* offset(CTask.wake_jiffy) */
#define HOLY_CTASK_FLAGS  24                 /* offset(CTask.task_flags) */
#define HOLY_CTASK_NEXT   128                /* offset(CTask.next_task) */
#define HOLY_CTASK_RSP    296                /* offset(CTask.rsp) */
#define HOLY_TASKf_KILL         1            /* TASKf_KILL_TASK bit */
#define HOLY_TASKf_SUSPENDED    2            /* TASKf_SUSPENDED bit */
#define HOLY_TASKf_AWAITING_MSG 9            /* TASKf_AWAITING_MSG bit */
static HRT_I64 HolyRVYieldInit(void *fs_slot) { holy_fs_slot = (void **)fs_slot; return 0; }

/* Jiffy clock, derived from the machine timer (mtime) so it advances whether we are polling from a
 * cooperative Yield or spinning in the idle path — no dependency on the timer trap handler
 * re-entering. Set
 * holy_jiffy_div to the number of mtime ticks per jiffy (QEMU virt mtime is 10 MHz, so 10000 -> a
 * 1 ms / ~1000 Hz jiffy, matching TempleOS's JIFFY_FREQ). 0 disables wake_jiffy checks entirely. */
static HRT_I64 holy_jiffy_div = 0;
static HRT_I64 HolyRVJiffies(void) {
  if (!holy_jiffy_div) return 0;
  volatile HRT_I64 *mt = (volatile HRT_I64 *)HOLY_MTIME;
  return *mt / holy_jiffy_div;
}
static HRT_I64 HolyRVJiffiesInit(HRT_I64 mtime_ticks_per_jiffy) {
  holy_jiffy_div = mtime_ticks_per_jiffy;
  return 0;
}

/* Is a task eligible to run right now? Mirrors Sched.HC RESTORE_RSI_TASK's skip conditions: killed,
 * suspended and awaiting-message tasks are passed over, and a task sleeping via wake_jiffy is not
 * runnable until the jiffy clock reaches its wake time. */
static int HolyTaskRunnable(char *t) {
  HRT_I64 fl = *(HRT_I64 *)(t + HOLY_CTASK_FLAGS);
  if (fl & ((1 << HOLY_TASKf_KILL) | (1 << HOLY_TASKf_SUSPENDED) | (1 << HOLY_TASKf_AWAITING_MSG)))
    return 0;
  if (holy_jiffy_div && *(HRT_I64 *)(t + HOLY_CTASK_WAKE) > HolyRVJiffies())
    return 0;
  return 1;
}

static HRT_I64 HolyYield(void) {
  if (!holy_fs_slot || !*holy_fs_slot) return 0;      /* not wired yet -> single task */
  char *cur = (char *)*holy_fs_slot;
  char *nxt;
  /* Round-robin scan for the next runnable task (Sched.HC's next_task walk). If none but cur is
   * runnable, keep running cur. If NOBODY is runnable (every task sleeping/suspended), idle: mask
   * interrupts and poll mtime so the jiffy clock still advances, then rescan — TempleOS x86 idle
   * used STI;HLT;rescan; here we poll mtime instead of waiting for a timer trap. */
  for (;;) {
    nxt = *(char **)(cur + HOLY_CTASK_NEXT);
    while (nxt != cur && !HolyTaskRunnable(nxt))
      nxt = *(char **)(nxt + HOLY_CTASK_NEXT);
    if (nxt != cur) break;                            /* found another runnable task */
    if (HolyTaskRunnable(cur)) {                      /* only cur runnable -> resume it */
      __asm__ volatile("csrs mstatus, %0" :: "r"((HRT_I64)(1 << 3)));
      return 0;
    }
    __asm__ volatile("csrc mstatus, %0" :: "r"((HRT_I64)(1 << 3)));   /* idle: mask interrupts */
    { volatile HRT_I64 *mt = (volatile HRT_I64 *)HOLY_MTIME; HRT_I64 t0 = *mt; while (*mt - t0 < 1000) {} }
  }
  *holy_fs_slot = nxt;                                /* Fs = next task */
  /* The task we switch to must run with interrupts ENABLED: reached from the timer trap handler,
   * mstatus.MIE was cleared on trap entry, and reached from the idle path we just masked it —
   * either way an incoming task that never yields could not otherwise be preempted. */
  __asm__ volatile("csrs mstatus, %0" :: "r"((HRT_I64)(1 << 3)));
  HolyRVCtxSw(cur + HOLY_CTASK_RSP, nxt + HOLY_CTASK_RSP);
  return 0;
}

/* --- Real-CTask timer preemption --------------------------------------------------------------- */
__attribute__((used)) static void HolyTimerReArm(void) {
  volatile HRT_I64 *mtime=(volatile HRT_I64*)HOLY_MTIME, *mtimecmp=(volatile HRT_I64*)HOLY_MTIMECMP;
  *mtimecmp = *mtime + holy_timer_interval;
}
__attribute__((naked, aligned(4))) static void HolyRealPreemptVector(void) {
  __asm__ volatile(
    "addi sp,sp,-144\n"
    "sd ra,0(sp)\n"
    "sd t0,8(sp)\n"
    "sd t1,16(sp)\n"
    "sd t2,24(sp)\n"
    "sd a0,32(sp)\n"
    "sd a1,40(sp)\n"
    "sd a2,48(sp)\n"
    "sd a3,56(sp)\n"
    "sd a4,64(sp)\n"
    "sd a5,72(sp)\n"
    "sd a6,80(sp)\n"
    "sd a7,88(sp)\n"
    "sd t3,96(sp)\n"
    "sd t4,104(sp)\n"
    "sd t5,112(sp)\n"
    "sd t6,120(sp)\n"
    "csrr t0, mepc\n" "sd t0,128(sp)\n"
    "csrr t0, mstatus\n" "sd t0,136(sp)\n"
    "call HolyTimerReArm\n"
    "call HolyYield\n"
    "ld t0,136(sp)\n" "csrw mstatus, t0\n"
    "ld t0,128(sp)\n" "csrw mepc, t0\n"
    "ld ra,0(sp)\n"
    "ld t0,8(sp)\n"
    "ld t1,16(sp)\n"
    "ld t2,24(sp)\n"
    "ld a0,32(sp)\n"
    "ld a1,40(sp)\n"
    "ld a2,48(sp)\n"
    "ld a3,56(sp)\n"
    "ld a4,64(sp)\n"
    "ld a5,72(sp)\n"
    "ld a6,80(sp)\n"
    "ld a7,88(sp)\n"
    "ld t3,96(sp)\n"
    "ld t4,104(sp)\n"
    "ld t5,112(sp)\n"
    "ld t6,120(sp)\n"
    "addi sp,sp,144\n" "mret\n"
  );
}
/* --- Diagnostic trap handler: prints mcause/mepc/mtval to the UART and halts. Temporary; used to
 * decide whether a "hang" is actually a synchronous fault. Install with HolyRVTrapDiag().
 * mcause line matches McausePrint / holy_crash_put_mcause symbolic form. ------------------------- */
__attribute__((used)) static void HolyTrapDiagBody(void) {
  HRT_I64 mcause, mepc, mtval;
  __asm__ volatile("csrr %0, mcause" : "=r"(mcause));
  __asm__ volatile("csrr %0, mepc"   : "=r"(mepc));
  __asm__ volatile("csrr %0, mtval"  : "=r"(mtval));
  HOLY_RT_PUTC('\n');
  rt_puts("TRAP ");
  holy_crash_put_mcause(mcause);
  HOLY_RT_PUTC('\n');
  rt_puts("mepc=");
  holy_crash_puthex((HRT_U64)mepc);
  rt_puts(" mtval=");
  holy_crash_puthex((HRT_U64)mtval);
  HOLY_RT_PUTC('\n');
  for (;;) __asm__ volatile("wfi");
}
__attribute__((naked, aligned(4))) static void HolyTrapDiagVector(void) {
  __asm__ volatile("call HolyTrapDiagBody");
}
static HRT_I64 HolyRVTrapDiag(void) {
  __asm__ volatile("csrw mtvec, %0" :: "r"(&HolyTrapDiagVector));
  return 0;
}

static HRT_I64 HolyRVPreemptReal(HRT_I64 interval) {
  holy_timer_interval = interval;
  __asm__ volatile("csrw mtvec, %0" :: "r"(&HolyRealPreemptVector));
  __asm__ volatile("csrs mstatus, %0" :: "r"((HRT_I64)(1<<3)));
  volatile HRT_I64 *mtime=(volatile HRT_I64*)HOLY_MTIME, *mtimecmp=(volatile HRT_I64*)HOLY_MTIMECMP;
  *mtimecmp = *mtime + interval;
  __asm__ volatile("csrs mie, %0" :: "r"((HRT_I64)(1<<7)));
  return 0;
}
static HRT_I64 HolyTaskEndNow(void) { rt_puts("[TaskEndNow]\n"); for (;;) __asm__ volatile("wfi"); }
/* D: hex dump `n` bytes at `p`, 16 per line with ASCII */
static HRT_I64 HolyD(HRT_U8 *p, HRT_I64 n) {
  for (HRT_I64 off = 0; off < n; off += 16) {
    rt_putnum((HRT_U64)off, 16, 1, 0, 4, '0', 0); HOLY_RT_PUTC(':');
    for (HRT_I64 i = 0; i < 16; i++) {
      HOLY_RT_PUTC(' ');
      if (off + i < n) rt_putnum(p[off + i], 16, 1, 0, 2, '0', 0); else rt_puts("  ");
    }
    HOLY_RT_PUTC(' ');
    for (HRT_I64 i = 0; i < 16 && off + i < n; i++) { HRT_U8 c = p[off + i]; HOLY_RT_PUTC((c >= 32 && c < 127) ? (char)c : '.'); }
    HOLY_RT_PUTC('\n');
  }
  return 0;
}
static HRT_I64 HolySeed(HRT_I64 s) { rt_rand_state = (HRT_U64)s ? (HRT_U64)s : 1; return 0; }

static HRT_I64 HolyRVRunBlob(HRT_I64 addr, HRT_I64 size);   /* defined after holy_resolve_imports */
typedef struct { const char *name; void *fn; HRT_I64 argc; } HolyRtEntry;
#define HOLY_RT_ENTRY(n, a) { #n, (void *)Holy##n, a },
static const HolyRtEntry holy_rt_table[] = { HOLY_RT_NAMES(HOLY_RT_ENTRY) };
#define HOLY_RT_COUNT ((HRT_I64)(sizeof(holy_rt_table) / sizeof(holy_rt_table[0])))

/* AOT blobs end with an import directory: entries {u64 slot_offset; char name[24]} ×count,
 * then u64 count, u64 magic. Fill each slot with the runtime entry point of that name. */
#define HOLY_IMPORT_MAGIC 0x31504D4959464F48ULL  /* "HOFYIMP1" little-endian bytes */
static HRT_I64 holy_unresolved_import(void) { rt_puts("[unresolved import]\n"); return 0; }
static HRT_I64 holy_resolve_imports(HRT_U8 *blob_start, HRT_U8 *blob_end) {
  if (blob_end - blob_start < 16) return 0;
  HRT_U64 magic, count;
  HRT_U8 *mp = (HRT_U8 *)&magic, *cp = (HRT_U8 *)&count;
  for (int i = 0; i < 8; i++) { mp[i] = blob_end[-8 + i]; cp[i] = blob_end[-16 + i]; }
  if (magic != HOLY_IMPORT_MAGIC) return 0;
  HRT_U8 *ent = blob_end - 16 - (HRT_I64)count * 32;
  HRT_I64 resolved = 0;
  for (HRT_U64 k = 0; k < count; k++, ent += 32) {
    HRT_U64 slot; HRT_U8 *sp = (HRT_U8 *)&slot; for (int i = 0; i < 8; i++) sp[i] = ent[i];
    const char *name = (const char *)ent + 8;
    { HRT_U64 fn = (HRT_U64)holy_unresolved_import; HRT_U8 *fp = (HRT_U8 *)&fn;
      for (int i = 0; i < 8; i++) blob_start[slot + (HRT_U64)i] = fp[i]; }   /* default: diagnostic stub */
    int found = 0;
    for (HRT_I64 j = 0; j < HOLY_RT_COUNT; j++) {
      const char *a = holy_rt_table[j].name, *b = name;
      while (*a && *a == *b) { a++; b++; }
      if (*a == 0 && *b == 0) {
        HRT_U64 fn = (HRT_U64)holy_rt_table[j].fn; HRT_U8 *fp = (HRT_U8 *)&fn;
        for (int i = 0; i < 8; i++) blob_start[slot + (HRT_U64)i] = fp[i];
        resolved++;
        found = 1;
        break;
      }
    }
    if (!found) { rt_puts("[import unresolved: "); rt_puts(name); rt_puts("]\n"); }   /* named once, at load */
  }
  return resolved;
}

/* Run a blob loaded at an arbitrary address: resolve its import trailer in place (holy_resolve_imports
 * writes the runtime function addresses into the blob's own import slots), then enter at byte 0 — the
 * first function, main() for a single-unit program. AOT code is PC-relative for its own code/data, so
 * a blob runs wherever it is placed once its imports are filled. Returns the blob's return value. */
static HRT_I64 HolyRVRunBlob(HRT_I64 addr, HRT_I64 size) {
  holy_resolve_imports((HRT_U8 *)addr, (HRT_U8 *)(addr + size));
  HRT_I64 (*fn)(void) = (HRT_I64 (*)(void))addr;
  return fn();
}
#endif
