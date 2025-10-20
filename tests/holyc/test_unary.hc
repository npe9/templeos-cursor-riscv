I64 TestNot() {
  I64 x;
  x = 5;
  return !x;
}

I64 TestCom() {
  return ~7;
}

I64 TestNeg() {
  return -42;
}

I64 Main() {
  return TestNeg();
}
