// Read-only PCIe config-space access, for boards whose firmware has already trained the link.
//
// Milestone 1 of docs/UNMATCHED_DEVICES.md: enumerate, print, touch nothing. Every function here
// reads; none writes, so this cannot disturb a link U-Boot has brought up or a device Linux left
// configured. BAR assignment, resets and DMA belong to later milestones.
//
// The FU740's ECAM is at 0xE00000000 -- ABOVE 4 GiB. Every address is therefore computed in I64 and
// handed to InU32/InU16 as an I64; a U32 anywhere in this arithmetic would silently truncate to
// 0x00000000 and read the bottom of DRAM instead. QEMU virt's 0x30000000 hides that class of bug
// completely, which is why it is called out here rather than discovered on hardware.
#ifndef RV_DRV_PCIE_HC
#define RV_DRV_PCIE_HC
#ifndef CONFIG_PCIE_ECAM_BASE
#define CONFIG_PCIE_ECAM_BASE 0
#endif
#ifndef CONFIG_PCIE_DBI_BASE
#define CONFIG_PCIE_DBI_BASE 0
#endif
#define RV_PCI_VENDOR_NONE  0xFFFF
#define RV_PCI_OFF_VENDOR   0x00
#define RV_PCI_OFF_DEVICE   0x02
#define RV_PCI_OFF_CLASS    0x08   /* [31:24] class, [23:16] subclass, [15:8] prog-if, [7:0] rev */
#define RV_PCI_OFF_HDRTYPE  0x0E   /* bit 7 = multifunction */
#define RV_PCI_OFF_SECBUS   0x19   /* type-1 header: the bus behind this bridge */

I64 RVPcieBase()
{
  return CONFIG_PCIE_ECAM_BASE;
}

I64 RVPcieDbi()
{
  return CONFIG_PCIE_DBI_BASE;
}

I64 RVPcieRootVendor()
{
  // The root port, read through the DBI alias. On a DesignWare core this works before the iATU is
  // touched, which makes it the one thing a read-only pass can honestly report on the FU740.
  if (!CONFIG_PCIE_DBI_BASE)
    return RVPcieVendor(0, 0, 0);
  return InU16(CONFIG_PCIE_DBI_BASE + RV_PCI_OFF_VENDOR);
}

I64 RVPcieRootDevice()
{
  if (!CONFIG_PCIE_DBI_BASE)
    return RVPcieRd16(0, 0, 0, RV_PCI_OFF_DEVICE);
  // 0x02, not 0x04: a 16-bit read at an even offset needs no adjustment, and +4 is the Command
  // register -- which read back as 0x0007 (IO|MEM|BusMaster) and looked exactly like a device id
  // until U-Boot's own `pci` said the root port is 0xF15E:0x0000.
  return InU16(CONFIG_PCIE_DBI_BASE + RV_PCI_OFF_DEVICE);
}

I64 RVPcieEcamAnswers()
{
  //Does the config window yield config cycles at all? All-ones at 0:0.0 means it does not.
  if (!CONFIG_PCIE_ECAM_BASE)
    return 0;
  return RVPcieVendor(0, 0, 0) != RV_PCI_VENDOR_NONE;
}

I64 RVPcieCfgAddr(I64 bus, I64 dev, I64 fn, I64 off)
{
  // I64 throughout: see the header comment. The masks keep a caller's mistake from walking out of
  // the 256 MiB ECAM window into whatever the SoC maps next.
  return CONFIG_PCIE_ECAM_BASE + ((bus & 0xFF) << 20) + ((dev & 31) << 15) + ((fn & 7) << 12) + (off & 0xFFC);
}

U32 RVPcieRd32(I64 bus, I64 dev, I64 fn, I64 off)
{
  if (!CONFIG_PCIE_ECAM_BASE)
    return 0xFFFFFFFF;
  return InU32(RVPcieCfgAddr(bus, dev, fn, off));
}

U16 RVPcieRd16(I64 bus, I64 dev, I64 fn, I64 off)
{
  if (!CONFIG_PCIE_ECAM_BASE)
    return RV_PCI_VENDOR_NONE;
  return InU16(RVPcieCfgAddr(bus, dev, fn, off) + (off & 2));
}

U8 RVPcieRd8(I64 bus, I64 dev, I64 fn, I64 off)
{
  if (!CONFIG_PCIE_ECAM_BASE)
    return 0xFF;
  return InU8(RVPcieCfgAddr(bus, dev, fn, off) + (off & 3));
}

I64 RVPcieVendor(I64 bus, I64 dev, I64 fn)
{
  //0xFFFF means nothing answered. An all-ones read IS the absence signal on PCI: unclaimed config
  //cycles come back as ones, so there is no separate "is it there" question to ask.
  return RVPcieRd16(bus, dev, fn, RV_PCI_OFF_VENDOR);
}

I64 RVPciePresent(I64 bus, I64 dev, I64 fn)
{
  I64 v = RVPcieVendor(bus, dev, fn);
  if (v == RV_PCI_VENDOR_NONE || v == 0)
    return 0;
  return 1;
}

I64 RVPcieMultiFn(I64 bus, I64 dev)
{
  if (!RVPciePresent(bus, dev, 0))
    return 0;
  return (RVPcieRd8(bus, dev, 0, RV_PCI_OFF_HDRTYPE) >> 7) & 1;
}

I64 RVPcieClass(I64 bus, I64 dev, I64 fn)
{
  //Class in [15:8], subclass in [7:0] — the pair U-Boot prints.
  U32 c = RVPcieRd32(bus, dev, fn, RV_PCI_OFF_CLASS);
  return ((c >> 16) & 0xFF00) | ((c >> 16) & 0xFF);
}

U8 *RVPcieClassName(I64 cls)
{
  //Only the classes this board actually shows, plus the ones worth recognising on sight.
  switch (cls >> 8) {
    case 0x01: return "Mass storage";
    case 0x02: return "Network";
    case 0x03: return "Display";
    case 0x04: return "Multimedia";
    case 0x06: return "Bridge";
    case 0x0C: return "Serial bus";
    case 0x0D: return "Wireless";
  }
  return "-";
}
#endif
