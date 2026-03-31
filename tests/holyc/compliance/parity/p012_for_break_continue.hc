// Parity: for with break and continue
I64 main() {
  I64 s = 0;
  I64 i;
  for (i = 0; i < 10; i = i + 1) {
    if (i == 2)
      continue;
    if (i == 7)
      break;
    s = s + i;
  }
  return s;
}
