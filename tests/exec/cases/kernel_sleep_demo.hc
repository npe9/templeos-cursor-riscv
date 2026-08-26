// RVSleep: a preemptive task waits N timer ticks WITHOUT busy-spinning — it records a wake tick and
// the scheduler's picker skips it until holy_ticks reaches it, so the CPU runs other tasks meanwhile.
// Three tasks sleep concurrently and all wake; the total elapsed is near the longest sleep, not the
// sum (which is what a blocking busy-wait would cost), proving they slept in parallel.
#include "/Kernel/Kernel_RV.PRJ"
I64 woke=0;
U0 t1(){ RVSleep(6); I64 g=RVCritEnter(); woke++; RVCritLeave(g); RVPreemptExit(); }
U0 t2(){ RVSleep(3); I64 g=RVCritEnter(); woke++; RVCritLeave(g); RVPreemptExit(); }
U0 t3(){ RVSleep(5); I64 g=RVCritEnter(); woke++; RVCritLeave(g); RVPreemptExit(); }
I64 main(){
  RVKernelInit();
  U8 *a=CAlloc(16384,NULL),*b=CAlloc(16384,NULL),*c=CAlloc(16384,NULL);
  RVPreemptInit(200000);
  RVPreemptSpawn(&t1,(a+16384-16)&(~15));
  RVPreemptSpawn(&t2,(b+16384-16)&(~15));
  RVPreemptSpawn(&t3,(c+16384-16)&(~15));
  while (woke<3){ I64 s=0; while (s<300000) s++; }
  I64 el=RVGetTicks();
  Print("slept concurrently: woke=%d elapsed_ticks=%d concurrent=%d\n", woke, el, el < 14);
  return 0;
}
