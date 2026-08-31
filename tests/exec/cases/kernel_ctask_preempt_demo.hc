// Authentic timer-driven PREEMPTION of real CTasks, TempleOS-style (Sched.HC IntSwapTask): two real
// CTasks that never call Yield are forced to share the CPU by the machine-timer interrupt. The trap
// handler saves the interrupted caller-saved regs + mepc, then calls the kernel's own Yield() — which
// walks Fs->next_task and context-switches on the real CTask.rsp — then restores and mrets. Only the
// low-level pieces are ported to RISC-V; the task model (Fs, CTask, next_task, task_flags) is real.
#include "/Kernel/Kernel_RV.PRJ"
CHeapCtrl *the_heap = 0x82000000;
U8 *heap_next = 0x82000400, *heap_end = 0x86000000;
U8 *MAlloc(I64 size, CTask *mem_task = NULL)
{
  I64 need = (size + offset(CMemUsed.start) + 15) & (~15);
  CMemUnused *f = the_heap->malloc_free_lst, *prev = NULL;
  while (f && f->size < need) {
    prev = f;
    f = f->next;
  }
  U8 *c;
  I64 us;
  if (f) {
    if (prev)
      prev->next = f->next;
    else
      the_heap->malloc_free_lst = f->next;
    c = f;
    us = f->size;
  } else {
    if (heap_next + need > heap_end)
      return NULL;
    c = heap_next;
    heap_next += need;
    us = need;
  }
  CMemUsed *u = c;
  u->hc = the_heap;
  u->size = us;
  return c + offset(CMemUsed.start);
}
#define MEM_UART 0x10000000
U0 Free(U8 *p)
{
  if (!p)
    return;
  CMemUsed *u = p - offset(CMemUsed.start);
  CMemUnused *fu = u;
  fu->size = u->size;
  fu->next = the_heap->malloc_free_lst;
  the_heap->malloc_free_lst = fu;
}

U0 UC(I64 c)
{
  U8 *u = MEM_UART;
  *u = c;
}
I64 ca = 0, cb = 0;
U0 taskA()
{
  while (ca < 5) {
    UC('A');
    ca++;
    I64 s = 0;
    while (s < 3000000)
      s++;
  }
  Bts(&Fs->task_flags, TASKf_KILL_TASK);
  while (TRUE) {
  }
}

U0 taskB()
{
  while (cb < 5) {
    UC('B');
    cb++;
    I64 s = 0;
    while (s < 3000000)
      s++;
  }
  Bts(&Fs->task_flags, TASKf_KILL_TASK);
  while (TRUE) {
  }
}

CTask *KSpawn(U0 (*entry)())
{
  CTask *t = CAlloc(sizeof(CTask), NULL);
  t->addr = t;
  t->task_flags = 0;
  U8 *stk = CAlloc(16384, NULL);
  I64 top = (stk + 16384) & (~15);
  I64 *fr = top - 104;
  I64 i;
  for (i = 0; i < 12; i++)
    fr[i] = 0;
  fr[12] = entry;
  t->rsp = fr;
  CTask *c = Fs;
  t->next_task = c->next_task;
  t->last_task = c;
  c->next_task->last_task = t;
  c->next_task = t;
  return t;
}

I64 main()
{
  RVKernelInit();
  CTask *adam = 0x87000000;
  MemSet(adam, 0, sizeof(CTask));
  adam->addr = adam;
  adam->next_task = adam;
  adam->last_task = adam;
  Fs = adam;
  RVYieldInit(&Fs);
  KSpawn(&taskA);
  KSpawn(&taskB);
  Print("preempting real CTasks (no yield in tasks): ");
  RVPreemptReal(400000);
  // timer preempts every ~400k cycles, via the kernel's Yield()
  while (ca < 5 || cb < 5) {
    I64 s = 0;
    while (s < 500000)
      s++;
  }
  Print("\ndone A=%d B=%d (preempted via kernel Yield)\n", ca, cb);
  return 0;
}
