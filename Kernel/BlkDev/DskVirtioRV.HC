// Native RISC-V legacy (v1) virtio-mmio block driver with virtio-pci fallback.
// Addresses come from Kernel/RVAutoConf.HH (CONFIG_VIRTIO_MMIO_* / CONFIG_PLIC_* /
// CONFIG_VIRTIO_DRV_RAM_BASE). QEMU virt exposes N generic virtio-mmio slots
// (MagicValue 0x74726976, Version 1 = legacy); a block device (DeviceID 2) appears
// with `-drive ... -device virtio-blk-device`. Prefer MMIO; fall back to VirtioPciBlk
// when no mmio slot (virtio-blk-pci), same pattern as VirtioNet / Virtio9p.
// Registers are 32-bit MMIO via InU32/OutU32.
//
// Split virtqueue (size 8) lives in a fixed 4K-aligned RAM region: descriptor table + avail ring in
// the first page, used ring in the second (QueueAlign = 4096). Identity-mapped bare metal, so the
// buffer's virtual address is its physical address and descriptors point straight at caller buffers.
#ifndef CONFIG_VIRTIO_MMIO_BASE
#define CONFIG_VIRTIO_MMIO_BASE 0x10001000
#endif
#ifndef CONFIG_VIRTIO_MMIO_STRIDE
#define CONFIG_VIRTIO_MMIO_STRIDE 0x1000
#endif
#ifndef CONFIG_VIRTIO_MMIO_COUNT
#define CONFIG_VIRTIO_MMIO_COUNT 8
#endif
#ifndef CONFIG_VIRTIO_MMIO_IRQ_BASE
#define CONFIG_VIRTIO_MMIO_IRQ_BASE 0x10000000
#endif
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
#ifndef CONFIG_PLIC_BASE
#define CONFIG_PLIC_BASE 0x0C000000
#endif
#ifndef CONFIG_PLIC_ENABLE_OFF
#define CONFIG_PLIC_ENABLE_OFF 0x2000
#endif
#ifndef CONFIG_PLIC_THRESHOLD_OFF
#define CONFIG_PLIC_THRESHOLD_OFF 0x200000
#endif
#define VIRTIO_MMIO_LO    CONFIG_VIRTIO_MMIO_BASE
#define VIRTIO_MMIO_HI    (CONFIG_VIRTIO_MMIO_BASE+(CONFIG_VIRTIO_MMIO_COUNT-1)*CONFIG_VIRTIO_MMIO_STRIDE)
#define VIRTIO_MAGIC      0x74726976
#define VIRTIO_ID_BLOCK   2
// Legacy virtio-mmio register offsets.
#define VMR_MAGIC         0x00
#define VMR_DEVICE_ID     0x08
#define VMR_DRIVER_FEAT   0x20
#define VMR_DRIVER_FEATSEL 0x24
#define VMR_GUEST_PGSZ    0x28
#define VMR_QUEUE_SEL     0x30
#define VMR_QUEUE_NUM     0x38
#define VMR_QUEUE_ALIGN   0x3c
#define VMR_QUEUE_PFN     0x40
#define VMR_QUEUE_NOTIFY  0x50
#define VMR_STATUS        0x70
#define VSTAT_ACK         1
#define VSTAT_DRIVER      2
#define VSTAT_DRIVER_OK   4
#define VBLK_QSZ          8
#define VDESC_F_NEXT      1
#define VDESC_F_WRITE     2
#define VBLK_T_IN         0     // read (device -> memory)
#define VBLK_T_OUT        1     // write (memory -> device)
// Fixed driver RAM (needs DRAM covering CONFIG_VIRTIO_DRV_RAM_BASE; virt -m >=256M).
#define VBLK_VQ           CONFIG_VIRTIO_DRV_RAM_BASE
#define VBLK_HDR          (CONFIG_VIRTIO_DRV_RAM_BASE+0x20000)   // 16-byte request header
#define VBLK_STAT         (CONFIG_VIRTIO_DRV_RAM_BASE+0x21000)   // 1-byte status
// Split-virtqueue structures (queue size 8). Using real structs, not raw *(U32*) casts: a cast-pointer
// store can emit the wrong width in this codegen (a U32 len came out 0), whereas struct member stores
// get correct per-field widths.
class CVioDesc
{
  U64 addr;
  U32 len;
  U16 flags;
  U16 next;
};
// 16 bytes
class CVioAvail
{
  U16 flags;
  U16 idx;
  U16 ring[VBLK_QSZ];
  U16 used_ev;
};

class CVioUsedElem
{
  U32 id;
  U32 len;
};

class CVioUsed
{
  U16 flags;
  U16 idx;
  CVioUsedElem ring[VBLK_QSZ];
  U16 avail_ev;
};

class CVioBlkReq
{
  U32 type;
  U32 rsvd;
  U64 sector;
};
// virtio-blk request header
#define VBLK_KIND_NONE  0
#define VBLK_KIND_MMIO  1
#define VBLK_KIND_PCI   2
I64 virtio_blk_base;
// device MMIO base, 0 until VirtioBlkInit succeeds (mmio path)
I64 virtio_blk_kind;
// VBLK_KIND_* after VirtioBlkInit
I64 virtio_blk_wait_yield;
// if set, VirtioBlkReq yields to the scheduler while the device works
// (needs a running scheduler); else it polls the used ring inline
// Scan the virtio-mmio slots for a block device; return its base or 0.
I64 VirtioBlkFind()
{
  I64 slot;
  if (!RVVirtioMmioEnabled())
    return 0;
  for (slot = VIRTIO_MMIO_LO; slot <= VIRTIO_MMIO_HI; slot += CONFIG_VIRTIO_MMIO_STRIDE) {
    U8 *r = slot;
    if (InU32(r + VMR_MAGIC) == VIRTIO_MAGIC && InU32(r + VMR_DEVICE_ID) == VIRTIO_ID_BLOCK)
      return slot;
  }
  return 0;
}
// Bring the device up (legacy handshake) and publish the virtqueue. Prefer MMIO;
// fall back to VirtioPciBlk when no mmio slot. Returns 0 on success, -1 if absent.
I64 VirtioBlkInit()
{
  U8 *r;
  virtio_blk_kind = VBLK_KIND_NONE;
  virtio_blk_base = VirtioBlkFind();
  if (!virtio_blk_base) {
    if (VirtioPciBlkInit())
      return -1;
    virtio_blk_kind = VBLK_KIND_PCI;
    return 0;
  }
  r = virtio_blk_base;
  MemSet(VBLK_VQ, 0, 8192);
  OutU32(r + VMR_STATUS, 0);
  // reset
  OutU32(r + VMR_STATUS, VSTAT_ACK);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER);
  OutU32(r + VMR_DRIVER_FEATSEL, 0);
  OutU32(r + VMR_DRIVER_FEAT, 0);
  // negotiate no optional features
  OutU32(r + VMR_GUEST_PGSZ, 4096);
  // legacy: guest page size
  OutU32(r + VMR_QUEUE_SEL, 0);
  OutU32(r + VMR_QUEUE_NUM, VBLK_QSZ);
  OutU32(r + VMR_QUEUE_ALIGN, 4096);
  OutU32(r + VMR_QUEUE_PFN, VBLK_VQ >> 12);
  // legacy: single PFN for the whole queue
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER | VSTAT_DRIVER_OK);
  virtio_blk_kind = VBLK_KIND_MMIO;
  return 0;
}
// One block request. type: VBLK_T_IN (read) / VBLK_T_OUT (write). buf is 512 bytes. Returns the
// virtio status byte (0 = VIRTIO_BLK_S_OK). Descriptor chain: [header ro][data rw|ro][status wo].
I64 VirtioBlkReq(I64 type, I64 sector, U8 *buf)
{
  U8 *r = virtio_blk_base;
  CVioDesc *desc = VBLK_VQ;
  CVioAvail *avail = VBLK_VQ + 128;
  CVioUsed *used = VBLK_VQ + 4096;
  CVioBlkReq *hdr = VBLK_HDR;
  U8 *statp = VBLK_STAT;
  U16 uidx0;
  I64 spin;
  if (virtio_blk_kind == VBLK_KIND_PCI)
    return VirtioPciBlkReq(type, sector, buf);
  if (!virtio_blk_base)
    return -1;
  hdr->type = type;
  hdr->rsvd = 0;
  hdr->sector = sector;
  *statp = 0xFF;
  // desc[0]: request header, device-readable, chain to data
  desc[0].addr = VBLK_HDR;
  desc[0].len = 16;
  desc[0].flags = VDESC_F_NEXT;
  desc[0].next = 1;
  // desc[1]: data buffer; on a read the device WRITES it, on a write it only reads it
  desc[1].addr = buf;
  desc[1].len = 512;
  if (type == VBLK_T_IN)
    desc[1].flags = VDESC_F_NEXT | VDESC_F_WRITE;
  else
    desc[1].flags = VDESC_F_NEXT;
  desc[1].next = 2;
  // desc[2]: status byte, device-writable, end of chain
  desc[2].addr = VBLK_STAT;
  desc[2].len = 1;
  desc[2].flags = VDESC_F_WRITE;
  desc[2].next = 0;
  // publish head desc 0 into the avail ring, then bump avail.idx
  uidx0 = used->idx;
  avail->ring[0] = 0;
  avail->idx = avail->idx + 1;
  OutU32(r + VMR_QUEUE_NOTIFY, 0);
  // kick queue 0
  if (virtio_blk_wait_yield) {
    // async: let other tasks run while the device works
    while (used->idx == uidx0)
      Yield;
    // wakes the idle task if everything else blocks (VirtioBlkIrqInit)
  } else {
    for (spin = 0; spin < 200000000; spin++)
      if (used->idx != uidx0)
        break;
  }
  return *statp;
}

I64 VirtioBlkRead(I64 sector, U8 *buf)
{
  return VirtioBlkReq(VBLK_T_IN, sector, buf);
}

I64 VirtioBlkWrite(I64 sector, U8 *buf)
{
  return VirtioBlkReq(VBLK_T_OUT, sector, buf);
}
// Disk capacity in 512-byte sectors (virtio-blk config space, legacy offset 0x100).
I64 VirtioBlkCapacity()
{
  U8 *r = virtio_blk_base;
  U64 lo, hi;
  if (virtio_blk_kind == VBLK_KIND_PCI)
    return VirtioPciBlkCapacity();
  if (!virtio_blk_base)
    return 0;
  lo = InU32(r + 0x100);
  hi = InU32(r + 0x104);
  return lo | (hi << 32);
}
#ifndef RV_THIN_LOADER
// Mount the virtio-blk device as a RedSea drive (BDT_VIRTIO) -- the RISC-V translation of the x86
// MountIDEAuto/RVMountRAMDisk path, but backed by a REAL disk: RedSea's BlkRead/BlkWrite now dispatch
// to VirtioBlkRead/VirtioBlkWrite. BlkDevAdd formats a blank disk (RedSeaFmt) or mounts an existing one.
U0 RVMountVirtioDisk(U8 drv_let)
{
  CBlkDev *bd;
  I64 cap;
  if (!blkdev.blkdevs) {
    blkdev.blkdevs = CAlloc(sizeof(CBlkDev) * BLKDEVS_NUM);
    blkdev.drvs = CAlloc(sizeof(CDrv) * DRVS_NUM);
    I64 i;
    for (i = 0; i < DRVS_NUM; i++)
      blkdev.let_to_drv[i] = &blkdev.drvs[i];
  }
  if (VirtioBlkInit())
    return;
  // no device -> leave the drive unmounted
  cap = VirtioBlkCapacity();
  bd = BlkDevNextFreeSlot(drv_let, Let2BlkDevType(drv_let));
  // pass the letter's native type, then
  bd->type = BDT_VIRTIO;
  // override to virtio (reuses the RAM slot setup)
  bd->flags &= ~BDF_READ_CACHE;
  bd->unit = 0;
  bd->max_blk = cap - 1;
  BlkDevAdd(bd, I64_MIN, FALSE, TRUE);
  Drv(drv_let);
}
// Route the virtio-blk completion interrupt through the PLIC + mie.MEIE.
// MMIO: IRQ = (base - CONFIG_VIRTIO_MMIO_IRQ_BASE) >> 12. PCI: VirtioPciBlkIrq*.
// Requires RVTrapInit first. AIA MSI-X→IMSIC stays deferred on virt PLIC.
U0 VirtioBlkIrqInit()
{
  I64 irq;
  if (virtio_blk_kind == VBLK_KIND_PCI) {
    VirtioPciBlkIrqInit();
    return;
  }
  if (virtio_blk_kind != VBLK_KIND_MMIO || !virtio_blk_base)
    return;
  irq = (virtio_blk_base - CONFIG_VIRTIO_MMIO_IRQ_BASE) >> 12;
  OutU32(CONFIG_PLIC_BASE + irq * 4, 1);
  // PLIC priority[irq] = 1
  OutU32(CONFIG_PLIC_BASE + CONFIG_PLIC_ENABLE_OFF, InU32(CONFIG_PLIC_BASE + CONFIG_PLIC_ENABLE_OFF) | (1 << irq));
  // enable[irq] context 0
  OutU32(CONFIG_PLIC_BASE + CONFIG_PLIC_THRESHOLD_OFF, 0);
  // threshold 0
  RvSetMEIE();
  // mie.MEIE
}
/* SoftCall ENTER wrappers for Kernel.BIN mount/BlkDev ownership (G9).
 * Remount of an already-mounted letter hangs (BlkDevNextFreeSlot+BlkDevAdd);
 * if virtio RedSea is up, re-validate via BlkRead; else call RVMountVirtioDisk. */
I64 RVVirtioBlkCapacity()
{
  return VirtioBlkCapacity();
}

I64 RVVirtioBlkRead(I64 sector, U8 *buf)
{
  return VirtioBlkRead(sector, buf);
}

Bool RVRedSeaValidate(U8 drv_let)
{
  return RedSeaValidate(drv_let);
}

I64 RVRVMountVirtioDisk(U8 drv_let)
{
  if (Fs && Fs->cur_dv && Fs->cur_dv->dv_signature == DRV_SIGNATURE_VAL &&
      Fs->cur_dv->bd && Fs->cur_dv->bd->type == BDT_VIRTIO) {
    if (RedSeaValidate(drv_let))
      return 0x4B4D;
    // 'KM'
    return -1;
  }
  RVMountVirtioDisk(drv_let);
  if (Fs && Fs->cur_dv && Fs->cur_dv->dv_signature == DRV_SIGNATURE_VAL &&
      RedSeaValidate(drv_let))
    return 0x4B4D;
  return -2;
}
#endif
// RVRedSeaRawFileRead lives in BlkDev/RVRedSeaRaw.HC (thin + full).
