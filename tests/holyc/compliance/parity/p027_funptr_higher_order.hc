// Parity: function pointer passed and invoked
I64 Twice(I64 x, I64 (*f)(I64)) {
  return f(f(x));
}

I64 Inc(I64 x) {
  return x + 1;
}

I64 main() {
  return Twice(5, Inc);
}
