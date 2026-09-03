// OpenTitan / lowRISC Ibex UART (QEMU -M opentitan @ CONFIG_UART_BASE).
// Regs: CTRL@0x10 (TX_ENABLE bit0), STATUS@0x14 (TXFULL bit0), WDATA@0x1c, RDATA@0x18.
// HolyC RV64 cannot run on Ibex yet — driver ready for ARCH_RISCV32 emit (RV32.md).
// Pair with RVTimerIbex when HAS_IBEX_TIMER.
U0 RVUartInit()
{
  U32 *ctrl = CONFIG_UART_BASE + 0x10;
  *ctrl = 1;
  // TX_ENABLE
}

Bool RVUartPutS(U8 *st)
{
  U32 *status = CONFIG_UART_BASE + 0x14;
  U32 *wdata = CONFIG_UART_BASE + 0x1C;
  while (*st) {
    while (*status & 1)
      ;
    // TXFULL
    *wdata = *st++;
  }
  return TRUE;
}

Bool RVUartDataReady()
{
  U32 *status = CONFIG_UART_BASE + 0x14;
  return (*status & 0x20) == 0;
  // RXEMPTY clear ⇒ data ready
}

I64 RVUartGetC()
{
  U32 *rdata = CONFIG_UART_BASE + 0x18;
  while (!RVUartDataReady)
    ;
  return *rdata & 0xFF;
}

I64 RVUartTryGet()
{
  U32 *rdata = CONFIG_UART_BASE + 0x18;
  if (!RVUartDataReady)
    return -1;
  return *rdata & 0xFF;
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
