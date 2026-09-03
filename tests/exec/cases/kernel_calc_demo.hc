// Interactive kernel I/O over the UART: RVKernelInit() brings up the console, RVUartGetLine() reads
// a line (echoing), the kernel's Str2I64() parses it, and the kernel's Print() formats the result —
// all over the same UART. Proves the phase-2 console works both directions (input + output).
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  RVKernelInit();
  Print("RISC-V calc: type a number, or 'q' to quit\n");
  U8 line[64];
  while (TRUE) {
    Print("> ");
    I64 n = RVUartGetLine(line, 64);
    if (n == 0)
      continue;
    if (line[0] == 'q') {
      Print("bye\n");
      break;
    }
    I64 v = Str2I64(line, 10, NULL);
    Print("  dec=%d  x2=%d  hex=0x%X\n", v, v * 2, v);
  }
  return 0;
}
