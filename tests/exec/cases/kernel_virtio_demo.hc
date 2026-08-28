// The kernel's OWN native RISC-V virtio-blk driver (Kernel/BlkDev/DskVirtioRV.HC) driving a real disk
// on the QEMU virt machine over legacy virtio-mmio -- the RISC-V translation of the x86 ATA driver.
// The VM is launched with a 256-sector raw disk image whose sector 5 is pre-filled with 0xCC. The
// demo brings the device up (legacy handshake + virtqueue), reads sector 5 and checks it, then writes
// a pattern to sector 10 and reads it back -- exercising the full descriptor-chain request path.
#include "/Kernel/Kernel_RV.PRJ"
U0 Sh(U8 *s){ U8 *u=0x10000000; while(*s)*u=*s++; }
I64 main()
{
  U8 *buf=0x88030000;
  I64 i, ok=0;
  Sh("virtio-blk demo: kernel's own driver over legacy virtio-mmio\n");
  if (VirtioBlkInit()) { Sh("no virtio-blk device\n"); return 0; }
  Sh("device up\n");
  if (VirtioBlkRead(5, buf)==0 && buf[0]==0xCC && buf[511]==0xCC) { Sh("read sector 5 = 0xCC OK\n"); ok++; }
  for (i=0; i<512; i++) buf[i]=0x5A;
  if (VirtioBlkWrite(10, buf)==0) {
    for (i=0; i<512; i++) buf[i]=0;
    if (VirtioBlkRead(10, buf)==0 && buf[0]==0x5A && buf[511]==0x5A) { Sh("write+readback sector 10 OK\n"); ok++; }
  }
  if (ok==2) Sh("virtio-blk read-write OK\n"); else Sh("virtio-blk FAILED\n");
  return ok;
}
