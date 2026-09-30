// The three string/memory primitives cFS needs that TempleOS does NOT already have.
//
// This file used to be cfe_xlat_libc.HC and it was a mistake: it reimplemented memset, memcpy,
// strcmp and a mini snprintf in HolyC, sitting next to a kernel that already has all four.
// TempleOS's own set, confirmed by grepping the stock distro rather than assumed, is
//
//     MemCpy MemSet MemRep StrCpy StrLen StrCmp StrNCmp StrMatch StrPrint StrPrintJoin
//     StrNew StrOcc
//
// so the translation now CALLS those directly. The mapping is exact, not approximate:
//
//   memset(d,c,n)  -> MemSet(d,c,n)   RVMemSet(U8 *dst, I64 dat, I64 size), same argument
//                                     order as C's, and it returns dst as C's does.
//   memcpy(d,s,n)  -> MemCpy(d,s,n)   RVMemCpy(U8 *dst, U8 *src, I64 size), likewise.
//   strlen(s)      -> StrLen(s)
//   strcmp(a,b)    -> StrCmp(a,b)     SIGN-compatible with C: _STRCMP (Kernel/StrA.HC:85) puts
//                                     st2 in RSI and st1 in RDI, and `JA` -> -1, so st1 < st2
//                                     gives a negative result. The MAGNITUDE is only ever +-1,
//                                     never a byte difference -- every cFS call site compares
//                                     against zero, so that is equivalent here, and a future
//                                     call site that wants the difference must not use it.
//
// Three have no TempleOS equivalent anywhere in the distro, so they are written here. They are
// ADDITIONS in TempleOS style, not renames of something that already existed:
#ifndef CFS_STR_HC
#define CFS_STR_HC

// C's memchr. cFS uses it for exactly one thing -- "is there a NUL within the first n bytes",
// the bounded name-length check -- and StrLen cannot do that job, because on an unterminated
// buffer StrLen is what runs off the end. That is why NASA uses memchr here and so do we.
U8 *MemChr(U8 *s, I64 c, I64 n)
{
  I64 i = 0;
  while (i < n) {
    if (s[i] == (c & 0xFF))
      return &s[i];
    i++;
  }
  return NULL;
}

// C's strncpy, INCLUDING the sharp edges, because the translation's correctness rests on them:
// at most n bytes are copied; if src is shorter the remainder of n is filled with NULs; and if
// src is n or longer the result is NOT terminated. Every cFS call site passes n = SIZE - 1 into
// a buffer that was just MemSet to zero, which is what makes that safe there.
U8 *StrNCpy(U8 *dst, U8 *src, I64 n)
{
  I64 i = 0;
  while (i < n && src[i]) {
    dst[i] = src[i];
    i++;
  }
  while (i < n) {
    dst[i] = 0;
    i++;
  }
  return dst;
}


// A SIZE-BOUNDED formatter, in TempleOS naming (the N is the bound, as in StrNCmp).
//
// TempleOS has StrPrint and StrPrintJoin, and they are the right thing in the kernel -- but
// neither is size-bounded, and StrPrintJoin allocates, so neither can serve a fixed cFS buffer
// or run in the standalone oracle harness where there is no heap.
//
// It follows C's conversions rather than TempleOS's, and that is deliberate: the format strings
// it is handed are NASA's own, verbatim, because they are part of the translated source. Feeding
// "%ld" to TempleOS's StrPrint would be feeding it a string it does not speak; rewriting the
// format strings would mean the translation no longer says what NASA wrote, which is the one
// property every gate here rests on. So the SPELLING is TempleOS and the CONVERSIONS are C, and
// the reason is that the input is C.
//
// Covers exactly the conversions the translated call sites use: %s, %u, %d and %ld. Anything
// else is emitted literally so an unhandled case appears in a transcript instead of vanishing.
//
// Truncation and the return value are C's snprintf: at most Size-1 characters plus a NUL,
// nothing at all when Size is 0, and the return is the length that WOULD have been written, so
// it can exceed Size. No cFS call site uses the return today; it is faithful anyway.
//
// HolyC has variadics, but a fixed arity with defaults is enough and reads better: the widest
// translated call passes five arguments.
I64 StrPrintN(U8 *Buf, I64 Size, U8 *Fmt, I64 a0=0, I64 a1=0, I64 a2=0, I64 a3=0, I64 a4=0)
{
  I64 args[5];
  I64 ai = 0, n = 0, i;
  U8 dig[24];
  U8 *sp;
  U64 uv;
  I64 sv;
  args[0] = a0;
  args[1] = a1;
  args[2] = a2;
  args[3] = a3;
  args[4] = a4;
  while (*Fmt) {
    if (*Fmt != '%') {
      if (Size > 0 && n < Size - 1)
        Buf[n] = *Fmt;
      n++;
      Fmt++;
      continue;
    }
    Fmt++;
    if (*Fmt == 's') {
      sp = args[ai++](U8 *);
      if (sp == NULL)
        sp = "(null)";
      while (*sp) {
        if (Size > 0 && n < Size - 1)
          Buf[n] = *sp;
        n++;
        sp++;
      }
    } else if (*Fmt == 'd' || *Fmt == 'l') {
      // %d and %ld. OSAL prints status codes with both, and they are NEGATIVE -- treating them
      // as unsigned would print 18446744073709551615 where NASA prints -1.
      if (*Fmt == 'l') {
        Fmt++;              // consume the length modifier; 'l' is 64-bit here either way
        if (*Fmt != 'd' && *Fmt != 'u')
          Fmt--;            // not %ld/%lu after all: let the default branch see it
      }
      sv = args[ai++];
      if (sv < 0) {
        if (Size > 0 && n < Size - 1)
          Buf[n] = '-';
        n++;
        sv = -sv;
      }
      uv = sv;
      i = 0;
      if (!uv)
        dig[i++] = '0';
      while (uv > 0) {
        dig[i++] = '0' + uv % 10;
        uv /= 10;
      }
      while (i > 0) {
        i--;
        if (Size > 0 && n < Size - 1)
          Buf[n] = dig[i];
        n++;
      }
    } else if (*Fmt == 'u') {
      uv = args[ai++];
      i = 0;
      if (!uv)
        dig[i++] = '0';
      while (uv > 0) {
        dig[i++] = '0' + uv % 10;
        uv /= 10;
      }
      while (i > 0) {
        i--;
        if (Size > 0 && n < Size - 1)
          Buf[n] = dig[i];
        n++;
      }
    } else {
      // Any other conversion is one this port has not had to translate yet. Emit it literally
      // rather than silently dropping it, so an unhandled case shows up in a transcript.
      if (Size > 0 && n < Size - 1)
        Buf[n] = '%';
      n++;
      if (Size > 0 && n < Size - 1)
        Buf[n] = *Fmt;
      n++;
    }
    if (*Fmt)
      Fmt++;
  }
  if (Size > 0) {
    if (n < Size)
      Buf[n] = 0;
    else
      Buf[Size - 1] = 0;
  }
  return n;
}
#endif
