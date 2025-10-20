I64 Main() {
  U8 *plic;
  plic = 0x0C000004;
  *plic = 123;
  return 123;
}
