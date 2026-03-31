I64 main() {
  I64 x = 42;
  I64 *p = &x;
  *p = *p + 1;
  return x;
}
