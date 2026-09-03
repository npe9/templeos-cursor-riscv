// Cooperative multitasking on RISC-V: RVSpawn creates tasks on fresh stacks and RVYield round-robins
// between them via the RVTaskSwitch context-switch primitive (save/restore callee-saved regs + sp +
// ra). Two tasks interleave their output through the kernel's Print over the UART, then exit. This
// is a small cooperative runtime, not the kernel's CTask scheduler (phase 2).
#include "/Kernel/Kernel_RV.PRJ"
U0 taskA()
{
  I64 i;
  for (i = 0; i < 3; i++) {
    Print("A%d ", i);
    RVYield();
  }
  Print("[A done] ");
  RVTaskExit();
}

U0 taskB()
{
  I64 i;
  for (i = 0; i < 3; i++) {
    Print("B%d ", i);
    RVYield();
  }
  Print("[B done] ");
  RVTaskExit();
}

I64 main()
{
  RVKernelInit();
  RVSpawn(&taskA);
  RVSpawn(&taskB);
  Print("start: ");
  while (!rv_sched_done[1] || !rv_sched_done[2])
    RVYield();
  Print("\nall tasks finished\n");
  return 0;
}
