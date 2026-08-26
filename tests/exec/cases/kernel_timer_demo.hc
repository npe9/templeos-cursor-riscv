// RISC-V machine-timer interrupts on QEMU virt: RVTrapInit installs a trap vector (save caller-saved
// regs -> C dispatcher -> restore -> mret), RVTimerArm programs the CLINT mtimecmp and enables MTIE,
// and the dispatcher counts each timer interrupt and re-arms. The main loop only spins — the ticks
// accumulate asynchronously, proving interrupt-driven execution (the foundation for preemption).
#include "/Kernel/Kernel_RV.PRJ"
I64 main(){
  RVKernelInit();
  RVTrapInit();
  RVTimerArm(50000);
  I64 spin=0;
  while (RVGetTicks()<5 && spin<50000000) spin++;   // let several interrupts fire
  Print("timer interrupts fired: %d\n", RVGetTicks());
  if (RVGetTicks()>=5) Print("interrupt-driven execution OK\n");
  return 0;
}
