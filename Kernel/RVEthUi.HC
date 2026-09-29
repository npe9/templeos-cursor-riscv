// Eth() — what the ethernet controller says about itself, without touching it.
//
// Read-only on purpose. Whether the GEM's DMA is coherent with the caches on the FU540/740 is an
// open question this tree has asserted both ways and measured neither (see EthAb below, and
// docs/UNMATCHED_DEVICES.md); until it is settled, the useful thing is to read what firmware left
// configured without disturbing it. On the HiFive Unmatched that includes
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
  Print("  ring coherency unsettled — run EthAb to find out whether sending needs L2 flushes\n");
}
// EthAb() — does this controller need cache maintenance, or not?
//
// The claim "FU740 DMA is not coherent, so the rings need L2 flushes" has been in this tree's
// comments and in a commit message without ever being tested. The evidence cuts both ways: only
// the PCIe node in the device tree is marked dma-coherent, which argues non-coherent — but Linux
// drove this board's ethernet for years with no cache maintenance at all, which argues that
// on-chip masters reach memory through the L2 front port and are coherent already.
//
// So run the same TX probe twice, once with a flush of the descriptor and buffer arena and once
// without, and print what the controller says each time. The interesting outcomes:
//   flush helps                -> non-coherent, and RVL2FlushRange is the fix
//   both fail the same way     -> coherency is NOT the fault; look at the PHY link, the GEMGXL
//                                 clock (see Clk) and the queue base instead
//   both succeed               -> coherent, and the flushes are not needed
// This WRITES to the GEM: it resets the controller and re-lays the rings, which means it takes
// the interface away from whatever firmware configured. Everything else in this file is a read.
U0 EthAb()
{
  I64 a_rc, b_rc, a_d1, b_d1, a_st, b_st, base, len;
  if (!RVSifiveGemPresent) {
    Print("EthAb: no GEM on this board\n");
    return;
  }
  base = RVSifiveGemDmaBase;
  len = RVSifiveGemDmaLen;
  Print("EthAb: this RESETS the GEM and re-lays its rings, taking the interface away from\n");
  Print("       whatever firmware configured. Everything else in Eth() is a read.\n");
  Print("  DMA arena 0x%08X + 0x%X (descriptors, TX buffers, RX buffers), L2 %s\n", base, len,
        RVL2Base ? "present" : "absent — no flush possible, so run B is not a real B");
  RVSifiveGemInit;
  a_rc = RVSifiveGemTxProbe;
  a_d1 = RVSifiveGemTxDescW1;
  a_st = RVSifiveGemRd(RVSIFIVE_GEM_TXSTATUS);
  RVSifiveGemInit;
  RVL2FlushRange(base, len);
  b_rc = RVSifiveGemTxProbe;
  b_d1 = RVSifiveGemTxDescW1;
  b_st = RVSifiveGemRd(RVSIFIVE_GEM_TXSTATUS);
  Print("  A no flush  rc=%d  txdesc[1]=0x%08X  txstatus=0x%08X\n", a_rc, a_d1, a_st);
  Print("  B flushed   rc=%d  txdesc[1]=0x%08X  txstatus=0x%08X\n", b_rc, b_d1, b_st);
  // rc 0 is "the controller took the buffer"; -2 is "it never gave the descriptor back";
  // -3 is "it started and never completed". USED (bit 31 of the TX status word) is the
  // controller's own statement that it read the descriptor we wrote.
  if (!a_rc && !b_rc)
    Print("  both sent: the rings work with no cache maintenance, so DMA here is coherent\n");
  if (a_rc && !b_rc)
    Print("  only the flushed run sent: DMA is NOT coherent and RVL2FlushRange is required\n");
  if (!a_rc && b_rc)
    Print("  only the unflushed run sent: suspect the flush itself, not coherency\n");
  if (a_rc && b_rc) {
    Print("  neither sent, and identically if the two lines above match — then coherency is not\n");
    Print("  the fault. Check the PHY link, the GEMGXL clock (Clk) and the queue base (Eth).\n");
  }
}
#endif
