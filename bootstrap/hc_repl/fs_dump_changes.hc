// fs_dump_changes.hc -- UART batch export of the memfs dirty set (hc_repl / AOT).
// Same body as seed/zmodem.hc DumpChanges; kept here so we do not pull ZMODEM into
// the product image. Requires seed/fs.hc journal + seed/files.hc DumpFile.
// (Named fs_dump_* — not dump_* — so .gitignore dump_* does not hide this source.)
// DumpChanges -- DumpChanges(since_epoch)
// NAME
//   DumpChanges - UART manifest of the dirty set, then DumpFile each body
// SYNOPSIS
//   U0 DumpChanges(I64 since_epoch=-1);
U0 DumpChanges(I64 since_epoch = -1)
{
  I64 n, i, op, dumps, since_lo;
  U8 *path, *path2;
  if (since_epoch < -1)
    since_epoch = -1;
  n = FsChangeCollect(since_epoch, 0, -1);
  dumps = 0;
  i = 0;
  while (i < n) {
    if (FsChangeCanDump(i))
      dumps++;
    i++;
  }
  if (since_epoch < 0)
    since_lo = 0;
  else
    since_lo = since_epoch;
  "$$HC_CHANGES epoch=%d..%d count=%d dumps=%d$$\n", since_lo, FsEpoch(), n, dumps;
  i = 0;
  while (i < n) {
    op = FsChangeOp(i);
    path = FsChangePath(i);
    path2 = FsChangePath2(i);
    if (op == FS_OP_RENAME && *path2)
      "  %c  %s -> %s\n", FsOpChar(op), path, path2;
    else
      "  %c  %s\n", FsOpChar(op), path;
    i++;
  }
  "$$HC_END$$\n";
  i = 0;
  while (i < n) {
    if (FsChangeCanDump(i)) {
      op = FsChangeOp(i);
      if (op == FS_OP_RENAME)
        path = FsChangePath2(i);
      else
        path = FsChangePath(i);
      DumpFile(path);
    }
    i++;
  }
}
