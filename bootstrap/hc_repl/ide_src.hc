// ide_src.hc -- Src / Run / editor trampoline after seed editors + RVEditorSelected.
// G3: Src opens preferred editor (Vi by default); quit returns to REPL.
// Prefer memfs path before man-lane SrcFile (ManUnitFor can false-hit on paths).
U8 ide_src_name[96];
I64 IdeHasHcSuffix(U8 *name)
{
  I64 n;
  if (!name)
    return 0;
  n = 0;
  while (name[n])
    n++;
  if (n < 3)
    return 0;
  if (name[n - 3] != '.')
    return 0;
  if (name[n - 2] != 'h' && name[n - 2] != 'H')
    return 0;
  if (name[n - 1] != 'c' && name[n - 1] != 'C' && name[n - 1] != 'h' && name[n - 1] != 'H')
    return 0;
  return 1;
}

U0 IdeSetName(U8 *name)
{
  I64 j = 0;
  while (name[j] && j < 95) {
    ide_src_name[j] = name[j];
    j++;
  }
  ide_src_name[j] = 0;
}

U0 IdeSetHome(U8 *name)
{
  I64 j, k;
  ide_src_name[0] = 'H';
  ide_src_name[1] = 'o';
  ide_src_name[2] = 'm';
  ide_src_name[3] = 'e';
  ide_src_name[4] = '/';
  j = 5;
  k = 0;
  while (name[k] && j < 95) {
    ide_src_name[j] = name[k];
    j++;
    k++;
  }
  ide_src_name[j] = 0;
}

U0 IdeAppendHc()
{
  I64 j;
  j = 0;
  while (ide_src_name[j])
    j++;
  if (j + 3 >= 96)
    return;
  ide_src_name[j] = '.';
  ide_src_name[j + 1] = 'h';
  ide_src_name[j + 2] = 'c';
  ide_src_name[j + 3] = 0;
}

U8 *IdeResolveFile(U8 *name)
{
  if (!name || !*name)
    return 0;
  if (FileLen(name) >= 0) {
    IdeSetName(name);
    return ide_src_name;
  }
  if (!IdeHasHcSuffix(name)) {
    IdeSetName(name);
    IdeAppendHc();
    if (FileLen(ide_src_name) >= 0)
      return ide_src_name;
  }
  IdeSetHome(name);
  if (FileLen(ide_src_name) >= 0)
    return ide_src_name;
  if (!IdeHasHcSuffix(name)) {
    IdeSetHome(name);
    IdeAppendHc();
    if (FileLen(ide_src_name) >= 0)
      return ide_src_name;
  }
  return 0;
}

U0 Run(U8 *name)
{
  U8 *fn, *src;
  I64 jr;
  fn = IdeResolveFile(name);
  if (!fn)
    fn = name;
  src = FileRead(fn);
  if (!src || FileLen(fn) < 0) {
    UartStr("Run: no such file: ");
    if (name)
      UartStr(name);
    UartStr("\n");
    return;
  }
  jr = ExePutS(src, fn);
  if (jr < 0)
    UartStr("Run: compile error\n");
}

U0 Exec(U8 *src)
{
  if (!src)
    return;
  ExePutS(src, NULL);
}

U0 HcCallEditor(U8 *name)
{
  // Prefer direct calls — `editor(name)` IC_CALL_INDIRECT can wedge on the large
  // AOT TU (Vi works as JitAdd/direct; Src hung with no NORMAL paint).
  if (editor == &EditHoly || editor == &Edit)
    EditHoly(name);
  else if (editor == &EdHoly || editor == &Ed)
    EdHoly(name);
  else
    Vi(name);
}
// Seed Ed() reads host EdC via MEM_HOST_SLOTS; on thin image that DRAM is garbage and
// wedges. Always EdHoly — soft RX via HcUartGet (do not touch hc_repl/uart ring).
U0 Ed(U8 *name)
{
  EdHoly(name);
}

U0 Src(U8 *name)
{
  U8 *fn;
  I64 j;
  if (!name || !*name) {
    UartStr("Src: need name\n");
    return;
  }
  fn = IdeResolveFile(name);
  if (!fn)
    fn = SrcFile(name);
  if (!fn) {
    UartStr("Src: no source for ");
    UartStr(name);
    PutCh('\n');
    return;
  }
  // Seek only for symbol names (not raw paths with / or .hc).
  j = 0;
  while (name[j] && name[j] != '/' && name[j] != '.')
    j++;
  if (!name[j])
    SrcJumpSet(name);
  else
    JumpIdent[0] = 0;
  HcCallEditor(fn);
  JumpIdent[0] = 0;
  // Auto-Run only for symbol Src("Name") — path Src("f.hc") already edited;
  // re-ExePutS of demos can desync thin-JIT smokes after Vi.
  j = 0;
  while (name[j] && name[j] != '/' && name[j] != '.')
    j++;
  if (!name[j] && IsHcName(fn))
    Run(fn);
}
