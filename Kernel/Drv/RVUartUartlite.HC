// Xilinx UARTLite (QEMU amd-microblaze-v-generic serial0 @ 0x40600000).
// Word regs: RX@0, TX@4, STATUS@8 (bit2 TX_EMPTY, bit0 RX_VALID).
U0 RVUartInit()
{
}

Bool RVUartPutS(U8 *st)
{
  U32 *tx = CONFIG_UART_BASE + 4;
  U32 *status = CONFIG_UART_BASE + 8;
  while (*st) {
    while (*status & 8)
      ;
    // TX_FULL
    *tx = *st++;
  }
  return TRUE;
}

Bool RVUartDataReady()
{
  U32 *status = CONFIG_UART_BASE + 8;
  return (*status & 1) != 0;
}

I64 RVUartGetC()
{
  U32 *rx = CONFIG_UART_BASE;
  while (!RVUartDataReady)
    ;
  return *rx & 0xFF;
}

I64 RVUartTryGet()
{
  U32 *rx = CONFIG_UART_BASE;
  if (!RVUartDataReady)
    return -1;
  return *rx & 0xFF;
}

U0 RVUartSoftOn(I64 on = 1)
{
  no_warn on;
}

I64 RVUartSoftGet()
{
  return 0;
}

U0 RVUartRxDrain()
{
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
