// Dump / Peek / PeekU32 — look at any address from the prompt.
//
// The board's own reason for existing: QSPI0 maps the SPI-NOR flash at a direct-mapped window
// (0x20000000, 256 MiB on the FU740), so `Dump(0x20000000)` reads the flash with no driver at all.
// It is equally the tool for MMIO — `Dump(0x10060000)` is the GPIO block, `Dump(0x10010000)` the UART.
//
// A bad address faults rather than hanging, and the REPL's recover path turns that into one line and
// a prompt (RVTrapRecoverArm around ExePutS), so poking around is cheap. Reads only: there is no
// Poke here on purpose, because a stray write to MMIO is how a board stops answering.
#ifndef RV_PEEK_UI_HC
#define RV_PEEK_UI_HC
#help_index "Dbg"
I64 Peek(U8 *addr)
{
  //One byte.
  return *addr;
}

I64 PeekU32(U8 *addr)
{
  //One 32-bit word — the right width for almost every MMIO register on this SoC.
  return *(addr(U32 *));
}

I64 PeekU64(U8 *addr)
{
  return *(addr(I64 *));
}

U0 Dump(U8 *addr, I64 lines = 8)
{
  //`lines` rows of 16 bytes, hex and printable ASCII, the way every monitor since the 1970s does it.
  I64 i, j, ch;
  U8 *p = addr;
  if (lines < 1)
    lines = 1;
  if (lines > 64)
    lines = 64;
  i = 0;
  while (i < lines) {
    Print("%010X ", p);
    j = 0;
    while (j < 16) {
      Print("%02X ", p[j]);
      j++;
    }
    Print(" ");
    j = 0;
    while (j < 16) {
      ch = p[j];
      if (ch >= 0x20 && ch < 0x7F)
        Print("%c", ch);
      else
        Print(".");
      j++;
    }
    Print("\n");
    p += 16;
    i++;
  }
}
#endif
