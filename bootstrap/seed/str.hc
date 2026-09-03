// str.hc -- string / mem / small integer helpers in HolyC. Boot-loaded; redefines any
// leftover C stubs. Uses pointer walks (not s[i] indexing) to avoid known frame/index
// codegen hazards under a heavy boot. Src("StrLen") opens this file.
// StrLen -- StrLen(s)
// NAME
//   StrLen - length of a NUL-terminated string.
// SYNOPSIS
//   StrLen(s)
// DESCRIPTION
//   length of a NUL-terminated string.
// INPUTS
//   s - argument
// OUTPUTS
//   length of a NUL-terminated string.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 StrLen(U8 *s)
{
  I64 n;
  if (!s)
    return 0;
  n = 0;
  while (*s) {
    n++;
    s++;
  }
  return n;
}
// StrCpy -- StrCpy(dst,src)
// NAME
//   StrCpy - copy src onto dst (including NUL); returns dst.
// SYNOPSIS
//   StrCpy(dst,src)
// DESCRIPTION
//   copy src onto dst (including NUL); returns dst.
// INPUTS
//   dst - argument
//   src - argument
// OUTPUTS
//   copy src onto dst (including NUL); returns dst.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U8 *StrCpy(U8 *dst, U8 *src)
{
  U8 *o;
  if (!dst)
    return 0;
  o = dst;
  if (!src) {
    *dst = 0;
    return o;
  }
  while (*src) {
    *dst = *src;
    dst++;
    src++;
  }
  *dst = 0;
  return o;
}
// StrCmp -- StrCmp(a,b)
// NAME
//   StrCmp - strcmp; <0 / 0 / >0.
// SYNOPSIS
//   StrCmp(a,b)
// DESCRIPTION
//   strcmp; <0 / 0 / >0.
// INPUTS
//   a - argument
//   b - argument
// OUTPUTS
//   strcmp; <0 / 0 / >0.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 StrCmp(U8 *a, U8 *b)
{
  if (!a)
    a = "";
  if (!b)
    b = "";
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return *a - *b;
}
// StrCat -- StrCat(dst,src)
// NAME
//   StrCat - append src onto dst; returns dst.
// SYNOPSIS
//   StrCat(dst,src)
// DESCRIPTION
//   append src onto dst; returns dst.
// INPUTS
//   dst - argument
//   src - argument
// OUTPUTS
//   append src onto dst; returns dst.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U8 *StrCat(U8 *dst, U8 *src)
{
  U8 *o;
  if (!dst)
    return 0;
  o = dst;
  while (*dst)
    dst++;
  if (!src)
    return o;
  while (*src) {
    *dst = *src;
    dst++;
    src++;
  }
  *dst = 0;
  return o;
}
// StrNew -- StrNew(s)
// NAME
//   StrNew - heap copy of s (via MAlloc).
// SYNOPSIS
//   StrNew(s)
// DESCRIPTION
//   heap copy of s (via MAlloc).
// INPUTS
//   s - argument
// OUTPUTS
//   heap copy of s (via MAlloc).
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U8 *StrNew(U8 *s)
{
  I64 n;
  U8 *d;
  if (!s)
    s = "";
  n = StrLen(s);
  d = MAlloc(n + 1);
  if (!d)
    return 0;
  StrCpy(d, s);
  return d;
}
// StrNCmp -- StrNCmp(a,b,n)
// NAME
//   StrNCmp - compare at most n chars.
// SYNOPSIS
//   StrNCmp(a,b,n)
// DESCRIPTION
//   compare at most n chars.
// INPUTS
//   a - argument
//   b - argument
//   n - argument
// OUTPUTS
//   compare at most n chars.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 StrNCmp(U8 *a, U8 *b, I64 n)
{
  I64 i;
  if (!a)
    a = "";
  if (!b)
    b = "";
  for (i = 0; i < n; i++) {
    if (a[i] != b[i])
      return a[i] - b[i];
    if (!a[i])
      return 0;
  }
  return 0;
}
// StrNICmp -- StrNICmp(a,b,n)
// NAME
//   StrNICmp - case-insensitive compare of at most n chars.
// SYNOPSIS
//   StrNICmp(a,b,n)
// DESCRIPTION
//   case-insensitive compare of at most n chars.
// INPUTS
//   a - argument
//   b - argument
//   n - argument
// OUTPUTS
//   case-insensitive compare of at most n chars.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 StrNICmp(U8 *a, U8 *b, I64 n)
{
  I64 i, ca, cb;
  if (!a)
    a = "";
  if (!b)
    b = "";
  for (i = 0; i < n; i++) {
    ca = a[i];
    cb = b[i];
    if (ca >= 'A' && ca <= 'Z')
      ca += 32;
    if (cb >= 'A' && cb <= 'Z')
      cb += 32;
    if (ca != cb)
      return ca - cb;
    if (!a[i])
      return 0;
  }
  return 0;
}
// StrICmp -- StrICmp(a,b)
// NAME
//   StrICmp - case-insensitive strcmp.
// SYNOPSIS
//   StrICmp(a,b)
// DESCRIPTION
//   case-insensitive strcmp.
// INPUTS
//   a - argument
//   b - argument
// OUTPUTS
//   case-insensitive strcmp.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 StrICmp(U8 *a, U8 *b)
{
  I64 ca, cb;
  if (!a)
    a = "";
  if (!b)
    b = "";
  while (*a && *b) {
    ca = *a;
    cb = *b;
    if (ca >= 'A' && ca <= 'Z')
      ca += 32;
    if (cb >= 'A' && cb <= 'Z')
      cb += 32;
    if (ca != cb)
      return ca - cb;
    a++;
    b++;
  }
  ca = *a;
  cb = *b;
  if (ca >= 'A' && ca <= 'Z')
    ca += 32;
  if (cb >= 'A' && cb <= 'Z')
    cb += 32;
  return ca - cb;
}
// StrMatch -- StrMatch(needle, hay, flags)
// NAME
//   StrMatch - find needle in hay (case-sensitive); returns ptr or NULL
// SYNOPSIS
//   U8 *StrMatch(U8 *needle, U8 *hay, I64 flags=0);
// DESCRIPTION
//   TempleOS StrMatch: first occurrence of needle in hay, or NULL. flags unused.
// SEE ALSO
//   StrIMatch  StrICmp  Funs
U8 *StrMatch(U8 *needle, U8 *hay, I64 flags = 0)
{
  U8 *h, *a, *b;
  flags = flags;
  if (!needle || !hay)
    return 0;
  if (!*needle)
    return hay;
  for (h = hay; *h; h++) {
    a = needle;
    b = h;
    while (*a && *a == *b) {
      a++;
      b++;
    }
    if (!*a)
      return h;
  }
  return 0;
}
// StrIMatch -- StrIMatch(needle, hay, flags)
// NAME
//   StrIMatch - find needle in hay (ASCII case-insensitive); returns ptr or NULL
// SYNOPSIS
//   U8 *StrIMatch(U8 *needle, U8 *hay, I64 flags=0);
// DESCRIPTION
//   Like StrMatch but folds A-Z before compare. Used by Funs / FunPick filter.
// SEE ALSO
//   StrMatch  StrICmp  Funs
U8 *StrIMatch(U8 *needle, U8 *hay, I64 flags = 0)
{
  U8 *h, *a, *b;
  I64 ca, cb;
  flags = flags;
  if (!needle || !hay)
    return 0;
  if (!*needle)
    return hay;
  for (h = hay; *h; h++) {
    a = needle;
    b = h;
    while (*a) {
      ca = *a;
      cb = *b;
      if (ca >= 'A' && ca <= 'Z')
        ca += 32;
      if (cb >= 'A' && cb <= 'Z')
        cb += 32;
      if (ca != cb)
        break;
      a++;
      b++;
    }
    if (!*a)
      return h;
  }
  return 0;
}
// MemCpy -- MemCpy(dst,src,n)
// NAME
//   MemCpy - copy n bytes from src to dst.
// SYNOPSIS
//   MemCpy(dst,src,n)
// DESCRIPTION
//   copy n bytes from src to dst.
// INPUTS
//   dst - argument
//   src - argument
//   n - argument
// OUTPUTS
//   copy n bytes from src to dst.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U8 *MemCpy(U8 *dst, U8 *src, I64 n)
{
  U8 *o;
  I64 i;
  o = dst;
  for (i = 0; i < n; i++) {
    *dst = *src;
    dst++;
    src++;
  }
  return o;
}
// MemSet -- MemSet(dst,v,n)
// NAME
//   MemSet - set n bytes of dst to v.
// SYNOPSIS
//   MemSet(dst,v,n)
// DESCRIPTION
//   set n bytes of dst to v.
// INPUTS
//   dst - argument
//   v - argument
//   n - argument
// OUTPUTS
//   set n bytes of dst to v.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U8 *MemSet(U8 *dst, I64 v, I64 n)
{
  U8 *o;
  I64 i;
  o = dst;
  for (i = 0; i < n; i++) {
    *dst = v;
    dst++;
  }
  return o;
}
// MemCmp -- MemCmp(a,b,n)
// NAME
//   MemCmp - compare n bytes.
// SYNOPSIS
//   MemCmp(a,b,n)
// DESCRIPTION
//   compare n bytes.
// INPUTS
//   a - argument
//   b - argument
//   n - argument
// OUTPUTS
//   compare n bytes.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 MemCmp(U8 *a, U8 *b, I64 n)
{
  I64 i;
  for (i = 0; i < n; i++) {
    if (*a != *b)
      return *a - *b;
    a++;
    b++;
  }
  return 0;
}
// MemSetI64 -- MemSetI64(dst,v,n)
// NAME
//   MemSetI64 - set n I64s.
// SYNOPSIS
//   MemSetI64(dst,v,n)
// DESCRIPTION
//   set n I64s.
// INPUTS
//   dst - argument
//   v - argument
//   n - argument
// OUTPUTS
//   set n I64s.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 *MemSetI64(I64 *dst, I64 v, I64 n)
{
  I64 i;
  for (i = 0; i < n; i++)
    dst[i] = v;
  return dst;
}
// AbsI64 -- AbsI64(x)
// NAME
//   AbsI64 - |x|.
// SYNOPSIS
//   AbsI64(x)
// DESCRIPTION
//   |x|.
// INPUTS
//   x - argument
// OUTPUTS
//   |x|.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 AbsI64(I64 x)
{
  if (x < 0)
    return -x;
  return x;
}
// MaxI64 -- MaxI64(a,b)
// NAME
//   MaxI64 - maximum of a,b.
// SYNOPSIS
//   MaxI64(a,b)
// DESCRIPTION
//   maximum of a,b.
// INPUTS
//   a - argument
//   b - argument
// OUTPUTS
//   maximum of a,b.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 MaxI64(I64 a, I64 b)
{
  if (a > b)
    return a;
  return b;
}
// MinI64 -- MinI64(a,b)
// NAME
//   MinI64 - minimum of a,b.
// SYNOPSIS
//   MinI64(a,b)
// DESCRIPTION
//   minimum of a,b.
// INPUTS
//   a - argument
//   b - argument
// OUTPUTS
//   minimum of a,b.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 MinI64(I64 a, I64 b)
{
  if (a < b)
    return a;
  return b;
}
// ToUpper -- ToUpper(c)
// NAME
//   ToUpper - uppercase one ASCII char.
// SYNOPSIS
//   ToUpper(c)
// DESCRIPTION
//   uppercase one ASCII char.
// INPUTS
//   c - argument
// OUTPUTS
//   uppercase one ASCII char.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 ToUpper(I64 c)
{
  if (c >= 'a' && c <= 'z')
    return c - 32;
  return c;
}
// ToLower -- ToLower(c)
// NAME
//   ToLower - lowercase one ASCII char.
// SYNOPSIS
//   ToLower(c)
// DESCRIPTION
//   lowercase one ASCII char.
// INPUTS
//   c - argument
// OUTPUTS
//   lowercase one ASCII char.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 ToLower(I64 c)
{
  if (c >= 'A' && c <= 'Z')
    return c + 32;
  return c;
}
// SqrI64 -- SqrI64(x)
// NAME
//   SqrI64 - x*x.
// SYNOPSIS
//   SqrI64(x)
// DESCRIPTION
//   x*x.
// INPUTS
//   x - argument
// OUTPUTS
//   x*x.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 SqrI64(I64 x)
{
  return x *x;
}
// ClampI64 -- ClampI64(x,lo,hi)
// NAME
//   ClampI64 - clamp x to [lo,hi].
// SYNOPSIS
//   ClampI64(x,lo,hi)
// DESCRIPTION
//   clamp x to [lo,hi].
// INPUTS
//   x - argument
//   lo - argument
//   hi - argument
// OUTPUTS
//   clamp x to [lo,hi].
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 ClampI64(I64 x, I64 lo, I64 hi)
{
  if (x < lo)
    return lo;
  if (x > hi)
    return hi;
  return x;
}
// Str2I64 -- Str2I64(st,radix=10,_end_ptr=NULL)
// NAME
//   Str2I64 - string to I64 (TempleOS Kernel/StrScan.HC)
// SYNOPSIS
//   I64 Str2I64(U8 *st,I64 radix=10,U8 **_end_ptr=NULL);
// DESCRIPTION
//   Parse a signed integer from st. Skips leading white space (space/tab/CR/LF).
//   Accepts leading + / - (each - toggles sign). With a leading 0, optional
//   radix override letters: 0b (2), 0d (10), 0x (16) — same rules as TempleOS
//   Str2I64 (similar to strtoul). Digits beyond the radix stop the scan; if
//   _end_ptr is set it receives the address of the first unparsed char.
// INPUTS
//   st - NUL-terminated string (NULL -> 0)
//   radix - base 2..36 (default 10); invalid radix -> 0
//   _end_ptr - optional out pointer to end of parse
// OUTPUTS
//   Parsed I64, or 0 on NULL/invalid radix
// BUGS
//   Whitespace is space/tab/CR/LF only (no full char_bmp_white_space). No 0o
//   octal prefix in stock TempleOS either (comment mentions it; code does not).
I64 Str2I64(U8 *st, I64 radix = 10, U8 **_end_ptr = NULL)
{
  Bool neg = FALSE;
  I64 ch, res = 0;
  if (!st || !(2 <= radix <= 36)) {
    if (_end_ptr)
      *_end_ptr = st;
    return 0;
  }
  while (*st == ' ' || *st == '\t' || *st == '\r' || *st == '\n')
    st++;
  while (TRUE)
    switch (*st) {
      case '-' :
      st++;
      neg = !neg;
      break;
      case '+' :
      st++;
      break;
      case '0' :
      st++;
      ch = ToUpper (*st);
      if (ch >= 'B' && (radix <= 10 || ch > 'A' + radix - 11))
        switch (ch) {
          case 'B' :
          radix = 2;
          st++;
          break;
          case 'D' :
          radix = 10;
          st++;
          break;
          case 'X' :
          radix = 16;
          st++;
          break;
        }
      default:
      goto ai_cont;
    }
  ai_cont:
  while (ch = ToUpper (*st++)) {
    if (radix > 10) {
      if ('0' <= ch <= '9')
        res = res *radix + ch - '0';
      else if ('A' <= ch <= 'A' + radix - 11)
        res = res *radix + ch - 'A' + 10;
      else
        break;
    } else if ('0' <= ch <= '0' + radix - 1)
      res = res *radix + ch - '0';
    else
      break;
  }
  if (_end_ptr)
    *_end_ptr = st - 1;
  if (neg)
    return -res;
  else
    return res;
}
// Atoi -- Atoi(st)
// NAME
//   Atoi - string to I64 (radix 10 + TempleOS 0b/0d/0x prefixes)
// SYNOPSIS
//   I64 Atoi(U8 *st);
// DESCRIPTION
//   Convenience wrapper: Str2I64(st) with default radix 10. TempleOS's real
//   converter is Str2I64; there is no separate Kernel Atoi. Same sign, white
//   space, and 0x/0b/0d prefix behavior as Str2I64("...",10).
// INPUTS
//   st - NUL-terminated decimal (or 0x/0b/0d) string
// OUTPUTS
//   Parsed I64
// BUGS
//   Name is C-flavored; prefer Str2I64 when you need radix or _end_ptr.
I64 Atoi(U8 *st)
{
  return Str2I64(st);
}
