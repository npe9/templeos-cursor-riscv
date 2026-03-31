I64 main() {
  I64 x = 0xF0F0F0F0;
  I64 y = 0x0F0F0F0F;
  I64 z = (x & y) | (~x ^ y);
  return z & 255;
}
