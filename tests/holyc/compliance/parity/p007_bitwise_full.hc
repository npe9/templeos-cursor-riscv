// Parity: ~ ^ | & in one expression
I64 main() {
  I64 a = 0x0F0F;
  I64 b = 0x00FF;
  return (~a & b) ^ (a | b);
}
