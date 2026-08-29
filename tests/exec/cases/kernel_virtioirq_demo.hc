// The virtio-blk completion interrupt, serviced through the PLIC. This is the correctness half of
// interrupt-driven disk I/O: a used-ring update raises a machine external interrupt (PLIC IRQ = the
// device's slot, 8 for 0x10008000), and HolyServiceExternal acknowledges the device's InterruptStatus
// so the line doesn't re-fire forever. RVTrapInit installs the vector + global MIE; VirtioBlkIrqInit
// routes the device IRQ and sets MEIE. The requests here still complete by polling -- this test only
// proves the interrupt fires and is acknowledged cleanly (no storm), via RVVirtioIrqs().
#include "/Kernel/Kernel_RV.PRJ"
U0 Sh(U8 *s){ U8 *u=0x10000000; while(*s)*u=*s++; }
I64 main()
{
  U8 *buf=0x88030000;
  I64 i;
  RVTrapInit();
  if (VirtioBlkInit()) { Sh("no virtio-blk device\n"); return 0; }
  VirtioBlkIrqInit();
  for (i=0;i<512;i++) buf[i]=0x77;
  VirtioBlkWrite(20,buf);
  for (i=0;i<512;i++) buf[i]=0;
  VirtioBlkRead(20,buf);
  I64 irqs=RVVirtioIrqs();
  if (irqs>0 && buf[0]==0x77) Sh("virtio IRQ serviced OK\n");
  else Sh("virtio IRQ FAILED\n");
  return irqs;
}
