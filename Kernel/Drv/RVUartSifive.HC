// SiFive UART0 — thin adapter to RVSifivePlat (selected via RVUartSelected.HH).
U0 RVUartInit()
{
  RVSifiveUartInit;
}

Bool RVUartPutS(U8 *st)
{
  return RVSifiveUartPutS(st);
}

// Soft RX ring, same shape as RVUart16550.HC's. It is not optional: RVDocVT's cursor-position
// probe (ESC[6n) pushes back any byte that is not the reply with RVUartSoftEnqueue, and on the
// HiFive Unmatched — where this driver is the console — the first keystroke after the REPL banner
// vanished into the C runtime's stub for it ("2+3;" evaluated as "+3;"). The ring is consulted
// before the hardware by every reader below.
#define RV_UART_SOFT_CAP 256
I64 RVUartSoft = 0;
U8 RVUartSoftRx[RV_UART_SOFT_CAP];
I64 RVUartSoftHead = 0;
I64 RVUartSoftTail = 0;
U0 RVUartSoftOn(I64 on = 1)
{
  RVUartSoft = on != 0;
  if (!on) {
    RVUartSoftHead = 0;
    RVUartSoftTail = 0;
  }
}
I64 RVUartSoftGet()
{
  return RVUartSoft;
}
U0 RVUartSoftEnqueue(I64 ch)
{
  I64 nh = (RVUartSoftHead + 1) & (RV_UART_SOFT_CAP - 1);
  if (nh == RVUartSoftTail)
    return;
  RVUartSoftRx[RVUartSoftHead] = ch;
  RVUartSoftHead = nh;
}
I64 RVUartSoftTryGet()
{
  I64 ch;
  if (RVUartSoftHead == RVUartSoftTail)
    return -1;
  ch = RVUartSoftRx[RVUartSoftTail];
  RVUartSoftTail = (RVUartSoftTail + 1) & (RV_UART_SOFT_CAP - 1);
  return ch;
}
Bool RVUartDataReady()
{
  if (RVUartSoftHead != RVUartSoftTail)
    return TRUE;
  return RVSifiveUartDataReady;
}
I64 RVUartGetC()
{
  I64 ch = RVUartSoftTryGet;
  if (ch >= 0)
    return ch;
  return RVSifiveUartGetC;
}
I64 RVUartTryGet()
{
  I64 ch = RVUartSoftTryGet;
  if (ch >= 0)
    return ch;
  if (!RVSifiveUartDataReady)
    return -1;
  return RVSifiveUartGetC;
}
U0 RVUartRxDrain()
{
  while (RVSifiveUartDataReady)
    RVUartSoftEnqueue(RVSifiveUartGetC);
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
