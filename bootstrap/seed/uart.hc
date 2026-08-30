// UART 16550 driver -- a live-editable kernel primitive (QEMU virt @ 0x10000000).
// Edit a body, Run("uart.hc") again, and the change is live -- no reboot.
U0 UartPut(I64 ch) {
  while (!(*(U8 *)0x10000005 & 0x20)) ;   // LSR bit 5: THR empty
  *(U8 *)0x10000000 = ch;                  // write the byte
}
U0 UartStr(U8 *s) { while (*s) UartPut(*s++); }
