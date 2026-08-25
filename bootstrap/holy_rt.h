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

/* Print: %[flags][width][.prec][h<n>|h*|h?]<conv>. Conversions: d u x X c s p P n f %.
 * HolyC extras: ',' thousands separators; h<n>/h* repeat count for %c; h? ignored. */
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

typedef struct { const char *name; void *fn; HRT_I64 argc; } HolyRtEntry;
#define HOLY_RT_ENTRY(n, a) { #n, (void *)Holy##n, a },
static const HolyRtEntry holy_rt_table[] = { HOLY_RT_NAMES(HOLY_RT_ENTRY) };
#define HOLY_RT_COUNT ((HRT_I64)(sizeof(holy_rt_table) / sizeof(holy_rt_table[0])))

/* AOT blobs end with an import directory: entries {u64 slot_offset; char name[24]} ×count,
 * then u64 count, u64 magic. Fill each slot with the runtime entry point of that name. */
#define HOLY_IMPORT_MAGIC 0x31504D4959464F48ULL  /* "HOFYIMP1" little-endian bytes */
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
    for (HRT_I64 j = 0; j < HOLY_RT_COUNT; j++) {
      const char *a = holy_rt_table[j].name, *b = name;
      while (*a && *a == *b) { a++; b++; }
      if (*a == 0 && *b == 0) {
        HRT_U64 fn = (HRT_U64)holy_rt_table[j].fn; HRT_U8 *fp = (HRT_U8 *)&fn;
        for (int i = 0; i < 8; i++) blob_start[slot + (HRT_U64)i] = fp[i];
        resolved++;
        break;
      }
    }
  }
  return resolved;
}
#endif
