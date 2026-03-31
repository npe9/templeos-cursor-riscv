// Parity: F64 locals and cross-use with I64 (when supported)
I64 main() {
  F64 x = 2.5;
  F64 y = 3.5;
  I64 xi = 4;
  return xi + (I64)(x + y);
}
