// dir.hc -- Dir() listing for the AOT HolyC REPL (no editor / host-slot deps).
U0 Dir()
{
  I64 i, n, sz;
  U8 *nm;
  n = FileCount();
  Print("Dir: %d files\n", n);
  for (i = 0; i < n; i++) {
    nm = FileName(i);
    sz = FileSize(i);
    if (!nm)
      continue;
    Print("  %s  (%d)\n", nm, sz);
  }
}

U0 Cat(U8 *name)
{
  U8 *p, *s;
  if (!name || !*name) {
    "Cat: need name\n";
    return;
  }
  // Copy name — avoid name[i] on the parameter (AOT index hazard).
  s = name;
  p = FsTmp;
  while (*s && p < &FsTmp[150]) {
    *p = *s;
    p++;
    s++;
  }
  *p = 0;
  p = FileRead(FsTmp);
  if (!p) {
    "Cat: no such file\n";
    return;
  }
  UartStr(p);
  PutCh('\n');
}
// Src -- print defining source from memfs (AOT image has no live JIT editor yet).
// Note: avoid name[i] on the parameter (AOT frame/index hazard); copy via *p bump first.
U8 src_path[96];
U0 Src(U8 *name)
{
  U8 *p, *d;
  if (!name) {
    "Src: need name\n";
    return;
  }
  if (!*name) {
    "Src: need name\n";
    return;
  }
  d = src_path;
  p = name;
  while (*p && d < &src_path[90]) {
    *d = *p;
    d++;
    p++;
  }
  *d = 0;
  p = FileRead(src_path);
  if (!p) {
    d = src_path;
    while (*d)
      d++;
    *d = '.';
    d++;
    *d = 'h';
    d++;
    *d = 'c';
    d++;
    *d = 0;
    p = FileRead(src_path);
  }
  if (!p) {
    UartStr("Src: no source for ");
    UartStr(src_path);
    PutCh('\n');
    return;
  }
  UartStr("==== ");
  UartStr(src_path);
  UartStr(" ====\n");
  UartStr(p);
  PutCh('\n');
}
