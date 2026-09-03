// Spike HTIF console. Selected via RVUartSelected.HH from Kconfig.
// CONFIG_UART_BASE = absolute ELF `tohost` (harness link_exec.ld /.tohost @ 0x807FF000).
// `fromhost` follows at +0x40 (.align 6 in crt0.S). QEMU spike parses both symbols.
#ifndef CONFIG_HTIF_FROMHOST_OFF
#define CONFIG_HTIF_FROMHOST_OFF 0x40
#endif
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
  U64 *from = CONFIG_UART_BASE + CONFIG_HTIF_FROMHOST_OFF;
  return *from != 0;
}

I64 RVUartGetC()
{
  U64 *tohost = CONFIG_UART_BASE, *from = CONFIG_UART_BASE + CONFIG_HTIF_FROMHOST_OFF, v;
  while (TRUE) {
    // Console device=1, cmd=0 (getc) — response lands in fromhost.
    *tohost = 1 << 56;
    while (*tohost)
      ;
    while (!*from)
      ;
    v = *from;
    *from = 0;
    return v & 0xFF;
  }
  return 0;
}

I64 RVUartTryGet()
{
  U64 *tohost = CONFIG_UART_BASE, *from = CONFIG_UART_BASE + CONFIG_HTIF_FROMHOST_OFF, v;
  if (!RVUartDataReady)
    return -1;
  *tohost = 1 << 56;
  while (*tohost)
    ;
  while (!*from)
    ;
  v = *from;
  *from = 0;
  return v & 0xFF;
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
  I64 n = 0, c;
  if (max <= 0) {
    return 0;
  }
  while (n + 1 < max) {
    c = RVUartGetC();
    if (c == '\r' || c == '\n')
      break;
    buf[n++] = c;
  }
  buf[n] = 0;
  return n;
}
