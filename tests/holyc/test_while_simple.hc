I64 CountTo5() {
  I64 i;
  i = 0;
  while (i < 5) {
    i = i + 1;
  }
  return i;  // Should be 5
}

I64 Main() {
  return CountTo5();
}
