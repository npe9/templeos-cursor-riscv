// Parity: Bool type in expressions
Bool T() {
  return 1;
}

Bool F() {
  return 0;
}

I64 main() {
  if (T() && !F())
    return 42;
  return 0;
}
