// Drive the kernel's OWN native output path to the QEMU virt UART. Register a UART "keyboard
// device" put_s sink via the kernel's KeyDevAdd, then use the kernel's PutS AND Print: both walk
// keydev.put_key_head and dispatch to our handler (Print also runs the full StrPrintJoin formatter
// first). Proves the kernel's device-dispatch layer + varargs Print execute on RISC-V.
#include "/Kernel/Kernel_RV.PRJ"
#define MEM_UART 0x10000000
Bool UartPutS(U8 *st)
{
  U8 *uart = MEM_UART;
  while (*st)
    *uart = *st++;
  return TRUE;
}

I64 main()
{
  MemSet(&keydev.put_key_head, 0, sizeof(CKeyDevEntry));
  QueInit(&keydev.put_key_head);
  KeyDevAdd(NULL, &UartPutS, MEM_UART, FALSE);
  // register our UART sink in the StdOut chain
  Fs->display_flags = 0;
  kbd.scan_code = 0;
  // not SILENT, not SCROLL-locked
  PutS("TempleOS/RISC-V kernel PutS over UART\n");
  Print("kernel Print: %d + %d = %d\n", 2, 40, 42);
  return 0;
}
