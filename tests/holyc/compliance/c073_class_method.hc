class Counter {
  I64 n;

  I64 Bump() {
    n = n + 1;
    return n;
  }
};

I64 main() {
  Counter c;
  c.n = 10;
  return c.Bump();
}
