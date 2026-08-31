// Spike HTIF console (experimental). Selected via RVUartSelected.HH from Kconfig.
U0 RVUartInit()
{
}

Bool RVUartPutS(U8 *st)
{
  U64 *htif = CONFIG_UART_BASE;
  while (*st) {
    *htif = (1 << 56) | (1 << 48) | (*st++);
    while (*htif)
      ;
  }
  return TRUE;
}

Bool RVUartDataReady()
{
  return FALSE;
}

I64 RVUartGetC()
{
  while (TRUE)
    ;
  return 0;
}

I64 RVUartGetLine(U8 *buf, I64 max)
{
  buf[0] = 0;
  return 0;
}
