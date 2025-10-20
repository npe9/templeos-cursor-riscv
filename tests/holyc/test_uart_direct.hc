I64 Main() {
  U8 *uart;
  uart = 0x10000000;
  *uart = 72;  // 'H'
  return 42;
}
