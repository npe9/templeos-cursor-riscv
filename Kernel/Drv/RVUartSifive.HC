// SiFive UART0 — thin adapter to RVSifivePlat (selected via RVUartSelected.HH).
U0 RVUartInit()
{
  RVSifiveUartInit;
}

Bool RVUartPutS(U8 *st)
{
  return RVSifiveUartPutS(st);
}

Bool RVUartDataReady()
{
  return RVSifiveUartDataReady;
}

I64 RVUartGetC()
{
  return RVSifiveUartGetC;
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
