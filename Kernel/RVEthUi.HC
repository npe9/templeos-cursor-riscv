// Eth() — what the ethernet controller says about itself, without touching it.
//
// Read-only on purpose. The GEM's DMA is NOT coherent with the L1 data cache on the FU540/740, so
// bringing up descriptor rings is real work (see docs/UNMATCHED_DEVICES.md); until that is done,
// the useful thing is to read what firmware left configured. On the HiFive Unmatched that includes
// the MAC address, which U-Boot programs from the board's 24c02 EEPROM -- so this doubles as an
// independent check of the register map: if Eth() prints the address U-Boot printed, the base and
// the offsets are right.
#ifndef RV_ETH_UI_HC
#define RV_ETH_UI_HC
#help_index "Dbg"
U0 Eth()
{
  //GEM identity and state. Reads only — no reset, no descriptor rings, no DMA.
  I64 ncr, ncfgr, lo, hi;
  if (!RVSifiveGemPresent) {
    Print("Eth: no GEM on this board (CONFIG_SIFIVE_ETH_BASE is 0)\n");
    return;
  }
  ncr = RVSifiveGemRd(RVSIFIVE_GEM_NCR);
  ncfgr = RVSifiveGemRd(RVSIFIVE_GEM_NCFGR);
  Print("GEM @ 0x%08X  irq %d\n", RVSifiveGemBase, RVSifiveGemIrqNum);
  // Four specific-address slots at 0x88, 0x90, 0x98, 0xA0 (bottom) with their tops 4 bytes up.
  // Do NOT assume slot 1: on this board U-Boot leaves the address in SLOT 3 and slot 1 reads zero,
  // so a reader hardwired to SA1B reports a controller with no MAC. Print whichever slots are set.
  {
    I64 slot = 0, found = 0;
    while (slot < 4) {
      lo = RVSifiveGemRd(RVSIFIVE_GEM_SA1B + slot * 8);
      hi = RVSifiveGemRd(RVSIFIVE_GEM_SA1T + slot * 8);
      if (lo || (hi & 0xFFFF)) {
        Print("  MAC %02X:%02X:%02X:%02X:%02X:%02X   (slot %d, programmed by firmware from the board EEPROM)\n",
              lo & 0xFF, (lo >> 8) & 0xFF, (lo >> 16) & 0xFF, (lo >> 24) & 0xFF,
              hi & 0xFF, (hi >> 8) & 0xFF, slot + 1);
        found++;
      }
      slot++;
    }
    if (!found)
      Print("  MAC none: all four specific-address slots are clear\n");
  }
  Print("  ncr   0x%08X  rx=%d tx=%d\n", ncr, (ncr & RVSIFIVE_GEM_NCR_RE) != 0, (ncr & RVSIFIVE_GEM_NCR_TE) != 0);
  Print("  ncfgr 0x%08X  (bit0 100Mb, bit1 full-duplex, bit10 gigabit)\n", ncfgr);
  Print("  rxq   0x%08X  txq 0x%08X\n", RVSifiveGemRd(RVSIFIVE_GEM_RXQBASE), RVSifiveGemRd(RVSIFIVE_GEM_TXQBASE));
  Print("  DMA is not L1-coherent here: rings need L2 flushes before this can send a packet\n");
}
#endif
