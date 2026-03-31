// Parity: multiple calls in argument list (evaluation order stress)
I64 Cnt;

I64 A() {
  Cnt = Cnt + 1;
  return 2;
}

I64 B() {
  Cnt = Cnt * 10;
  return 3;
}

I64 Add2(I64 x, I64 y) {
  return x + y;
}

I64 main() {
  Cnt = 0;
  return Add2(A(), B()) + Cnt;
}
