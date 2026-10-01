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
// Covers exactly the conversions the translated call sites use: %s, %u, %d, %x, %X, the 'l'
// and 'll' length modifiers, and a leading zero-or-space field width as in %08x. Anything else
// is emitted literally so an unhandled case appears in a transcript instead of vanishing.
//
// The hex and width forms were added when EVS arrived: it is the first translated module whose
// FORMATTED OUTPUT is the payload (the event text is the packet), so for the first time the
// formatter's agreement with C is inside the byte-identical comparison rather than beside it.
//
// Truncation and the return value are C's snprintf: at most Size-1 characters plus a NUL,
// nothing at all when Size is 0, and the return is the length that WOULD have been written, so
// it can exceed Size. No cFS call site uses the return today; it is faithful anyway.
//
// HolyC has variadics, and the core below takes the (fmt, argc, argv) triple one receives; the
// fixed-arity wrapper is for the translated call sites that pass a known list. The widest of
// those is EVS_SendViaPorts, with six.
// The core, taking the (fmt, argc, argv) triple that a HolyC variadic function receives -- the
// same shape TempleOS's own StrPrintJoin takes, so OS_printf can hand its varargs straight
// through. StrPrintN below is the fixed-arity convenience that packs into the same call.
I64 StrPrintNV(U8 *Buf, I64 Size, U8 *Fmt, I64 nargs, I64 *args)
{
  I64 ai = 0, n = 0, i;
  U8 dig[24];
  U8 *sp;
  U64 uv;
  I64 sv;
  I64 ndig;
  I64 neg;
  I64 width;
  I64 zeropad;
  U64 base;
  I64 upper;
  I64 islong;
  U8 *hexd;
  while (*Fmt) {
    if (*Fmt != '%') {
      if (Size > 0 && n < Size - 1)
        Buf[n] = *Fmt;
      n++;
      Fmt++;
      continue;
    }
    Fmt++;
    // C's flags and field width, in the one combination cFS uses: an optional '0' and an
    // optional decimal width, as in "%08x". Parsed before the conversion so that a width on a
    // conversion this does not handle still comes out as the literal text, rather than being
    // half-consumed.
    zeropad = 0;
    width = 0;
    if (*Fmt == '0') {
      zeropad = 1;
      Fmt++;
    }
    while (*Fmt >= '0' && *Fmt <= '9') {
      width = width * 10 + (*Fmt - '0');
      Fmt++;
    }
    if (*Fmt == 's') {
      sp = NULL;
      if (ai < nargs)
        sp = args[ai](U8 *);
      ai++;
      if (sp == NULL)
        sp = "(null)";
      while (*sp) {
        if (Size > 0 && n < Size - 1)
          Buf[n] = *sp;
        n++;
        sp++;
      }
    } else if (*Fmt == 'd' || *Fmt == 'u' || *Fmt == 'x' || *Fmt == 'X' || *Fmt == 'l') {
      // %d %u %x %X and the 'l' length modifier. OSAL and cFE print status codes with %d and
      // %ld and they are NEGATIVE -- treating those as unsigned would print
      // 18446744073709551615 where NASA prints -1.
      islong = 0;
      if (*Fmt == 'l') {
        Fmt++;              // consume the length modifier
        if (*Fmt == 'l')
          Fmt++;            // %lld
        if (*Fmt != 'd' && *Fmt != 'u' && *Fmt != 'x' && *Fmt != 'X')
          Fmt--;            // not a conversion after all: let the default branch see it
        else
          islong = 1;
      }
      base = 10;
      upper = 0;
      if (*Fmt == 'x')
        base = 16;
      if (*Fmt == 'X') {
        base = 16;
        upper = 1;
      }
      sv = 0;
      if (ai < nargs)
        sv = args[ai];
      ai++;
      neg = 0;
      if (*Fmt == 'd' && sv < 0) {
        neg = 1;
        sv = -sv;
      }
      uv = sv;
      // A %x or %u of a value that arrived as a negative I64 prints the 32-bit pattern, which
      // is what C does for the (unsigned int) casts every cFS call site puts on these.
      // THE LENGTH MODIFIER DECIDES THE WIDTH. Masking unconditionally was wrong for %016llX,
      // which TA uses to print a 64-bit affinity mask: in a one-core configuration the mask fits
      // in 32 bits and the truncation is invisible, so this is the kind of thing a transcript
      // agrees with right up to the first machine that has more than four cores.
      if (*Fmt != 'd' && base == 16 && !islong)
        uv = uv & 0xFFFFFFFF;
      hexd = "0123456789abcdef";
      if (upper)
        hexd = "0123456789ABCDEF";
      ndig = 0;
      if (!uv)
        dig[ndig++] = '0';
      // `uv = uv / base`, NOT `uv /= base`, and the two are not the same here: measured, the
      // compound form emits a SIGNED divide for a U64, so %llu of a value above 2^63 printed 17
      // digits instead of 20 while the sibling `uv % base` on the same line was unsigned.
      // docs/HOLYC_STRUCT_LIMITS.md #11.
      while (uv > 0) {
        dig[ndig++] = hexd[uv % base];
        uv = uv / base;
      }
      // Zero- or space-padding to the field width, the minus sign counted inside it as C does.
      // THE SIGN'S POSITION DEPENDS ON THE FLAG, and getting that wrong is invisible until a
      // negative number meets a zero-padded width: C writes %06d of -42 as "-00042", with the
      // sign first and the zeros after it, while spaces go BEFORE the sign ("   -42"). An
      // earlier version here padded first in both cases and produced "000-42".
      if (neg && zeropad) {
        if (Size > 0 && n < Size - 1)
          Buf[n] = '-';
        n++;
      }
      i = ndig + neg;
      while (i < width) {
        if (Size > 0 && n < Size - 1) {
          if (zeropad)
            Buf[n] = '0';
          else
            Buf[n] = ' ';
        }
        n++;
        i++;
      }
      if (neg && !zeropad) {
        if (Size > 0 && n < Size - 1)
          Buf[n] = '-';
        n++;
      }
      while (ndig > 0) {
        ndig--;
        if (Size > 0 && n < Size - 1)
          Buf[n] = dig[ndig];
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

// Fixed arity with defaults, for the translated call sites that pass a known argument list --
// EIGHT slots, not five. The first version took five, and EVS_SendViaPorts formats SIX
// conversions -- "%s %u/%u/%s %u: %s" -- so the message text, the last one, was dropped and
// every port line in the differential transcript read "(null)" where NASA's read the event.
// Nothing warns: a HolyC default argument is a call-site expression, so a sixth argument to a
// five-parameter function is simply not passed, and `nargs = 5` then makes StrPrintNV stop
// short rather than read off the end. The arity here is a HARD CEILING on every format string
// in the port, so it is written down: raise it when a call site needs more.
I64 StrPrintN(U8 *Buf, I64 Size, U8 *Fmt, I64 a0=0, I64 a1=0, I64 a2=0, I64 a3=0, I64 a4=0,
              I64 a5=0, I64 a6=0, I64 a7=0)
{
  I64 args[8];
  args[0] = a0;
  args[1] = a1;
  args[2] = a2;
  args[3] = a3;
  args[4] = a4;
  args[5] = a5;
  args[6] = a6;
  args[7] = a7;
  return StrPrintNV(Buf, Size, Fmt, 8, args);
}
#endif
