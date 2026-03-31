// Parity: TempleOS-style mixed-width promotion in expressions
I64 main() {
  I8  a = 40;
  I16 b = 1000;
  I32 c = 50000;
  U8  u = 200;
  return (I64)a + (I64)b + (I64)c + (I64)u;
}
