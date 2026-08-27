// Authentic cooperative SLEEP on real CTasks, TempleOS-style (Sched.HC RESTORE_RSI_TASK wake_jiffy
// check + SleepUntil's Fs->wake_jiffy=... ; Yield()). Tasks put themselves to sleep by setting the
// real CTask.wake_jiffy field and yielding; the kernel's own Yield() (HolyYield) walks Fs->next_task
// and skips any task whose wake_jiffy has not yet been reached by the jiffy clock, running whoever
// is ready. When EVERY task is asleep the scheduler idles (masking interrupts and polling mtime so
// the jiffy clock still advances) until the earliest sleeper wakes — TempleOS's idle-task loop.
// The jiffy clock is derived from the machine timer (mtime, 10 MHz on QEMU virt): 1 jiffy = 1 ms.
// Only the low-level pieces are ported; the task model (Fs, CTask, next_task, task_flags,
// wake_jiffy) and the sleep mechanism are the kernel's own. Distinct from kernel_sleep_demo.hc,
// which sleeps on the Phase-1 parallel RVSleep runtime rather than real CTasks.
#include "/Kernel/Kernel_RV.PRJ"
CHeapCtrl *the_heap=0x82000000; U8 *heap_next=0x82000400,*heap_end=0x86000000;
U8 *MAlloc(I64 size,CTask *mem_task=NULL){ I64 need=(size+offset(CMemUsed.start)+15)&(~15); CMemUnused *f=the_heap->malloc_free_lst,*prev=NULL; while(f&&f->size<need){prev=f;f=f->next;} U8 *c; I64 us; if(f){if(prev)prev->next=f->next;else the_heap->malloc_free_lst=f->next;c=f;us=f->size;}else{if(heap_next+need>heap_end)return NULL;c=heap_next;heap_next+=need;us=need;} CMemUsed *u=c;u->hc=the_heap;u->size=us; return c+offset(CMemUsed.start); }
U0 Free(U8 *p){ if(!p)return; CMemUsed *u=p-offset(CMemUsed.start); CMemUnused *fu=u; fu->size=u->size; fu->next=the_heap->malloc_free_lst; the_heap->malloc_free_lst=fu; }
U0 UC(I64 c){ U8 *u=0x10000000; *u=c; }
// Sleep exactly as SleepUntil does: set the real CTask.wake_jiffy, then Yield to the scheduler,
// which will not return here until the jiffy clock passes wake_jiffy.
U0 KSleep(I64 ms){ Fs->wake_jiffy=RVJiffies()+ms; Yield(); }
CTask *KSpawn(U0 (*entry)()){ CTask *t=CAlloc(sizeof(CTask),NULL); t->addr=t; t->task_flags=0; U8 *stk=CAlloc(16384,NULL); I64 top=(stk+16384)&(~15); I64 *fr=top-104; I64 i; for(i=0;i<12;i++)fr[i]=0; fr[12]=entry; t->rsp=fr; CTask *c=Fs; t->next_task=c->next_task; t->last_task=c; c->next_task->last_task=t; c->next_task=t; return t; }
I64 ca=0,cb=0;
// Task A sleeps 40 ms up front, so B runs alone during that window, then A prints 3 times.
U0 taskA(){ KSleep(40); while(ca<3){ UC('A'); ca++; KSleep(20); } Bts(&Fs->task_flags,TASKf_KILL_TASK); Yield(); }
U0 taskB(){ while(cb<3){ UC('B'); cb++; KSleep(20); } Bts(&Fs->task_flags,TASKf_KILL_TASK); Yield(); }
I64 main(){
  RVKernelInit();
  CTask *adam=0x87000000; MemSet(adam,0,sizeof(CTask)); adam->addr=adam; adam->next_task=adam; adam->last_task=adam; Fs=adam;
  RVYieldInit(&Fs);
  RVJiffiesInit(10000);               // 1 jiffy = 1 ms (QEMU virt mtime is 10 MHz)
  KSpawn(&taskA); KSpawn(&taskB);
  Print("sleeping real CTasks (via CTask.wake_jiffy + kernel Yield): ");
  I64 t0=RVJiffies();
  // Adam also sleeps between checks: at moments when A, B and adam are all asleep the scheduler
  // must idle and still wake — if that path hung, this smoke would time out.
  while(ca<3 || cb<3) KSleep(5);
  I64 elapsed=RVJiffies()-t0;
  // A slept 40 ms then 3x20 ms of its own; end-to-end should be ~100 ms of real wall clock, proving
  // the sleeps actually consumed time (not returned instantly) and every task woke.
  I64 ok = (ca==3 && cb==3 && elapsed>=60 && elapsed<=600);
  Print("\nsleep test done A=%d B=%d elapsed=%dms %s\n", ca, cb, elapsed, ok?"OK":"BAD");
  return 0;
}
