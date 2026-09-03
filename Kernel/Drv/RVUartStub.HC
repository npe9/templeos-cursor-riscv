// Stub UART (no hardware). Selected via RVUartSelected.HH from Kconfig.
U0 RVUartInit()
{
}

Bool RVUartPutS(U8 *st)
{
  while (*st)
    st++;
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

I64 RVUartTryGet()
{
  return -1;
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
  buf[0] = 0;
  return 0;
}
