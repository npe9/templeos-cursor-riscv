// Authentic task switching using TempleOS's OWN Yield(): real CTasks (real sizeof, linked through
// the real next_task/last_task list), Fs as the current-task pointer, and the kernel's own Yield()
// intrinsic — which now walks Fs->next_task, skips TASKf_KILL_TASK tasks, and context-switches on
// the real CTask.rsp, exactly like Sched.HC _YIELD. RVYieldInit(&Fs) tells the runtime where Fs is;
// only the low-level register save/restore (RVCtxSw) is the RISC-V port. So kernel code that yields
// (scheduler waits, PutS's scroll-lock wait) cooperates on the real task list.
#include "/Kernel/Kernel_RV.PRJ"
I64 done_count = 0;
CTask *KSpawn(U0 (*entry)())
{
  CTask *t = CAlloc(sizeof(CTask), NULL);
  t->addr = t;
  t->task_flags = 0;
  U8 *stk = CAlloc(16384, NULL);
  I64 top = (stk + 16384) & (~15);
  I64 *frame = top - 104;
  I64 i;
  for (i = 0; i < 12; i++)
    frame[i] = 0;
  frame[12] = entry;
  t->rsp = frame;
  CTask *c = Fs;
  t->next_task = c->next_task;
  t->last_task = c;
  c->next_task->last_task = t;
  c->next_task = t;
  return t;
}

U0 taskA()
{
  I64 k;
  for (k = 0; k < 3; k++) {
    Print("A%d ", k);
    Yield();
  }
  Print("[A done] ");
  done_count++;
  Bts(&Fs->task_flags, TASKf_KILL_TASK);
  Yield();
}

U0 taskB()
{
  I64 k;
  for (k = 0; k < 3; k++) {
    Print("B%d ", k);
    Yield();
  }
  Print("[B done] ");
  done_count++;
  Bts(&Fs->task_flags, TASKf_KILL_TASK);
  Yield();
}

I64 main()
{
  RVKernelInit();
  CTask *adam = CAlloc(sizeof(CTask), NULL);
  adam->addr = adam;
  adam->task_flags = 0;
  adam->next_task = adam;
  adam->last_task = adam;
  Fs = adam;
  RVYieldInit(&Fs);
  // wire the kernel's Yield() to the real CTask list
  KSpawn(&taskA);
  KSpawn(&taskB);
  Print("start: ");
  while (done_count < 2)
    Yield();
  // the KERNEL's own Yield() intrinsic
  Print("\nall done via the kernel's own Yield()\n");
  return 0;
}
