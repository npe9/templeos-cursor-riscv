// Parity: += -= *= /= &= |= ^=
I64 main() {
  I64 x = 16;
  x += 4;
  x -= 2;
  x *= 2;
  x /= 5;
  x &= 0xFF;
  x |= 0x100;
  x ^= 0x10;
  return x;
}
