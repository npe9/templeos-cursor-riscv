// TempleOS's OWN Spawn() creating and running a real CTask on RISC-V. Everything here is the real
// kernel code: BlkPoolInit + HeapCtrlInit bring up a real block pool + heap; a faithful MAlloc/Free
// (overriding the runtime stub) backs the kernel's CAlloc; the REAL Spawn() -> TaskInit() allocates
// a real CTask (task_num, hash table, stack, FPU area, window fields); and the kernel's own Yield()
// context-switches into it. The only RISC-V ports: MAlloc/Free, the low-level switch (RVCtxSw), and
// two adaptations of x86-isms — SYS_FIXED_AREA (an x86 phys address) pointed at real RAM, and the
// new task's initial stack frame re-seeded for the RISC-V calling convention after Spawn sets it up.
#define SYS_FIXED_AREA 0x87000000
#include "/Kernel/Kernel_RV.PRJ"
CHeapCtrl *the_heap = 0x82000000;
U8 *heap_next = 0x82000400;
U8 *heap_end = 0x86000000;
U8 *MAlloc(I64 size, CTask *mem_task = NULL)
{
  I64 need = (size + offset(CMemUsed.start) + 15) & (~15);
  CMemUnused *f = the_heap->malloc_free_lst, *prev = NULL;
  while (f && f->size < need) {
    prev = f;
    f = f->next;
  }
  U8 *chunk;
  I64 usize;
  if (f) {
    if (prev)
      prev->next = f->next;
    else
      the_heap->malloc_free_lst = f->next;
    chunk = f;
    usize = f->size;
  } else {
    if (heap_next + need > heap_end)
      return NULL;
    chunk = heap_next;
    heap_next += need;
    usize = need;
  }
  CMemUsed *u = chunk;
  u->hc = the_heap;
  u->size = usize;
  the_heap->used_u8s += usize;
  return chunk + offset(CMemUsed.start);
}

U0 Free(U8 *ptr)
{
  if (!ptr)
    return;
  CMemUsed *u = ptr - offset(CMemUsed.start);
  CMemUnused *fu = u;
  fu->size = u->size;
  fu->next = the_heap->malloc_free_lst;
  the_heap->malloc_free_lst = fu;
}

U8 *ACAlloc(I64 size)
{
  U8 *r = MAlloc(size, NULL);
  MemSet(r, 0, size);
  return r;
}
// adam-heap CAlloc used by HeapCtrlInit
I64 ran = 0;
U0 taskA()
{
  ran = 1;
  Print("  >>> real-spawned CTask is running! (task_num set by TaskInit)\n");
  Bts(&Fs->task_flags, TASKf_KILL_TASK);
  Yield();
}

I64 main()
{
  RVKernelInit();
  MemSet(0x87000000, 0, 8192);
  CBlkPool *bp = 0x83000000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  CHeapCtrl *ah = HeapCtrlInit(NULL, NULL, bp);
  CTask *adam = 0x82008000;
  MemSet(adam, 0, sizeof(CTask));
  adam->addr = adam;
  adam->code_heap = ah;
  adam->data_heap = ah;
  adam->next_task = adam;
  adam->last_task = adam;
  CCPU *gs = 0x82009000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Fs = adam;
  Gs = gs;
  adam_task = adam;
  RVYieldInit(&Fs);
  Print("calling the real Spawn()...\n");
  CTask *t = Spawn(&taskA, NULL, "tA", -1, adam, 0, 0);
  Print("real Spawn -> task=0x%X task_num=%d rip_set=%d\n", t, t->task_num, t->rip != 0);
  // Spawn() plants HolyRVCtxSw via RVKFixSpawnFrame (no second fixup).
  // link the real task into adam's circular list
  t->next_task = adam->next_task;
  t->last_task = adam;
  adam->next_task->last_task = t;
  adam->next_task = t;
  Print("yielding to the real task...\n");
  while (!ran)
    Yield();
  Print("back in adam; real Spawn+Yield worked=%d\n", ran);
  return 0;
}
