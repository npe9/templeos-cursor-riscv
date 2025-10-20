I64 TestIf(I64 x) {
  if (x > 5) return 100;
  return 200;
}

I64 Main() {
  return TestIf(10);
}
