// VirtioPci.HC — QEMU virt ECAM + modern virtio-pci capability helpers.
// ECAM @ CONFIG_PCI_ECAM_BASE (0x30000000). Dig-down: VirtioPciFind; VirtioPciParseCaps.
#ifndef RV_DRV_VIRTIO_PCI_HC
#define RV_DRV_VIRTIO_PCI_HC
#ifndef CONFIG_PCI_ECAM_BASE
#define CONFIG_PCI_ECAM_BASE 0x30000000
#endif
#ifndef CONFIG_PCI_MMIO_ASSIGN_BASE
#define CONFIG_PCI_MMIO_ASSIGN_BASE 0x48000000
#endif
#define VPCI_VENDOR_VIRTIO     0x1AF4
#define VPCI_DEV_BLK_TRANS     0x1001
#define VPCI_DEV_BLK_MODERN    0x1042
#define VPCI_DEV_9P_TRANS      0x1009
#define VPCI_DEV_9P_MODERN     0x1049
#define VPCI_DEV_NET_TRANS     0x1000
#define VPCI_DEV_NET_MODERN    0x1041
#define VPCI_CAP_VENDOR        9
#define VPCI_CAP_MSIX          0x11
#define VPCI_CAP_COMMON_CFG    1
#define VPCI_CAP_NOTIFY_CFG    2
#define VPCI_CAP_ISR_CFG       3
#define VPCI_CAP_DEVICE_CFG    4
#define VPCI_COMMON_DFSELECT   0
#define VPCI_COMMON_DF         4
#define VPCI_COMMON_GFSELECT   8
#define VPCI_COMMON_GF         12
#define VPCI_COMMON_MSIX_CFG   16
#define VPCI_COMMON_NUM_QUEUES 18
#define VPCI_COMMON_STATUS     20
#define VPCI_COMMON_CFG_GEN    21
#define VPCI_COMMON_Q_SELECT   22
#define VPCI_COMMON_Q_SIZE     24
#define VPCI_COMMON_Q_MSIX     26
#define VPCI_COMMON_Q_ENABLE   28
#define VPCI_COMMON_Q_NOTIFY   30
#define VPCI_COMMON_Q_DESC     32
#define VPCI_COMMON_Q_AVAIL    40
#define VPCI_COMMON_Q_USED     48
#define VPCI_MSIX_NO_VECTOR    0xFFFF
#define VPCI_MSIX_ENABLE       0x80000000
#define VPCI_MSIX_MASKALL      0x40000000
// QEMU virt PCIe INTx → PLIC: IRQ = 32 + ((pin-1 + slot) % 4). MSI-X needs AIA.
#define VPCI_PCIE_IRQ_BASE     32
#define VPCI_PCIE_IRQ_COUNT    4
#define VPCI_CMD_INTX_DISABLE  0x400
#define VPCI_S_ACK             1
#define VPCI_S_DRIVER          2
#define VPCI_S_DRIVER_OK       4
#define VPCI_S_FEATURES_OK     8
#define VPCI_S_FAILED          128
// mie.MEIE (bit 11). Global mstatus.MIE comes from RVTrapInit. Shared by mmio + PCI IrqInit.
asm {
	RvSetMEIE::
	li	t0,1
	slli	t0,t0,11
	csrs	0x304,t0
	ret
}

I64 VirtioPciCfgAddr(I64 bus, I64 dev, I64 fn, I64 off)
{
  return CONFIG_PCI_ECAM_BASE + ((bus & 0xFF) << 20) + ((dev & 31) << 15) + ((fn & 7) << 12) + (off & 0xFFC);
}

U32 VirtioPciRead32(I64 bus, I64 dev, I64 fn, I64 off)
{
  return InU32(VirtioPciCfgAddr(bus, dev, fn, off));
}

U16 VirtioPciRead16(I64 bus, I64 dev, I64 fn, I64 off)
{
  return InU16(VirtioPciCfgAddr(bus, dev, fn, off) + (off & 2));
}

U8 VirtioPciRead8(I64 bus, I64 dev, I64 fn, I64 off)
{
  return InU8(VirtioPciCfgAddr(bus, dev, fn, off) + (off & 3));
}

U0 VirtioPciWrite32(I64 bus, I64 dev, I64 fn, I64 off, U32 v)
{
  OutU32(VirtioPciCfgAddr(bus, dev, fn, off), v);
}

U0 VirtioPciWrite16(I64 bus, I64 dev, I64 fn, I64 off, U16 v)
{
  OutU16(VirtioPciCfgAddr(bus, dev, fn, off) + (off & 2), v);
}
// Find first virtio-pci function matching device_id (or either of two ids if id2!=0).
// Returns packed (bus<<16)|(dev<<8)|fn, or -1.
I64 VirtioPciFindIds(I64 id1, I64 id2)
{
  I64 bus, dev, fn, idl, vid, did;
  if (!RVVirtioPciEnabled())
    return -1;
  for (bus = 0; bus < 8; bus++) {
    for (dev = 0; dev < 32; dev++) {
      for (fn = 0; fn < 8; fn++) {
        idl = VirtioPciRead32(bus, dev, fn, 0);
        vid = idl & 0xFFFF;
        if (vid == 0xFFFF || !vid)
          continue;
        did = (idl >> 16) & 0xFFFF;
        if (vid != VPCI_VENDOR_VIRTIO)
          continue;
        if (did == id1 || (id2 && did == id2))
          return (bus << 16) | (dev << 8) | fn;
      }
    }
  }
  return -1;
}

I64 VirtioPciFindBlk()
{
  return VirtioPciFindIds(VPCI_DEV_BLK_MODERN, VPCI_DEV_BLK_TRANS);
}

I64 VirtioPciFind9p()
{
  return VirtioPciFindIds(VPCI_DEV_9P_MODERN, VPCI_DEV_9P_TRANS);
}

I64 VirtioPciFindNet()
{
  return VirtioPciFindIds(VPCI_DEV_NET_MODERN, VPCI_DEV_NET_TRANS);
}

U0 VirtioPciEnableBm(I64 bdf)
{
  I64 bus = (bdf >> 16) & 0xFF, dev = (bdf >> 8) & 0xFF, fn = bdf & 0xFF;
  U16 cmd = VirtioPciRead16(bus, dev, fn, 0x04);
  VirtioPciWrite16(bus, dev, fn, 0x04, cmd | 6);
}
// QEMU -bios none often leaves virtio BAR4 unassigned; map into PCIe MMIO window.
// Per-dev 64KiB slot so blk/9p/net can coexist without colliding at ASSIGN_BASE.
U0 VirtioPciAssignBar4(I64 bdf)
{
  I64 bus = (bdf >> 16) & 0xFF, dev = (bdf >> 8) & 0xFF, fn = bdf & 0xFF;
  U32 lo, hi, lo_type;
  U16 cmd;
  U64 cur, base;
  lo = VirtioPciRead32(bus, dev, fn, 0x20);
  hi = VirtioPciRead32(bus, dev, fn, 0x24);
  lo_type = lo & 0xF;
  if (lo_type != 0x4 && lo_type != 0xC)
    return;
  cur = (hi << 32) | lo;
  if (cur & ~0xF)
    return;
  cmd = VirtioPciRead16(bus, dev, fn, 0x04);
  VirtioPciWrite16(bus, dev, fn, 0x04, cmd & ~6);
  base = CONFIG_PCI_MMIO_ASSIGN_BASE + ((dev & 31) << 16) + ((fn & 7) << 12);
  VirtioPciWrite32(bus, dev, fn, 0x20, base | lo_type);
  VirtioPciWrite32(bus, dev, fn, 0x24, base >> 32);
  VirtioPciWrite16(bus, dev, fn, 0x04, cmd | 6);
}

U0 VirtioPciFillBars(I64 bdf, U64 *bar6)
{
  I64 bus = (bdf >> 16) & 0xFF, dev = (bdf >> 8) & 0xFF, fn = bdf & 0xFF;
  I64 i;
  U32 lo, hi;
  for (i = 0; i < 6; i++)
    bar6[i] = 0;
  for (i = 0; i < 6; i++) {
    lo = VirtioPciRead32(bus, dev, fn, 0x10 + 4 * i);
    if (lo & 1) {
      bar6[i] = 0;
      continue;
    }
    if ((lo & 6) == 4) {
      hi = VirtioPciRead32(bus, dev, fn, 0x10 + 4 * (i + 1));
      bar6[i] = (hi << 32) | (lo & ~0xF);
      i++;
      if (i < 6)
        bar6[i] = 0;
    } else
      bar6[i] = lo & ~0xF;
  }
}
// Parse virtio vendor caps. Returns 0; sets *common / *notify / *notify_mult / *devcfg / *isr.
// *isr may be NULL out-param (skip); when non-NULL, ISR cap is optional (may stay 0).
I64 VirtioPciParseCapsEx(I64 bdf, U64 *bars, U8 **common, U8 **notify, U32 *notify_mult, U8 **devcfg, U8 **isr)
{
  I64 bus = (bdf >> 16) & 0xFF, dev = (bdf >> 8) & 0xFF, fn = bdf & 0xFF;
  U8 ptr, id, next, len, cfg_type, bar_idx;
  U32 off, mult;
  *common = 0;
  *notify = 0;
  *devcfg = 0;
  *notify_mult = 1;
  if (isr)
    *isr = 0;
  ptr = VirtioPciRead8(bus, dev, fn, 0x34);
  while (ptr) {
    id = VirtioPciRead8(bus, dev, fn, ptr);
    next = VirtioPciRead8(bus, dev, fn, ptr + 1);
    len = VirtioPciRead8(bus, dev, fn, ptr + 2);
    if (id == VPCI_CAP_VENDOR && len >= 16) {
      cfg_type = VirtioPciRead8(bus, dev, fn, ptr + 3);
      bar_idx = VirtioPciRead8(bus, dev, fn, ptr + 4);
      off = VirtioPciRead32(bus, dev, fn, ptr + 8);
      if (bar_idx < 6 && bars[bar_idx]) {
        if (cfg_type == VPCI_CAP_COMMON_CFG)
          *common = bars[bar_idx] + off;
        else if (cfg_type == VPCI_CAP_NOTIFY_CFG) {
          *notify = bars[bar_idx] + off;
          mult = 1;
          if (len >= 20)
            mult = VirtioPciRead32(bus, dev, fn, ptr + 16);
          if (!mult)
            mult = 1;
          *notify_mult = mult;
        } else if (cfg_type == VPCI_CAP_DEVICE_CFG)
          *devcfg = bars[bar_idx] + off;
        else if (cfg_type == VPCI_CAP_ISR_CFG && isr)
          *isr = bars[bar_idx] + off;
      }
    }
    ptr = next;
  }
  if (!*common || !*notify)
    return -1;
  return 0;
}

I64 VirtioPciParseCaps(I64 bdf, U64 *bars, U8 **common, U8 **notify, U32 *notify_mult, U8 **devcfg)
{
  return VirtioPciParseCapsEx(bdf, bars, common, notify, notify_mult, devcfg, 0);
}
// QEMU virt: PLIC IRQ for this BDF's INTx pin (PCIE_IRQ + swizzle).
I64 VirtioPciIrqNum(I64 bdf)
{
  I64 bus = (bdf >> 16) & 0xFF, dev = (bdf >> 8) & 0xFF, fn = bdf & 0xFF;
  U8 pin;
  I64 slot;
  if (bdf < 0)
    return -1;
  pin = VirtioPciRead8(bus, dev, fn, 0x3D);
  if (!pin)
    pin = 1;
  // pci_swizzle_map_irq / PCI_SLOT(devfn): device number only (not full devfn).
  slot = dev;
  return VPCI_PCIE_IRQ_BASE + ((pin - 1 + slot) % VPCI_PCIE_IRQ_COUNT);
}
// Clear Command.InterruptDisable so INTx can assert (MSI-X must stay off on virt PLIC).
U0 VirtioPciEnableIntx(I64 bdf)
{
  I64 bus = (bdf >> 16) & 0xFF, dev = (bdf >> 8) & 0xFF, fn = bdf & 0xFF;
  U16 cmd = VirtioPciRead16(bus, dev, fn, 0x04);
  VirtioPciWrite16(bus, dev, fn, 0x04, (cmd | 6) & ~VPCI_CMD_INTX_DISABLE);
}
// Read virtio ISR status (clears INTx). Returns bitmask: bit0=queue, bit1=cfg.
I64 VirtioPciIsrAck(U8 *isr)
{
  if (!isr)
    return 0;
  return InU8(isr);
}
// Locate PCI MSI-X capability. Returns 0 and fills outs; -1 if absent.
// table_bar/pba_bar are BAR indices; offs are byte offsets within those BARs.
I64 VirtioPciFindMsix(I64 bdf, I64 *table_bar, I64 *table_off, I64 *pba_bar, I64 *pba_off, I64 *nvec)
{
  I64 bus = (bdf >> 16) & 0xFF, dev = (bdf >> 8) & 0xFF, fn = bdf & 0xFF;
  U8 ptr, id, next;
  U32 msg_ctrl, table, pba;
  ptr = VirtioPciRead8(bus, dev, fn, 0x34);
  while (ptr) {
    id = VirtioPciRead8(bus, dev, fn, ptr);
    next = VirtioPciRead8(bus, dev, fn, ptr + 1);
    if (id == VPCI_CAP_MSIX) {
      msg_ctrl = VirtioPciRead16(bus, dev, fn, ptr + 2);
      table = VirtioPciRead32(bus, dev, fn, ptr + 4);
      pba = VirtioPciRead32(bus, dev, fn, ptr + 8);
      if (nvec)
        *nvec = (msg_ctrl & 0x7FF) + 1;
      if (table_bar)
        *table_bar = table & 7;
      if (table_off)
        *table_off = table & ~7;
      if (pba_bar)
        *pba_bar = pba & 7;
      if (pba_off)
        *pba_off = pba & ~7;
      return 0;
    }
    ptr = next;
  }
  return -1;
}
// Clear MSI-X Enable (poll path). Safe when cap absent.
U0 VirtioPciMsixDisable(I64 bdf)
{
  I64 bus = (bdf >> 16) & 0xFF, dev = (bdf >> 8) & 0xFF, fn = bdf & 0xFF;
  U8 ptr, id, next;
  U16 ctrl;
  ptr = VirtioPciRead8(bus, dev, fn, 0x34);
  while (ptr) {
    id = VirtioPciRead8(bus, dev, fn, ptr);
    next = VirtioPciRead8(bus, dev, fn, ptr + 1);
    if (id == VPCI_CAP_MSIX) {
      ctrl = VirtioPciRead16(bus, dev, fn, ptr + 2);
      VirtioPciWrite16(bus, dev, fn, ptr + 2, ctrl & ~(VPCI_MSIX_ENABLE >> 16));
      return;
    }
    ptr = next;
  }
}
// Enable MSI-X with MaskAll so vectors stay quiet until programmed (AIA/IMSIC later).
I64 VirtioPciMsixEnableMasked(I64 bdf)
{
  I64 bus = (bdf >> 16) & 0xFF, dev = (bdf >> 8) & 0xFF, fn = bdf & 0xFF;
  U8 ptr, id, next;
  U16 ctrl;
  ptr = VirtioPciRead8(bus, dev, fn, 0x34);
  while (ptr) {
    id = VirtioPciRead8(bus, dev, fn, ptr);
    next = VirtioPciRead8(bus, dev, fn, ptr + 1);
    if (id == VPCI_CAP_MSIX) {
      ctrl = VirtioPciRead16(bus, dev, fn, ptr + 2);
      ctrl |= (VPCI_MSIX_ENABLE | VPCI_MSIX_MASKALL) >> 16;
      VirtioPciWrite16(bus, dev, fn, ptr + 2, ctrl);
      return 0;
    }
    ptr = next;
  }
  return -1;
}
// Tell virtio common cfg to ignore MSI-X (poll / INTx). Call after FEATURES_OK.
U0 VirtioPciSetNoMsix(U8 *common)
{
  if (!common)
    return;
  OutU16(common + VPCI_COMMON_MSIX_CFG, VPCI_MSIX_NO_VECTOR);
}

U0 VirtioPciQueueNoMsix(U8 *common)
{
  if (!common)
    return;
  OutU16(common + VPCI_COMMON_Q_MSIX, VPCI_MSIX_NO_VECTOR);
}
#endif
