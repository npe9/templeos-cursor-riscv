I64 Add(I64 a, I64 b) {
  return a + b;
}

I64 main() {
  I64 (*fn)(I64, I64) = Add;
  return fn(2, 3);
}
