// Parity: while with local accumulator
I64 main() {
  I64 i = 0;
  I64 s = 0;
  while (i < 5) {
    s = s + i;
    i = i + 1;
  }
  return s;
}
