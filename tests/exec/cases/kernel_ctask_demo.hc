#include "/Kernel/Kernel_RV.PRJ"
// Authentic task switching on the REAL CTask: Fs is the current task, tasks are linked by next_task,
// and Yield saves/restores the register frame on the task's own stack (CTask.rsp), exactly the model
// TempleOS uses (Sched.HC _YIELD) — only the low-level save/restore is ported to RISC-V (RVCtxSw).
I64 done_count=0;
U0 KYield(){
  CTask *cur=Fs, *nxt=cur->next_task;
  while (nxt!=cur && Bt(&nxt->task_flags,TASKf_KILL_TASK)) nxt=nxt->next_task;
  if (nxt==cur) return;
  Fs=nxt;
  RVCtxSw(&cur->rsp, &nxt->rsp);
}
CTask *KSpawn(U0 (*entry)()){
  CTask *t=CAlloc(sizeof(CTask),NULL); t->addr=t; t->task_flags=0;
  U8 *stk=CAlloc(16384,NULL);
  I64 top=(stk+16384)&(~15);
  I64 *frame=top-104; I64 i; for (i=0;i<12;i++) frame[i]=0; frame[12]=entry;   // ra=entry
  t->rsp=frame;
  CTask *c=Fs;                                      // link into the circular task list after Fs
  t->next_task=c->next_task; t->last_task=c; c->next_task->last_task=t; c->next_task=t;
  return t;
}
U0 taskA(){ I64 k; for (k=0;k<3;k++){ Print("A%d ",k); KYield(); } Print("[A done] "); done_count++; Bts(&Fs->task_flags,TASKf_KILL_TASK); KYield(); }
U0 taskB(){ I64 k; for (k=0;k<3;k++){ Print("B%d ",k); KYield(); } Print("[B done] "); done_count++; Bts(&Fs->task_flags,TASKf_KILL_TASK); KYield(); }
I64 main(){
  RVKernelInit();
  CTask *adam=CAlloc(sizeof(CTask),NULL); adam->addr=adam; adam->task_flags=0;
  adam->next_task=adam; adam->last_task=adam; Fs=adam;   // Fs = the current (real) task
  KSpawn(&taskA); KSpawn(&taskB);
  Print("start: ");
  while (done_count<2) KYield();
  Print("\nall tasks done (via real CTask Yield)\n");
  return 0;
}
