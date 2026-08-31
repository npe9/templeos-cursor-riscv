// uart.hc -- 16550 UART in HolyC (@ MEM_UART). No host slots, no C drain/get.
#define MEM_UART  0x10000000
#define UART_BASE MEM_UART
#define UART_THR  (UART_BASE+0)
#define UART_RBR  (UART_BASE+0)
#define UART_LSR  (UART_BASE+5)
U0 UartPut(I64 ch)
{
  while (!(*(U8 *)UART_LSR & 0x20))
    ;
  *(U8 *)UART_THR = ch;
}

U0 UartStr(U8 *s)
{
  if (!s)
    return;
  while (*s)
    UartPut (*s++);
}

U0 PutCh(I64 ch)
{
  UartPut(ch);
}

U0 PutS(U8 *s)
{
  UartStr(s);
}

I64 UartRxReady()
{
  return *(U8 *)UART_LSR & 1;
}

I64 UartGet()
{
  while (!UartRxReady())
    ;
  return *(U8 *)UART_RBR;
}
