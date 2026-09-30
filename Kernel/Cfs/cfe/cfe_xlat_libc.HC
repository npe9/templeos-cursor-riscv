/************************************************************************
 * NASA Docket No. GSC-19,200-1, and identified as "cFS Draco"
 *
 * Copyright (c) 2023 United States Government as represented by the
 * Administrator of the National Aeronautics and Space Administration.
 * All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License. You may obtain
 * a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 ************************************************************************/

// Stand-ins for the <string.h> routines the translated cFE sources call.
//
// NOT a translation of anything -- cFE calls the C library, and this is what the C library owes
// it. The kernel has MemSet in Kernel/KUtilsRV.HC, but the translated units are deliberately
// standalone so that the differential oracle tests the translation and nothing else. The names
// are the C ones so the call sites can stay character-for-character what NASA wrote.
#ifndef CFE_XLAT_LIBC_HC
#define CFE_XLAT_LIBC_HC
U0 memset(U8 *dst, I64 c, I64 n)
{
  while (n > 0) {
    *dst++ = c;
    n--;
  }
}

// C's strncpy, including the part people forget: it pads the destination with NUL to n and does
// NOT terminate when the source is longer than n. OSAL relies on both -- it strncpy's into a
// fixed buffer and then writes the terminator itself.
U8 *strncpy(U8 *dst, U8 *src, I64 n)
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

I64 strcmp(U8 *a, U8 *b)
{
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return *a - *b;
}

U0 memcpy(U8 *dst, U8 *src, I64 n)
{
  while (n > 0) {
    *dst++ = *src++;
    n--;
  }
}
// A MINIMAL snprintf, covering exactly the two conversions cFE's translated call sites use:
// %s and %u. Written so that the call sites stay character-for-character what NASA wrote,
// which is the whole reason it exists -- the alternative was hand-building those strings and
// calling it a translation.
//
// HolyC has variadics, but a fixed arity with defaults is enough here and far easier to read:
// the widest call in the translated sources passes five arguments. Each is an I64 and is
// interpreted as a pointer or a number according to the conversion it meets, exactly as C's
// promotion rules leave them on the stack.
//
// Truncation follows C: at most Size-1 characters plus a NUL, and nothing written at all when
// Size is 0. The return value is C's too -- the length that WOULD have been written -- which is
// why it can exceed Size.
I64 snprintf(U8 *Buf, I64 Size, U8 *Fmt, I64 a0=0, I64 a1=0, I64 a2=0, I64 a3=0, I64 a4=0)
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
