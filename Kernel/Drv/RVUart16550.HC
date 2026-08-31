// NS16550A UART (QEMU virt). Selected via Kernel/Drv/RVUartSelected.HH from Kconfig.
U0 RVUartInit()
{
}

Bool RVUartPutS(U8 *st)
{
  U8 *uart = CONFIG_UART_BASE;
  while (*st)
    *uart = *st++;
  return TRUE;
}

Bool RVUartDataReady()
{
  U8 *lsr = CONFIG_UART_BASE + 5;
  return (*lsr & 1) != 0;
}

I64 RVUartGetC()
{
  U8 *rbr = CONFIG_UART_BASE;
  while (!RVUartDataReady)
    ;
  return *rbr;
}

I64 RVUartGetLine(U8 *buf, I64 max)
{
  I64 n = 0, ch;
  while (n < max - 1) {
    ch = RVUartGetC;
    if (ch == '\r' || ch == '\n') {
      RVUartPutS("\n");
      break;
    }
    if (ch == 8 || ch == 127) {
      if (n > 0) {
        n--;
        RVUartPutS("\b \b");
      }
      continue;
    }
    buf[n++] = ch;
    U8 e[2];
    e[0] = ch;
    e[1] = 0;
    RVUartPutS(e);
  }
  buf[n] = 0;
  return n;
}
