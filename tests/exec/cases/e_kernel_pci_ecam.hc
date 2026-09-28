// Read-only PCIe config space: the enumerator's mechanics, on QEMU virt's host bridge.
//
// virt always has a PCIe host bridge at 0:0.0 with ECAM at CONFIG_PCIE_ECAM_BASE, so this asserts
// the three properties that matter without naming QEMU's vendor IDs (which would make the case a
// test of QEMU rather than of the code):
//   bit 0  something answers at 0:0.0 — vendor is neither 0xFFFF nor 0
//   bit 1  it is a bridge (class 0x06): the host bridge always is
//   bit 2  an absent function reads back all ones — the PCI absence signal
//   bit 3  the ECAM address arithmetic is I64-clean: bus 1 is exactly 0x100000 above bus 0
//   bit 4  the device-id read lands in the same function as the vendor read (offset handling)
// The I64 check is the one that matters for the HiFive Unmatched, whose ECAM sits at 0xE00000000 --
// above 4 GiB, where a U32 anywhere in the arithmetic reads the bottom of DRAM instead.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  I64 r = 0, v;
  if (!RVPcieBase)
    return 0x100;
  v = RVPcieVendor(0, 0, 0);
  if (v != 0xFFFF && v != 0)                                        r |= 1;
  if ((RVPcieClass(0, 0, 0) >> 8) == 0x06)                          r |= 2;
  if (RVPcieVendor(0, 31, 7) == 0xFFFF)                             r |= 4;
  if (RVPcieCfgAddr(1, 0, 0, 0) - RVPcieCfgAddr(0, 0, 0, 0) == 0x100000) r |= 8;
  if (RVPcieRd16(0, 0, 0, RV_PCI_OFF_DEVICE) != 0xFFFF)             r |= 16;
  return r;
}
