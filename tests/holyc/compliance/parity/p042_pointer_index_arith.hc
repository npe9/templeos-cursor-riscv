// Parity: pointer base + [] indexing
I64 main() {
  I64 a[4];
  a[0] = 1;
  a[1] = 10;
  a[2] = 100;
  a[3] = 1000;
  I64 *p = a;
  return p[0] + p[3];
}
