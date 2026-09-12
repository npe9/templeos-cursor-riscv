// Thin-loader stubs: virtio-pci blk fallback unused on QEMU virt MMIO smoke.
// SoftCall + RVRedSeaRawFileRead use virtio-mmio only — drop VirtioPci.HC embed.
#ifndef VIRTIO_PCI_BLK_STUBS_RV_HC
#define VIRTIO_PCI_BLK_STUBS_RV_HC
I64 VirtioPciBlkPresent()
{
  return 0;
}

I64 VirtioPciBlkInit()
{
  return -1;
}

I64 VirtioPciBlkReq(I64 type, I64 lba, U8 *buf)
{
  no_warn type;
  no_warn lba;
  no_warn buf;
  return -1;
}

I64 VirtioPciBlkCapacity()
{
  return 0;
}

I64 VirtioPciBlkReadLba(U8 *buf, I64 lba)
{
  no_warn buf;
  no_warn lba;
  return -1;
}

I64 VirtioPciBlkWriteLba(U8 *buf, I64 lba)
{
  no_warn buf;
  no_warn lba;
  return -1;
}

I64 VirtioPciBlkReadSector0(U8 *buf)
{
  no_warn buf;
  return -1;
}

I64 VirtioPciBlkIrqNum()
{
  return -1;
}

U0 VirtioPciBlkIrqAck()
{
}

I64 VirtioPciBlkIrqInit()
{
  return -1;
}

I64 VirtioPciBlkIrqService()
{
  return 0;
}
#endif
