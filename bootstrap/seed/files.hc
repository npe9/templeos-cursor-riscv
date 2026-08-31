// files.hc -- TempleOS file utilities, in HolyC: Cat, Copy, Move, Rename, FileFind, FilesFind,
// Find (grep with wildcards), Activate (Enter-on-link), DirEd. Built on FileRead/FileWrite/Del.
// Cd/Pwd/DirMk/DirDel/IsDir and File* live in seed/fs.hc (HolyC arena at 0x85000000).
U8 FileAbsBuf[65];
// ToAbs -- ToAbs("name")
// NAME
//   ToAbs - absolute path under / if name is relative.
// SYNOPSIS
//   ToAbs("name")
// DESCRIPTION
//   absolute path under / if name is relative.
// INPUTS
//   "name" - string argument
// OUTPUTS
//   absolute path under / if name is relative.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U8 *ToAbs(U8 *nm)
{
  I64 i = 0;
  if (nm[0] == '/')
    return nm;
  FileAbsBuf[0] = '/';
  while (nm[i] && i < 63) {
    FileAbsBuf[i + 1] = nm[i];
    i++;
  }
  FileAbsBuf[i + 1] = 0;
  return FileAbsBuf;
}
// Cat -- Cat("file")
// NAME
//   Cat - print an in-memory file
// SYNOPSIS
//   U0 Cat(U8 *name);
// DESCRIPTION
//   Reads name from the memfs and prints its bytes to the UART (TempleOS Type/Cat style
//   for text). Ensures a trailing newline if the file does not end with one. HolyC in
//   files.hc -- no longer a C RuntimeRegister.
// INPUTS
//   name - memfs path
// OUTPUTS
//   none (file text on UART); prints an error line if missing
// BUGS
//   Binary files will dump raw bytes. Path resolution follows FileRead (cwd-relative).
U0 Cat(U8 *name)
{
  U8 *d;
  I64 n, i;
  d = FileRead(name);
  n = FileLen(name);
  if (!d || n < 0) {
    "Cat: no such file: %s\n", name;
    return;
  }
  for (i = 0; i < n; i++)
    PutCh(d[i]);
  if (n && d[n - 1] != '\n')
    PutCh('\n');
}
// Copy -- Copy("from","to")
// NAME
//   Copy - copy an in-memory file.
// SYNOPSIS
//   Copy("from","to")
// DESCRIPTION
//   copy an in-memory file.
// INPUTS
//   "from" - string argument
//   "to" - string argument
// OUTPUTS
//   copy an in-memory file.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 Copy(U8 *from, U8 *to)
{
  U8 *d;
  I64 n;
  d = FileRead(from);
  n = FileLen(from);
  if (!d || n < 0) {
    "Copy: no such file: %s\n", from;
    return -1;
  }
  FileWrite(to, d, n);
  "copied %s -> %s (%d bytes)\n", from, to, n;
  return n;
}
// Move -- Move("from","to")
// NAME
//   Move - copy then Del.
// SYNOPSIS
//   Move("from","to")
// DESCRIPTION
//   copy then Del.
// INPUTS
//   "from" - string argument
//   "to" - string argument
// OUTPUTS
//   copy then Del.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 Move(U8 *from, U8 *to)
{
  I64 n = Copy(from, to);
  if (n >= 0)
    Del(from);
  return n;
}
// Rename -- Rename("from","to")
// NAME
//   Rename - alias of Move.
// SYNOPSIS
//   Rename("from","to")
// DESCRIPTION
//   alias of Move.
// INPUTS
//   "from" - string argument
//   "to" - string argument
// OUTPUTS
//   alias of Move.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 Rename(U8 *from, U8 *to)
{
  return Move(from, to);
}
// FileFind -- FileFind("name")
// NAME
//   FileFind - print whether name exists.
// SYNOPSIS
//   FileFind("name")
// DESCRIPTION
//   print whether name exists.
// INPUTS
//   "name" - string argument
// OUTPUTS
//   print whether name exists.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 FileFind(U8 *name)
{
  I64 n = FileLen(name);
  if (n >= 0) {
    "%s (%d bytes)\n", name, n;
    return 1;
  }
  "not found: %s\n", name;
  return 0;
}
// "*"=all, "*.hc"=suffix, "ua*"=prefix, else exact.
// WildMatch -- WildMatch(s,p)
// NAME
//   WildMatch - simple * wildcard match.
// SYNOPSIS
//   WildMatch(s,p)
// DESCRIPTION
//   simple * wildcard match.
// INPUTS
//   s - argument
//   p - argument
// OUTPUTS
//   simple * wildcard match.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 WildMatch(U8 *s, U8 *p)
{
  I64 ls = 0, lp = 0, i;
  if (p[0] == '*' && p[1] == 0)
    return 1;
  while (s[ls])
    ls++;
  while (p[lp])
    lp++;
  if (p[0] == '*') {
    if (lp - 1 > ls)
      return 0;
    for (i = 0; i < lp - 1; i++)
      if (s[ls - lp + 1 + i] != p[1 + i])
        return 0;
    return 1;
  }
  if (p[lp - 1] == '*') {
    for (i = 0; i < lp - 1; i++)
      if (s[i] != p[i])
        return 0;
    return 1;
  }
  if (ls != lp)
    return 0;
  for (i = 0; i < ls; i++)
    if (s[i] != p[i])
      return 0;
  return 1;
}
// InCwd -- InCwd(nm)
// NAME
//   InCwd - nonzero if nm is under cwd.
// SYNOPSIS
//   InCwd(nm)
// DESCRIPTION
//   nonzero if nm is under cwd.
// INPUTS
//   nm - argument
// OUTPUTS
//   nonzero if nm is under cwd.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
I64 InCwd(U8 *nm)
{
  U8 *cwd;
  I64 cl = 0, k = 0;
  cwd = CwdStr();
  while (cwd[cl])
    cl++;
  while (k < cl && nm[k] == cwd[k])
    k++;
  return k == cl;
}
// Find("needle") / Find("needle", "*.hc") -- grep matching files under cwd, print file:line.
// FindIn -- FindIn(nm,needle)
// NAME
//   FindIn - grep needle in one file.
// SYNOPSIS
//   FindIn(nm,needle)
// DESCRIPTION
//   grep needle in one file.
// INPUTS
//   nm - argument
//   needle - argument
// OUTPUTS
//   grep needle in one file.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 FindIn(U8 *nm, U8 *needle)
{
  U8 *d;
  I64 j, k, line;
  d = FileRead(ToAbs(nm));
  if (!d)
    return;
  line = 1;
  j = 0;
  while (d[j]) {
    k = 0;
    while (needle[k] && d[j + k] == needle[k])
      k++;
    if (!needle[k]) {
      "%s:%d\n", nm, line;
      while (d[j] && d[j] != 10)
        j++;
      if (d[j]) {
        j++;
        line++;
      }
      continue;
    }
    if (d[j] == 10)
      line++;
    j++;
  }
}
// Find -- Find(needle,pat)
// NAME
//   Find - grep needle in files matching pat under cwd.
// SYNOPSIS
//   Find(needle,pat)
// DESCRIPTION
//   grep needle in files matching pat under cwd.
// INPUTS
//   needle - argument
//   pat - argument
// OUTPUTS
//   grep needle in files matching pat under cwd.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 Find(U8 *needle, U8 *pat = "*")
{
  I64 i, n;
  U8 *nm;
  n = FileCount();
  for (i = 0; i < n; i++) {
    nm = FileName(i);
    if (!nm || !InCwd(nm))
      continue;
    if (!WildMatch(nm, pat))
      continue;
    FindIn(nm, needle);
  }
}
// FilesFind -- FilesFind(pat)
// NAME
//   FilesFind - list files matching pat under cwd.
// SYNOPSIS
//   FilesFind(pat)
// DESCRIPTION
//   list files matching pat under cwd.
// INPUTS
//   pat - argument
// OUTPUTS
//   list files matching pat under cwd.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 FilesFind(U8 *pat = "*")
{
  I64 i, n, cl, hits;
  U8 *nm, *rest, *cwd;
  cwd = CwdStr();
  cl = 0;
  while (cwd[cl])
    cl++;
  n = FileCount();
  hits = 0;
  for (i = 0; i < n; i++) {
    nm = FileName(i);
    if (!nm || !InCwd(nm))
      continue;
    rest = nm + cl;
    if (rest[0] == '.')
      continue;
    if (!WildMatch(nm, pat) && !WildMatch(rest, pat))
      continue;
    "%s\n", nm;
    hits++;
  }
  if (!hits)
    "FilesFind: none\n";
}
// Activate("Demo") / Activate("uart.hc") -- the DolDoc Enter action: Cd into a directory,
// open a file via editor, or Src a symbol. Editors nest another session (Vi/EditHoly stack)
// for file/symbol jumps so :q / ^X returns to the prior buffer.
// Activate -- Activate(name)
// NAME
//   Activate - DolDoc Enter: Cd, editor(open), or Src.
// SYNOPSIS
//   Activate(name)
// DESCRIPTION
//   DolDoc Enter: Cd, editor(open), or Src.
// INPUTS
//   name - argument
// OUTPUTS
//   DolDoc Enter: Cd, editor(open), or Src.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 Activate(U8 *name)
{
  U8 w[64];
  I64 k = LinkKind(name, w);
  if (k == 1)
    LinkCd(w);
  else if (k == 2)
    editor(w);
  else if (w[0])
    Src(w);
  else {
    "Activate: nothing under cursor\n";
  }
}
// DirEd -- DirEd()
// NAME
//   DirEd - DirWrite + editor(.dirlist).
// SYNOPSIS
//   DirEd()
// DESCRIPTION
//   DirWrite + editor(.dirlist).
// INPUTS
//   none
// OUTPUTS
//   DirWrite + editor(.dirlist).
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 DirEd()
{
  DirWrite();
  editor(".dirlist");
}
