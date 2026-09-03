// PREEMPTIVE multitasking on RISC-V: two tasks that never yield are forced to share the CPU by the
// machine-timer interrupt. RVPreemptInit installs a full-context (mepc-based) trap switch and arms
// the timer; on each interrupt the handler saves the entire interrupted task (x1..x31 + mepc),
// round-robins to the next task, and mrets into it. The tasks only Print and spin — the interleaving
// is produced entirely by preemption. This is the foundation of a preemptive scheduler.
#include "/Kernel/Kernel_RV.PRJ"
I64 ca = 0, cb = 0;
U0 ptaskA()
{
  while (ca < 5) {
    Print("A");
    ca++;
    I64 s = 0;
    while (s < 3000000)
      s++;
  }
  RVPreemptExit();
}

U0 ptaskB()
{
  while (cb < 5) {
    Print("B");
    cb++;
    I64 s = 0;
    while (s < 3000000)
      s++;
  }
  RVPreemptExit();
}

I64 main()
{
  RVKernelInit();
  U8 *sa = CAlloc(16384, NULL), *sb = CAlloc(16384, NULL);
  RVPreemptInit(400000);
  RVPreemptSpawn(&ptaskA, (sa + 16384 - 16) & (~15));
  RVPreemptSpawn(&ptaskB, (sb + 16384 - 16) & (~15));
  Print("start ");
  while (ca < 5 || cb < 5) {
    I64 s = 0;
    while (s < 1000000)
      s++;
  }
  Print(" done A=%d B=%d preempted=%d\n", ca, cb, RVGetTicks() > 0);
  return 0;
}
