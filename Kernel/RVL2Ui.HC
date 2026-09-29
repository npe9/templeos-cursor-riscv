// L2() — what the cache is, and whether the scratchpad is still available.
#ifndef RV_L2_UI_HC
#define RV_L2_UI_HC
#help_index "Dbg"
U0 L2()
{
  //Cache geometry from the Config register, and the way-enable state that decides the LIM.
  I64 cfg, we, banks, ways, sets, blk;
  if (!RVL2Base) {
    Print("L2: no L2 controller known for this board\n");
    return;
  }
  cfg = RVL2Config();
  we = RVL2WayEnable();
  banks = cfg & 0xFF;
  ways = (cfg >> 8) & 0xFF;
  sets = 1 << ((cfg >> 16) & 0xFF);
  blk = 1 << ((cfg >> 24) & 0xFF);
  Print("L2 @ 0x%08X  config 0x%08X\n", RVL2Base, cfg);
  Print("  %d banks x %d ways x %d sets x %d B = %d KiB\n", banks, ways, sets, blk,
        banks * ways * sets * blk / 1024);
  Print("  WayEnable %d: ways 0..%d are cache\n", we, we);
  if (we >= ways - 1) {
    Print("  every way is cache, so the LIM at 0x08000000 is gone — and ways cannot be taken\n");
    Print("  back without a reset. Whether DMA here then needs Flush64 is still unmeasured:\n");
    Print("  FU740 on-chip masters may reach memory coherently through the L2 front port.\n");
  } else
    Print("  %d way(s) are still LIM at 0x08000000 (%d KiB)\n", ways - 1 - we,
          (ways - 1 - we) * banks * sets * blk / 1024);
}
#endif
