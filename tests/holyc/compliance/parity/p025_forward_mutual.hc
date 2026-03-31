// Parity: mutual forward declarations
I64 Second(I64 x);

I64 First(I64 x) {
  if (x <= 0)
    return 0;
  return x + Second(x - 1);
}

I64 Second(I64 x) {
  if (x <= 0)
    return 0;
  return x * 2 + First(x - 2);
}

I64 main() {
  return First(3);
}
