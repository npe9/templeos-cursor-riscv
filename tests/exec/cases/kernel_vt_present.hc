// VT presenter smoke: run the WinMgr/DolDoc stack headless and ship its text grid
// to the UART as ANSI. Proves RVDocVT.HC compiles and that the diff/flush loop has
// the property the design rests on — an idle present costs zero bytes.
#include "/Kernel/Kernel_RV.PRJ"
#include "/Kernel/RVDocVT.HC"
#define MEM_UART_VT 0x10000000

U0 VtOut(U8 *s)
{
  U8 *u = MEM_UART_VT;
  while (s && *s) {
    *u = *s;
    s++;
  }
}

I64 main()
{
  I64 first, idle, after;
  U8 buf[128];
  // Required before any kernel service: RVWinMgrLiteInit's MemSet/StrCpy need it.
  RVKernelInit();
  if (!RVWinMgrLiteInit()) {
    VtOut("VT: LiteInit FAILED\n");
    return 1;
  }
  VtOut("VT: WinMgr lite up (headless 80x25)\n");
  // ASCII fallback + colour: the smoke reads this over a pipe, not a real terminal.
  RVVtInit(0, 1);
  // Paint something recognisable straight into the grid the FB would consume.
  RVTextPrint(2, 1, WHITE, "TempleOS/RISC-V on a VT100");
  RVTextBorder(1, 40, 0, 3, LTGRAY, 0);
  first = RVVtPresent();
  // Nothing changed: the shadow must make this free. This is the whole design.
  idle = RVVtPresent();
  // One changed line must cost far less than the first full paint.
  RVTextPrint(2, 2, WHITE, "second line");
  after = RVVtPresent();
  RVVtStop();
  StrPrint(buf, "\nVT: first=%d idle=%d after=%d\n", first, idle, after);
  VtOut(buf);
  if (idle != 0) {
    VtOut("VT: FAIL idle present was not free\n");
    return 2;
  }
  if (first <= 0 || after <= 0 || after >= first) {
    VtOut("VT: FAIL incremental present not cheaper than full paint\n");
    return 3;
  }
  VtOut("VT: OK\n");
  return 0;
}
