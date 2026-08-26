// Persistent storage on RISC-V via a virtio-blk driver (legacy virtio-mmio). RVBlkInit finds the
// block device among the virtio-mmio slots and sets up its virtqueue; RVBlkWrite/RVBlkRead move
// 512-byte sectors through a 3-descriptor request (header + data + status). Here we write a marker
// to a sector and read it straight back, verifying the round trip — and, because it's a real disk
// image, the bytes persist after QEMU exits.
#include "/Kernel/Kernel_RV.PRJ"
I64 main(){
  RVKernelInit();
  if (RVBlkInit()) { Print("no block device\n"); return 1; }
  U8 *wb=CAlloc(512,NULL); I64 i; for (i=0;i<512;i++) wb[i]=0;
  StrCpy(wb, "RISCV-BLOCK-OK");
  wb[200]=0x42; wb[511]=0x99;
  I64 ws=RVBlkWrite(5, wb);
  U8 *rb=CAlloc(512,NULL);
  I64 rs=RVBlkRead(5, rb);
  I64 verified = (rs==0) * (StrCmp(rb,"RISCV-BLOCK-OK")==0) * (rb[200]==0x42) * (rb[511]==0x99);
  Print("blk write=%d read=%d readback='%s' verified=%d\n", ws, rs, rb, verified);
  return 0;
}
