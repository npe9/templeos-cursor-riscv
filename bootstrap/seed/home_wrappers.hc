// home_wrappers.hc -- the stock ~/HomeWrappers command line (F / R / FD / RD) for the UART
// memfs. Stock (tos/HomeWrappers.HC) hands Adam Find a file mask: "/*" is the whole disk and
// "*" is the current directory. Seed Find (files.hc) is always cwd-scoped and memfs names carry
// no leading '/', so the whole-tree walk here goes over FileName() directly instead of building
// a "/*" mask. Needles are plain substrings -- stock fu_flags (+l/-i/regex) are not implemented.
// HomeIsDot -- HomeIsDot(nm)
// NAME
//   HomeIsDot - nonzero if the last path component starts with '.'
// SYNOPSIS
//   I64 HomeIsDot(U8 *nm);
// DESCRIPTION
//   Filters memfs bookkeeping entries (".dir" markers, ".dirlist") out of the
//   whole-tree F/R walk the same way seed Find skips them under cwd.
// SEE ALSO
//   F  R  Find
I64 HomeIsDot(U8 *nm)
{
  I64 i, last;
  last = 0;
  i = 0;
  while (nm[i]) {
    if (nm[i] == '/')
      last = i + 1;
    i++;
  }
  return nm[last] == '.';
}
// HomeGrepFile -- HomeGrepFile(nm,needle)
// NAME
//   HomeGrepFile - print nm:line for each line holding needle; return hit count
// SYNOPSIS
//   I64 HomeGrepFile(U8 *nm, U8 *needle);
// DESCRIPTION
//   Same output shape as seed FindIn, but counts hits so F/FD can return an
//   I64 like the stock wrappers. One hit per line (the scan resumes at the
//   next newline).
// SEE ALSO
//   FindIn  F  FD
I64 HomeGrepFile(U8 *nm, U8 *needle)
{
  U8 *d;
  I64 j, k, line, hits;
  d = FileRead(ToAbs(nm));
  if (!d)
    return 0;
  hits = 0;
  line = 1;
  j = 0;
  while (d[j]) {
    k = 0;
    while (needle[k] && d[j + k] == needle[k])
      k++;
    if (!needle[k]) {
      "%s:%d\n", nm, line;
      hits++;
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
  return hits;
}
// HomeReplFile -- HomeReplFile(nm,needle,rep)
// NAME
//   HomeReplFile - substitute every needle in one memfs file
// SYNOPSIS
//   I64 HomeReplFile(U8 *nm, U8 *needle, U8 *rep);
// DESCRIPTION
//   Rebuilds the file into a MAlloc'd buffer and FileWrite()s it back when at
//   least one hit lands, so the edit shows up in the fs journal (FsChanges /
//   DumpChanges). Output is capped at MEMFS_CAP-1 like FileWrite.
// SEE ALSO
//   R  RD  FileWrite  FsChanges
I64 HomeReplFile(U8 *nm, U8 *needle, U8 *rep)
{
  U8 *d, *out;
  I64 len, nl, rl, i, o, k, hits, cap;
  d = FileRead(ToAbs(nm));
  len = FileLen(ToAbs(nm));
  if (!d || len < 0)
    return 0;
  nl = StrLen(needle);
  if (!nl)
    return 0;
  rl = StrLen(rep);
  cap = MEMFS_CAP - 1;
  out = MAlloc(cap + 1);
  if (!out) {
    "HomeReplFile: out of memory: %s\n", nm;
    return 0;
  }
  hits = 0;
  i = 0;
  o = 0;
  while (i < len) {
    k = 0;
    while (k < nl && i + k < len && d[i + k] == needle[k])
      k++;
    if (k == nl) {
      if (o + rl > cap)
        break;
      for (k = 0; k < rl; k++)
        out[o + k] = rep[k];
      o = o + rl;
      i = i + nl;
      hits++;
      continue;
    }
    if (o >= cap)
      break;
    out[o] = d[i];
    o++;
    i++;
  }
  out[o] = 0;
  if (hits) {
    FileWrite(ToAbs(nm), out, o);
    "%s: %d replaced\n", nm, hits;
  }
  Free(out);
  return hits;
}
// HomeWalk -- HomeWalk(needle,rep,cwd_only)
// NAME
//   HomeWalk - grep (rep=NULL) or substitute across memfs files
// SYNOPSIS
//   I64 HomeWalk(U8 *needle, U8 *rep, I64 cwd_only);
// DESCRIPTION
//   cwd_only=0 is the stock "/*" mask (whole tree from root); cwd_only=1 is
//   the stock "*" mask (current directory subtree, like seed Find). Returns
//   total hits across files.
// SEE ALSO
//   F  R  FD  RD  Find
I64 HomeWalk(U8 *needle, U8 *rep, I64 cwd_only)
{
  I64 i, n, cl, hits;
  U8 *nm, *cwd;
  if (!needle || !*needle) {
    UartStr("HomeWalk: need a needle\n");
    return 0;
  }
  cwd = CwdStr();
  cl = 0;
  while (cwd[cl])
    cl++;
  hits = 0;
  n = FileCount();
  for (i = 0; i < n; i++) {
    nm = FileName(i);
    if (!nm || !*nm)
      continue;
    if (HomeIsDot(nm))
      continue;
    if (cwd_only && !InCwd(nm))
      continue;
    if (rep)
      hits = hits + HomeReplFile(nm, needle, rep);
    else
      hits = hits + HomeGrepFile(nm, needle);
  }
  return hits;
}
// F -- F("needle")
// NAME
//   F - find text in every memfs text file
// SYNOPSIS
//   I64 F(U8 *needle);
// DESCRIPTION
//   Stock ~/HomeWrappers F: Find(needle,"/*") over the whole tree, printing
//   file:line and returning the hit count. Ignores cwd -- use FD for the
//   current directory. Plain substring; no fu_flags.
// EXAMPLES
//   F("TermGoto");
//   F("MEM_UART");
// SEE ALSO
//   FD  R  RD  Find  FindIn  FilesFind
// BUGS
//   No fu_flags (+l/-i), no regex, no interactive FUF window. One hit per line.
I64 F(U8 *needle)
{
  return HomeWalk(needle, 0, 0);
}
// FD -- FD("needle")
// NAME
//   FD - find text in the current directory's text files
// SYNOPSIS
//   I64 FD(U8 *needle);
// DESCRIPTION
//   Stock ~/HomeWrappers FD: Find(needle,"*") -- cwd subtree only, the same
//   scope as seed Find. Returns the hit count.
// EXAMPLES
//   Cd("Lib"); FD("PutCh");
// SEE ALSO
//   F  RD  Find  Cd
// BUGS
//   No fu_flags; plain substring.
I64 FD(U8 *needle)
{
  return HomeWalk(needle, 0, 1);
}
// R -- R("needle","replacement")
// NAME
//   R - find and replace across every memfs text file
// SYNOPSIS
//   I64 R(U8 *needle, U8 *rep);
// DESCRIPTION
//   Stock ~/HomeWrappers R: Find(needle,"/*",...,rep) over the whole tree.
//   Rewrites each touched file through FileWrite, so the edits land in the fs
//   journal (FsChanges / FsLog / DumpChanges). Returns replacements made.
// EXAMPLES
//   R("MEM_UART","MEM_UART0");
// SEE ALSO
//   RD  F  FD  FsChanges  FsCheckpoint  DumpChanges
// BUGS
//   Both args are required -- the REPL JIT does not fill HolyC default args,
//   so there is no stock delete-the-needle R(needle) form; pass "".
//   No confirmation prompt: this rewrites files in place.
I64 R(U8 *needle, U8 *rep)
{
  return HomeWalk(needle, rep, 0);
}
// RD -- RD("needle","replacement")
// NAME
//   RD - find and replace in the current directory's text files
// SYNOPSIS
//   I64 RD(U8 *needle, U8 *rep);
// DESCRIPTION
//   Stock ~/HomeWrappers RD: Find(needle,"*",...,rep) -- cwd subtree only.
// EXAMPLES
//   Cd("Home"); RD("old","new");
// SEE ALSO
//   R  F  FD  Cd  FsChanges
// BUGS
//   Same as R: both args required, in-place rewrite, no fu_flags.
I64 RD(U8 *needle, U8 *rep)
{
  return HomeWalk(needle, rep, 1);
}
