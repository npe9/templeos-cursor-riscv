// Cicl Test - PLIC Device Access
I64 Main() {
  U8 *plic;
  plic = 0x0C000004;
  *plic = 42;
  return 42;
}
