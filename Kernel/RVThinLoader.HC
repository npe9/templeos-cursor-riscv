// RVThinLoader — G9 thin boot path: virtio RedSea already mounted by RVKMain,
// then FileFind+Load A:/Kernel/Kernel.BIN and Call KernelEntry (handoff).
// No Cmp / MakeOS / StartOS — purpose is prove loader→BIN transfer so Mac
// phase3.elf can shrink toward “mount + Load + jump” only.
// Demo: tests/exec/cases/kernel_thin_loader_demo.hc
#ifndef RV_THIN_LOADER_HC
#define RV_THIN_LOADER_HC
Bool rv_thin_loader_ok = FALSE;
U0 RVThinUart(U8 *msg)
{
  U8 *uart = CONFIG_UART_BASE;
  if (!msg)
    return;
  while (*msg)
    *uart = *msg++;
}

U0 RVThinUartI64(U8 *prefix, I64 v)
{
  U8 msg[96];
  StrPrint(msg, "%s%d\n", prefix, v);
  RVThinUart(msg);
}

I64 RVThinCallExport(U8 *name)
{
  CHashExport *tmpex;
  if (!name)
    return -1;
  tmpex = HashFind(name, Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex)
    tmpex = HashFind(name, Fs->hash_table, HTT_FUN);
  if (!tmpex)
    return -1;
  if (tmpex->type & HTT_FUN)
    return Call(tmpex(CHashFun *)->exe_addr);
  return Call(tmpex->val);
}

U0 RVThinLoader()
{
  CBinFile *bfh;
  I64 r;
  rv_thin_loader_ok = FALSE;
  RVThinUart("RVThinLoader: RedSea mounted; FileFind A:/Kernel/Kernel.BIN...\n");
  if (!FileFind("A:/Kernel/Kernel.BIN")) {
    RVThinUart("RVThinLoader: Kernel.BIN missing (FileFind).\n");
    return;
  }
  RVThinUart("RVThinLoader: FileFind OK; Load...\n");
  bfh = Load("A:/Kernel/Kernel.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    RVThinUart("RVThinLoader: Load FAILED.\n");
    return;
  }
  RVThinUart("RVThinLoader: Load OK; Call KernelEntry (handoff)...\n");
  r = RVThinCallExport("KernelEntry");
  if (r != 0x4B45) {
    RVThinUartI64("RVThinLoader: KernelEntry FAILED r=", r);
    return;
  }
  r = RVThinCallExport("KernelProbe");
  if (r != 42) {
    RVThinUartI64("RVThinLoader: KernelProbe FAILED r=", r);
    return;
  }
  // G9 growth: KernelEntry ran KernelInitLite (heap MAlloc/Free + FileWrite).
  if (!FileFind("A:/Kernel/ENTRY.OK")) {
    RVThinUart("RVThinLoader: ENTRY.OK missing (KernelInitLite FileWrite).\n");
    return;
  }
  r = RVThinCallExport("KernelHeapProbe");
  if (r != 64) {
    RVThinUartI64("RVThinLoader: KernelHeapProbe FAILED r=", r);
    return;
  }
  r = RVThinCallExport("KernelInitLite");
  if (r != 0x4B49) {
    RVThinUartI64("RVThinLoader: KernelInitLite FAILED r=", r);
    return;
  }
  FileWrite("A:/Kernel/THIN.OK", "OK", 2);
  rv_thin_loader_ok = TRUE;
  RVThinUart("RVThinLoader: handoff OK (KernelEntry=0x4B45, KernelProbe=42).\n");
  RVThinUart("RVThinLoader: InitLite OK (ENTRY.OK + HeapProbe=64 + InitLite=0x4B49).\n");
  RVThinUart("RVThinLoader: done (thin loader + RedSea Kernel.BIN).\n");
}
#endif
