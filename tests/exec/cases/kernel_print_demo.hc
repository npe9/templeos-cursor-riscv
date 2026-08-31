#include "/Kernel/Kernel_RV.PRJ"
#define MEM_UART 0x10000000
// Format with the real kernel StrPrintJoin, then write each byte straight to the QEMU virt UART.
U0 UartPutC(I64 ch)
{
  U8 *uart = MEM_UART;
  *uart = ch;
}

I64 main()
{
  U8 buf[128];
  I64 args[3];
  args[0] = 2026;
  args[1] = 8;
  args[2] = 25;
  StrPrintJoin(buf, "TempleOS/RISC-V kernel StrPrint says: %d-%02d-%02d\n", 3, args);
  I64 i = 0;
  while (buf[i]) {
    UartPutC(buf[i]);
    i++;
  }
  return i;
}
