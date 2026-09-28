// Pci() — the prompt-facing enumerator. Separate from Kernel/Drv/RVPcie.HC for the same reason the
// GPIO driver is split: the thin plat image includes the driver and has no Print.
#ifndef RV_PCIE_UI_HC
#define RV_PCIE_UI_HC
#help_index "Dbg"
I64 RVPciScanBus(I64 bus, I64 depth)
{
  // One bus, then recurse behind any bridge. Depth-limited because a malformed secondary-bus
  // register (or a device that answers every address) would otherwise recurse forever -- and on a
  // board whose switch has five downstream ports that is not a hypothetical shape.
  I64 dev, fn, fns, n = 0, cls, sec;
  if (depth > 4)
    return 0;
  dev = 0;
  while (dev < 32) {
    if (RVPciePresent(bus, dev, 0)) {
      fns = 1;
      if (RVPcieMultiFn(bus, dev))
        fns = 8;
      fn = 0;
      while (fn < fns) {
        if (RVPciePresent(bus, dev, fn)) {
          cls = RVPcieClass(bus, dev, fn);
          Print("  %02X.%02X.%02X   0x%04X   0x%04X   %-14s 0x%02X\n",
                bus, dev, fn, RVPcieVendor(bus, dev, fn), RVPcieRd16(bus, dev, fn, RV_PCI_OFF_DEVICE),
                RVPcieClassName(cls), cls & 0xFF);
          n++;
          if ((cls >> 8) == 0x06) {
            // A bridge names the bus behind it in its type-1 header. Only follow a forward edge:
            // firmware numbers buses increasing away from the root, so sec<=bus means a bad read.
            sec = RVPcieRd8(bus, dev, fn, RV_PCI_OFF_SECBUS);
            if (sec > bus && sec < 0xFF)
              n += RVPciScanBus(sec, depth + 1);
          }
        }
        fn++;
      }
    }
    dev++;
  }
  return n;
}

U0 Pci()
{
  //Every PCIe function firmware left configured. Reads only — no BARs are assigned, nothing is reset.
  I64 n;
  if (!RVPcieBase) {
    Print("Pci: no PCIe ECAM known for this board (CONFIG_PCIE_ECAM_BASE is 0)\n");
    return;
  }
  Print("PCIe ECAM @ 0x%010X", RVPcieBase);
  if (RVPcieDbi)
    Print("   DBI @ 0x%010X", RVPcieDbi);
  Print("\n");
  if (!RVPcieEcamAnswers) {
    // Measured on the HiFive Unmatched: after U-Boot finishes, the config window returns all-ones
    // because the DesignWare iATU no longer maps config cycles, while the root port is still
    // readable through the DBI alias. Report exactly that instead of walking a window of ones and
    // reporting the controller's registers as if they were devices.
    Print("  config window returns all-ones: the iATU does not map config cycles right now\n");
    if (RVPcieDbi) {
      Print("  root port via DBI: vendor 0x%04X device 0x%04X\n", RVPcieRootVendor, RVPcieRootDevice);
      Print("  downstream buses need the iATU programmed — a write, so milestone 1b, not this pass\n");
      Print("  (U-Boot's `pci` enumerates them: 0x1B21:0x2824 switch, 0x1B21:0x1142 USB)\n");
    }
    return;
  }
  Print("  BusDevFun  VendorId DeviceId Class          Sub\n");
  n = RVPciScanBus(0, 0);
  if (!n)
    Print("  (nothing answered — firmware may not have trained the link)\n");
  else
    Print("  %d function(s)\n", n);
}
#endif
