// fmt.hc -- HolyC source formatter (gofmt-like). Host HolyFmtSrc (AST/CST emit in
// holyc_fmt.c) formats into slot MEM_HOST_SLOTS+0xC8; HcFmtFile (MEM_HOST_SLOTS+0xD8) rewrites a
// memfs .hc/.HH in place. Same engine as `holyc-riscv --fmt`.
// Rules: 2-space indent; tabs only inside asm{}; # at column 0; spaces around
// binary ops / after `,`; dense unary and `->`; space after if/for/while/switch;
// control `{` same line; function `{` next line.
// Editors: Vi :w / Edit ^O / Ed w auto-format via C or HolyC FileWrite hooks.
// Also: Fmt("file.hc"); FmtSrc(src) (host buffer pointer).
// Host hooks are once-indirect funptrs (no asm jalr trampoline).
I64 HcFmt(U8 *src)
{
  I64 (*fmt)(U8 *src);
  fmt = *(I64 *)MEM_HOST_SLOTS + 0xC0;
  if (!fmt)
    return -1;
  return fmt(src);
}

I64 HcFmtFile(U8 *name)
{
  I64 (*ff)(U8 *name);
  ff = *(I64 *)MEM_HOST_SLOTS + 0xD8;
  if (!ff)
    return -1;
  return ff(name);
}

U8 *FmtHostBuf()
{
  return *(I64 *)MEM_HOST_SLOTS + 0xC8;
}

I64 IsHcName(U8 *name)
{
  U8 *base, *p;
  I64 n;
  if (!name || !*name)
    return 0;
  base = name;
  p = name;
  while (*p) {
    if (*p == '/' || *p == '\\')
      base = p + 1;
    p++;
  }
  n = 0;
  p = base;
  while (*p) {
    n++;
    p++;
  }
  if (n < 3)
    return 0;
  p = base + n - 3;
  if (*p != '.')
    return 0;
  p++;
  if (!(*p == 'h' || *p == 'H'))
    return 0;
  p++;
  if (*p == 'c' || *p == 'C' || *p == 'h' || *p == 'H')
    return 1;
  return 0;
}
// FmtSrc -- FmtSrc(src)
// NAME
//   FmtSrc - format HolyC source (host HolyFmtSrc); returns host buffer pointer, or NULL.
U8 *FmtSrc(U8 *src)
{
  I64 n;
  if (!src)
    return 0;
  n = HcFmt(src);
  if (n < 0)
    return 0;
  return FmtHostBuf();
}

I64 FmtSrcLen(U8 *src)
{
  if (!src)
    return -1;
  return HcFmt(src);
}
// Fmt -- Fmt("file.hc")
// NAME
//   Fmt - format a memfs HolyC file in place
// SYNOPSIS
//   I64 Fmt(U8 *name);
// DESCRIPTION
//   Pretty-prints a .hc/.HH file using the host formatter (gofmt-style) and writes
//   it back if anything changed. Returns the new length, or -1 on failure. Editors
//   often call the quiet HcFmtFile helper; Fmt always prints a status line.
// EXAMPLES
//   Fmt("boot.hc");
//   Cat("boot.hc");
// SEE ALSO
//   FmtSrc  HcFmt  Ed  Vi  Cat
// BUGS
//   Only .hc/.HH names; missing file → -1.
I64 Fmt(U8 *name)
{
  U8 *src, *out;
  I64 n, olen, i, ch;
  if (!name) {
    "Fmt: missing name\n";
    return -1;
  }
  if (!IsHcName(name)) {
    "Fmt: not a .hc/.HH file: %s\n", name;
    return -1;
  }
  src = FileRead(name);
  if (!src) {
    "Fmt: no such file: %s\n", name;
    return -1;
  }
  olen = FileLen(name);
  n = HcFmt(src);
  if (n < 0) {
    "Fmt: failed %s\n", name;
    return -1;
  }
  out = FmtHostBuf();
  ch = 0;
  if (n != olen)
    ch = 1;
  else {
    for (i = 0; i < n; i++)
      if (src[i] != out[i]) {
        ch = 1;
        break;
      }
  }
  if (ch) {
    n = FileWrite(name, out, n);
    if (n < 0) {
      "Fmt: write failed %s\n", name;
      return -1;
    }
    "Fmt: %s (%d bytes, rewritten)\n", name, n;
  } else
    "Fmt: %s (%d bytes, already formatted)\n", name, n;
  return n;
}
// FmtSave -- FmtSave(name,data,len)
// NAME
//   FmtSave - FileWrite then quiet HcFmtFile for HolyC names; returns bytes written.
I64 FmtSave(U8 *name, U8 *data, I64 len)
{
  I64 n, f;
  if (!name || !data)
    return -1;
  if (len < 0)
    len = 0;
  n = FileWrite(name, data, len);
  if (n < 0)
    return n;
  if (IsHcName(name)) {
    f = HcFmtFile(name);
    if (f >= 0)
      return f;
  }
  return n;
}
