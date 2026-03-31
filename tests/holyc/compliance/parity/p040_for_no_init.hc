// Parity: for with empty init
I64 main() {
  I64 i = 0;
  I64 s = 0;
  for (; i < 4; i = i + 1)
    s = s + i;
  return s;
}
