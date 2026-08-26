// Drive the kernel's OWN native output path — PutS (Kernel/KeyDev.HC) — to the QEMU virt UART.
// Register a UART "keyboard device" put_s handler via the kernel's KeyDevAdd, then call PutS:
// PutS walks keydev.put_key_head and dispatches to our handler. This proves the kernel's device
// dispatch layer executes on RISC-V, not just leaf formatters.
#include "/Kernel/Kernel_RV.PRJ"
Bool UartPutS(U8 *st){ U8 *uart=0x10000000; while (*st) *uart=*st++; return TRUE; }
I64 main(){
  MemSet(&keydev.put_key_head,0,sizeof(CKeyDevEntry));
  QueInit(&keydev.put_key_head);
  KeyDevAdd(NULL,&UartPutS,0x10000000,FALSE);   // register our UART sink in the StdOut chain
  Fs->display_flags=0; kbd.scan_code=0;         // not SILENT, not SCROLL-locked
  PutS("TempleOS/RISC-V kernel PutS over UART\n");
  return 0;
}
