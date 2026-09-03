// fs.hc -- AOT HolyC REPL memfs: share seed journal (FsJournal/FsOnWrite/FsOnDel).
// Do not grow jit.hc for logging. Seed P6 may edit seed/fs.hc — keep this as include + FsInit.
#include "/bootstrap/seed/fs.hc"
// Fast slot clear (no full 96×65KiB MemSet — too slow under QEMU AOT).
// Journal ring / snap tables live at MEMFS_CWD+…; FsEpochSeal rebuilds them after seed.
U0 FsInit()
{
  I64 i;
  U8 *cwd, *p;
  for (i = 0; i < MEMFS_MAX; i++) {
    FsSetUsed(i, 0);
    FsSetLen(i, 0);
    *FsName(i) = 0;
  }
  cwd = FsCwd();
  // Zero cwd string + track/dirty/del meta ahead of the side ring.
  p = cwd;
  i = 0;
  while (i < FS_LOG_OFF) {
    *p = 0;
    p++;
    i++;
  }
  FsDelN = 0;
  FsSnapN = 0;
  FsLogSeq = 0;
  FsLogEpochId = 0;
  FsLogHead = 0;
  FsLogCount = 0;
  FsLogGen = 0;
  FsLogReady = 0;
  FsChN = 0;
  FsChBusy = 0;
  FsEmpty[0] = 0;
}
