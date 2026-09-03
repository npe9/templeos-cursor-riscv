// ide_bridge.hc -- G3 glue so seed ed/edit/vim AOT into repl-holyc.
// Man/SrcFile/SymFile: man lane (man_sym.hc + seed/man.hc). Do not redefine.
// Tab/asm{}: seed asm_complete.hc + complete.hc (G5) — include those before term/ed;
// do not stub CompTab / CompAsm* / CompCx here (duplicates).
// Include after uart + str (+ man if present); before term.hc / ed / edit / vim.
U8 JumpIdent[64];
U8 JumpFile[64];
I64 HcRdTime()
{
  // QEMU virt CLINT mtime (MemMapSelected MEM_MTIME) — TermProbe timeout.
  return *(I64 *)0x0200BFF8;
}

U0 WordAt(U8 *line, I64 col, U8 *out)
{
  I64 i = col, j = 0;
  if (!out)
    return;
  out[0] = 0;
  if (!line)
    return;
  if (i < 0)
    i = 0;
  while (i > 0 && line[i] && line[i] != ' ' && line[i] != 0x09)
    i--;
  if (line[i] == ' ' || line[i] == 0x09)
    i++;
  while (line[i] == ' ' || line[i] == 0x09)
    i++;
  while (line[i] && line[i] != ' ' && line[i] != 0x09 && j < 63) {
    out[j] = line[i];
    j++;
    i++;
  }
  out[j] = 0;
}

I64 IdentChar(I64 c)
{
  if (c >= 'a' && c <= 'z')
    return 1;
  if (c >= 'A' && c <= 'Z')
    return 1;
  if (c >= '0' && c <= '9')
    return 1;
  if (c == '_')
    return 1;
  return 0;
}

U0 WordIdent(U8 *line, I64 col, U8 *out)
{
  I64 i = col, j = 0;
  out[0] = 0;
  if (!line)
    return;
  if (i < 0)
    i = 0;
  if (i > 127)
    i = 127;
  if (IdentChar(line[i])) {
    while (i > 0 && IdentChar(line[i - 1]))
      i--;
  } else {
    while (i < 128 && line[i] && !IdentChar(line[i]))
      i++;
    if (i >= 128 || !IdentChar(line[i]))
      return;
  }
  while (i < 128 && IdentChar(line[i]) && j < 63) {
    out[j] = line[i];
    j++;
    i++;
  }
  out[j] = 0;
}

I64 IdentAt(U8 *line, U8 *name)
{
  I64 i, j, start;
  start = 0;
  while (start < 128 && line[start]) {
    i = start;
    j = 0;
    while (i < 128 && name[j] && line[i] == name[j]) {
      i++;
      j++;
    }
    if (!name[j] && j > 0) {
      if (i >= 128 || !IdentChar(line[i])) {
        if (start == 0 || !IdentChar(line[start - 1]))
          return start;
      }
    }
    start++;
  }
  return -1;
}

I64 DefAt(U8 *line, U8 *name)
{
  I64 i, k, j;
  if (!line || !name)
    return -1;
  j = 0;
  while (line[j] == ' ' || line[j] == 9)
    j++;
  if (line[j] == '/' && line[j + 1] == '/')
    return -1;
  i = IdentAt(line, name);
  if (i < 0)
    return -1;
  k = i;
  while (k < 128 && IdentChar(line[k]))
    k++;
  while (k < 128 && (line[k] == ' ' || line[k] == 9))
    k++;
  if (line[k] == '(')
    return i;
  return -1;
}

U0 SrcJumpSet(U8 *name)
{
  I64 i;
  JumpIdent[0] = 0;
  if (!name || !*name)
    return;
  i = 0;
  while (name[i] && i < 63) {
    JumpIdent[i] = name[i];
    i++;
  }
  JumpIdent[i] = 0;
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

I64 FmtSave(U8 *name, U8 *data, I64 len)
{
  if (!name || !data)
    return -1;
  if (len < 0)
    len = 0;
  return FileWrite(name, data, len);
}
