// Synchronization for the preemptive scheduler: a read-modify-write on a shared counter is split by
// timer preemption and loses updates, unless wrapped in a critical section (RVCritEnter/RVCritLeave
// disable/restore the machine interrupt-enable). Two preemptive tasks each bump the counter 50 times
// with a delay between read and write to widen the race window. Without the lock the total is short;
// with it, every increment survives.
#include "/Kernel/Kernel_RV.PRJ"
I64 counter, use_lock, da, db;
U0 bump(){
  I64 i;
  for (i=0;i<50;i++){
    I64 g=0; if (use_lock) g=RVCritEnter();
    I64 t=counter;
    I64 s=0; while (s<200000) s++;    // widen the read-modify-write window
    counter=t+1;
    if (use_lock) RVCritLeave(g);
  }
}
U0 ta(){ bump(); da=1; RVPreemptExit(); }
U0 tb(){ bump(); db=1; RVPreemptExit(); }
I64 run(){
  counter=0; da=0; db=0;
  U8 *sa=CAlloc(16384,NULL), *sb=CAlloc(16384,NULL);
  RVPreemptInit(150000);
  RVPreemptSpawn(&ta,(sa+16384-16)&(~15));
  RVPreemptSpawn(&tb,(sb+16384-16)&(~15));
  while (!da || !db){ I64 s=0; while (s<500000) s++; }
  return counter;
}
I64 main(){
  RVKernelInit();
  use_lock=0; I64 racy=run();
  use_lock=1; I64 safe=run();
  Print("no lock: counter=%d race_lost=%d\n", racy, racy<100);
  Print("with lock: counter=%d\n", safe);
  return 0;
}
