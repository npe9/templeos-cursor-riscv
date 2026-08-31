// UART 16550 -- HolyC driver (@ MEM_UART on this board profile).
// Shared RX ring via host slots (I64 loads of published pointers):
//   0x87001020 = uart_rx*  0x87001028 = &uart_rh  0x87001030 = &uart_rt  0x87001038 = CAP
//   0x87001088 = C uart_hw_drain   0x870010B0 = C UartGet
// Host hooks are once-indirect: load the code address from the slot, then call through a funptr.
// Layout: keep LSR wait ending on line 27 (`;`) so smoke `27a` inserts uppercase before THR store.
#define MEM_UART 0x10000000
U0 UartRxDrain()
{
  U0 (*drain)();
  drain = *(I64 *)0x87001088;
  if (drain)
    drain();
}

U0 UartPut(I64 ch)
{
  UartRxDrain();
  // line padding for livedrv smoke (27a inserts before THR poke)
  //
  //
  //
  //
  //
  //
  while (!(*(U8 *)(MEM_UART + 5) & 0x20))
    ;
  *(U8 *)MEM_UART = ch;
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

I64 HcUartGet()
{
  I64 (*get)();
  get = *(I64 *)0x870010B0;
  if (!get)
    return 0;
  return get();
}

I64 HcTermKeyGet()
{
  /* Repair hatch only — interactive TermKeyGet is HolyC (term.hc). C Ed/Edit/readline
   * call C TermKeyGet directly; do not route Vi/EditHoly/FunPick through this slot. */
  I64 (*get)();
  get = *(I64 *)0x870010D0;
  if (!get)
    return 0;
  return get();
}
