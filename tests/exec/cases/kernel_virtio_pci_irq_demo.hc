// Virtio-PCI blk INTx delivered via PLIC + trap MEIE (HolyServiceExternal ISR ACK).
// Mirrors kernel_virtioirq_demo but attaches virtio-blk-pci only.
#include "/Kernel/Kernel_RV.PRJ"
#define MEM_UART 0x10000000
U0 Sh(U8 *s)
{
  U8 *u = MEM_UART;
  while (*s)
    *u = *s++;
}

I64 main()
{
  U8 *buf = 0x88030000;
  I64 i, irqs;
  RVTrapInit();
  if (VirtioBlkInit()) {
    Sh("no virtio-blk device\n");
    return 0;
  }
  if (virtio_blk_kind != VBLK_KIND_PCI) {
    Sh("expected pci blk\n");
    return 0;
  }
  VirtioBlkIrqInit();
  for (i = 0; i < 512; i++)
    buf[i] = 0x77;
  VirtioBlkWrite(20, buf);
  for (i = 0; i < 512; i++)
    buf[i] = 0;
  VirtioBlkRead(20, buf);
  irqs = RVVirtioIrqs();
  if (irqs > 0 && buf[0] == 0x77)
    Sh("virtio-pci IRQ serviced OK\n");
  else
    Sh("virtio-pci IRQ FAILED\n");
  return irqs;
}
