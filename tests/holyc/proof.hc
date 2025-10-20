I64 Sub(I64 a, I64 b) {
  return a - b;
}

I64 Mult(I64 a, I64 b) {
  return Sub(a, b) + b + b;
}

I64 Main() {
  return Mult(6, 7);
}
