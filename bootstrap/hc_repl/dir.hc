// dir.hc -- cwd-aware Dir() for the AOT HolyC REPL.
// At /: subdirs as "Home/" (from Home/.dir). Inside a dir: files only. Hides dotfiles.
// Split helpers keep AOT frames small (a fat Dir() spilled and hung on cwd walks).
// Editor / Src live in ide_src.hc (G3) after seed ed/edit/vim.
I64 DirSlash(U8 *s)
{
  I64 n;
  n = 0;
  while (s[n] && s[n] != '/')
    n++;
  return n;
}

I64 DirIsDotDir(U8 *s)
{
  if (*s != '.')
    return 0;
  if (s[1] != 'd' || s[2] != 'i' || s[3] != 'r')
    return 0;
  if (s[4])
    return 0;
  return 1;
}

U0 DirOne(I64 i)
{
  U8 *nm, *cwd, *p, *q;
  I64 sl, k;
  nm = FileName(i);
  if (!nm)
    return;
  cwd = FsCwd();
  if (!cwd)
    cwd = "";
  p = nm;
  q = cwd;
  while (*q) {
    if (*p != *q)
      return;
    p++;
    q++;
  }
  if (*p == '.')
    return;
  sl = DirSlash(p);
  if (p[sl] == '/') {
    if (DirIsDotDir(p + sl + 1)) {
      UartStr("  ");
      k = 0;
      while (k < sl) {
        PutCh(p[k]);
        k++;
      }
      UartStr("/\n");
    }
    return;
  }
  Print("  %s  (%d)\n", p, FileSize(i));
}

U0 Dir()
{
  I64 i, n;
  U8 *cwd;
  n = FileCount();
  cwd = FsCwd();
  if (!cwd)
    cwd = "";
  Print("Dir: %d files\n", n);
  UartStr(" /");
  UartStr(cwd);
  PutCh('\n');
  i = 0;
  while (i < n) {
    DirOne(i);
    i++;
  }
}

U0 Ls()
{
  Dir;
}
// Cat / Copy / DumpFile live in seed/files.hc (AOT-included from repl.hc).
I64 LinkKind(U8 *name, U8 *out)
{
  I64 n = 0;
  if (!name) {
    out[0] = 0;
    return 0;
  }
  while (name[n] && n < 63) {
    out[n] = name[n];
    n++;
  }
  out[n] = 0;
  if (n && out[n - 1] == 47) {
    n--;
    out[n] = 0;
  }
  if (!out[0])
    return 0;
  if (out[0] == '.' && !out[1])
    return 0;
  if (out[0] == '.' && out[1] == '.' && !out[2])
    return 1;
  if (IsDir(out))
    return 1;
  if (FileLen(out) >= 0)
    return 2;
  return 0;
}

U0 LinkCd(U8 *name)
{
  Cd(name);
}

U0 DirWrite()
{
}
