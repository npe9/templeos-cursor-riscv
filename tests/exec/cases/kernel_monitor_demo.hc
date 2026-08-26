// Capstone: an interactive monitor that composes the whole RISC-V OS foundation. A preemptively
// scheduled worker task counts in the background (its shared counter guarded by a critical section),
// while main reads single-letter commands delivered by the UART receive interrupt: 'c' prints the
// live counter, 'q' quits. Because the worker runs between commands, successive 'c' readings grow —
// visible proof of preemptive multitasking + interrupt-driven I/O + synchronization together.
#include "/Kernel/Kernel_RV.PRJ"
I64 counter=0, quit=0;
U0 worker(){ while (!quit){ I64 g=RVCritEnter(); counter++; RVCritLeave(g); I64 s=0; while (s<30000) s++; } RVPreemptExit(); }
I64 rdcmd(){ while (!RVUartHasInput()){} return RVUartGetBuffered(); }
I64 main(){
  RVKernelInit();
  U8 *st=CAlloc(16384,NULL);
  RVPreemptInit(200000);
  RVPreemptSpawn(&worker,(st+16384-16)&(~15));
  RVUartIrqInit();
  Print("monitor: 'c'=counter 'q'=quit\n");
  while (TRUE){
    Print("> ");
    I64 c=rdcmd();
    if (c=='\n' || c=='\r') continue;
    if (c=='q'){ Print("q\n"); quit=1; break; }
    if (c=='c'){ I64 g=RVCritEnter(); I64 v=counter; RVCritLeave(g); Print("c counter=%d\n", v); }
    else Print("?\n");
  }
  Print("bye final=%d\n", counter>0);
  return 0;
}
