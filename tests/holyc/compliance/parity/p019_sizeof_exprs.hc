// Parity: sizeof on types and locals
I64 main() {
  I64 a = 0;
  a = a + sizeof(I64);
  a = a + sizeof(I32);
  a = a + sizeof(U8 *);
  return a;
}
