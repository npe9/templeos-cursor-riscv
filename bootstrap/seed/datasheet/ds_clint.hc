// ds_clint.hc -- CLINT MMIO datasheet (mtime / mtimecmp / msip).
// Counters are full-width ticks; msip is a soft-IRQ latch bit.
U0 DsSheetClintMsip()
{
  DsBegin("clint.msip", "clint", DS_KIND_MMIO, MEM_CLINT, 4);
  DsField("MSIP", 0, 0, "0=clear,1=pending", "Machine software interrupt pending");
  DsEnd;
}

U0 DsSheetClintMtime()
{
  DsBegin("clint.mtime", "clint", DS_KIND_MMIO, MEM_MTIME, 8);
  DsField("MTIME", 0, 63, 0, "Free-running machine timer (ticks)");
  DsEnd;
}

U0 DsSheetClintMtimecmp()
{
  DsBegin("clint.mtimecmp", "clint", DS_KIND_MMIO, MEM_MTIMECMP, 8);
  DsField("MTIMECMP", 0, 63, 0, "Hart0 timer compare (alarm)");
  DsEnd;
}

U0 DsClintInit()
{
  DsSheetClintMsip;
  DsSheetClintMtime;
  DsSheetClintMtimecmp;
}
DsClintInit;
