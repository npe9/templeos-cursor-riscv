I64 Multiply(I64 x, I64 y) {
  I64 result;
  result = x - y;
  result = result + y;
  result = result + y;
  return result;
}

I64 Negate(I64 n) {
  I64 zero;
  zero = 0;
  return zero - n;
}

I64 Main() {
  return Multiply(6, 7);
}
