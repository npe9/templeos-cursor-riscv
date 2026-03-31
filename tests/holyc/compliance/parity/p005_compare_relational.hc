// Parity: relational compares (compile + branch shape)
I64 main() {
  I64 a = 3;
  I64 b = 7;
  if (a < b && b >= a && a != b)
    return 1;
  return 0;
}
