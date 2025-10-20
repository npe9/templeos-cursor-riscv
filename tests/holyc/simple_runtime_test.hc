// Simple runtime test - just the essentials

U0 UartPut(U8 ch) {
  U8 *uart;
  uart = 0x10000000;
  *uart = ch;
}

I64 Main() {
  UartPut(72);   // 'H'
  UartPut(105);  // 'i'
  UartPut(33);   // '!'
  UartPut(10);   // '\n'
  return 42;
}
