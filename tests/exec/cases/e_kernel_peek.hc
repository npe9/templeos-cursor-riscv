// Peek / PeekU32 / PeekU64 read the width they claim, at the address they are given.
//
// Trivial by design: the value of these verbs is that an operator can look at the SPI-NOR window or
// an MMIO block from the prompt, and the only thing that can quietly betray them is a width or an
// offset bug. So this writes a known pattern and reads it back three ways. Expect 0x1f.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  U8 buf[32];
  I64 r = 0, i = 0;
  while (i < 32) {
    buf[i] = i;
    i++;
  }
  if (Peek(buf) == 0)                        r |= 1;
  if (Peek(buf + 5) == 5)                    r |= 2;
  if (PeekU32(buf + 4) == 0x07060504)        r |= 4;    // little-endian, and 4 bytes not 8
  if (PeekU64(buf + 8) == 0x0F0E0D0C0B0A0908) r |= 8;
  if (Peek(buf + 31) == 31)                  r |= 16;
  return r;
}
