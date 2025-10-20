U0 UartPut(U8 ch) {
  U8 *uart;
  uart = 0x10000000;
  *uart = ch;
}

U0 PrintStr(U8 *str) {
  while (*str) {
    UartPut(*str);
    str = str + 1;
  }
}

I64 Main() {
  PrintStr("Hello from HolyC!\n");
  return 42;
}
