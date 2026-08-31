I64 Add(I64 a, I64 b) {
  return a + b;
}

I64 Mul(I64 a, I64 b) {
  return a + a + a;  // Fake multiply as 3*a
}

I64 Main() {
  return Add(5, 3);
}
