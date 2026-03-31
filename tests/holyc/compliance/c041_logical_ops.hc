I64 main() {
  I64 a = 1;
  I64 b = 0;
  if (a && !b)
    return 1;
  if (b || a)
    return 2;
  return 0;
}
