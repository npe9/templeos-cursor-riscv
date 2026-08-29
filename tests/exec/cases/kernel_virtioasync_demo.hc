// Interrupt-driven async disk I/O: a background task keeps running while another task waits on the
// virtio-blk disk. With virtio_blk_wait_yield set, VirtioBlkReq yields to the scheduler between
// notify and completion instead of busy-polling, so the kernel does other work while I/O is
// outstanding (QEMU's virtio-blk completes asynchronously, leaving a real window). The completion
// interrupt (serviced + acknowledged by HolyServiceExternal) is what wakes an idle hart if every task
// blocks. Proof: the background counter advances by a lot during 64 reads here, but by ZERO on the
// polling path (see run_kernel_virtioasync_smoke.sh's contrast) -- the yield-wait is what enables it.
#include "/Kernel/Kernel_RV.PRJ"
U0 Sh(U8 *s){ U8 *u=0x10000000; while(*s)*u=*s++; }
I64 bg_counter=0;
Bool bg_stop=FALSE;
U0 BgTask(){ while(!bg_stop){ bg_counter++; Yield; } Bts(&Fs->task_flags,TASKf_KILL_TASK); Yield; }
I64 main()
{
  CTask *adam=0x86900000; MemSet(adam,0,sizeof(CTask)); Fs=adam; adam_task=adam;
  MemSet(the_heap,0,sizeof(CHeapCtrl)); heap_next=0x82000400; heap_end=0x86000000;
  CBlkPool *bp=0x86800000; BlkPoolInit(bp,0x2000); sys_code_bp=bp;
  CHeapCtrl *ah=HeapCtrlInit(NULL,NULL,bp); adam->code_heap=ah; adam->data_heap=ah;
  MemSet(SYS_FIXED_AREA,0,8192); TaskInit(adam,0);
  CCPU *gs=0x86A00000; MemSet(gs,0,sizeof(CCPU)); gs->seth_task=adam; adam->gs=gs; Gs=gs;
  RVYieldInit(&Fs); RVKernelInit();
  RVTrapInit();
  if (VirtioBlkInit()) { Sh("no virtio-blk device\n"); return 0; }
  VirtioBlkIrqInit();
  virtio_blk_wait_yield=TRUE;                 // yield during I/O waits
  U8 *buf=0x88030000;
  CTask *t=RVKSpawn(&BgTask,"Bg",adam);
  I64 c0=bg_counter, i, errs=0;
  for (i=0;i<64;i++) if (VirtioBlkRead(30,buf)) errs++;
  I64 adv=bg_counter-c0;
  bg_stop=TRUE;
  while (!(t->task_flags & (1<<TASKf_KILL_TASK))) Yield;
  if (adv>50 && errs==0 && RVVirtioIrqs()>0) Sh("async virtio I/O overlaps background task OK\n");
  else Sh("async virtio FAILED\n");
  return adv;
}
