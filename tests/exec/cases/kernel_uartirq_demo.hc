// Interrupt-driven UART input on RISC-V: RVUartIrqInit enables the UART RX interrupt and routes it
// through the PLIC; on each machine-external interrupt the trap handler drains the RX FIFO into a
// ring buffer. main() only ever reads that buffer (RVUartHasInput / RVUartGetBuffered) — it never
// touches the device — so the characters arrive entirely by interrupt, while a background task is
// scheduled preemptively in the gaps.
#include "/Kernel/Kernel_RV.PRJ"
I64 bgcount=0;
U0 bg(){ while (TRUE){ bgcount++; I64 s=0; while (s<50000) s++; } }
I64 main(){
  RVKernelInit();
  U8 *st=CAlloc(16384,NULL);
  RVPreemptInit(300000);
  RVPreemptSpawn(&bg,(st+16384-16)&(~15));
  RVUartIrqInit();
  Print("type a line: ");
  U8 line[64]; I64 n=0;
  while (n<63){
    while (!RVUartHasInput()){}
    I64 c=RVUartGetBuffered();
    if (c=='\r' || c=='\n') break;
    line[n]=c; n++;
    U8 e[2]; e[0]=c; e[1]=0; Print("%s", e);
  }
  line[n]=0;
  Print("\ngot: '%s' len=%d\n", line, n);
  return 0;
}
