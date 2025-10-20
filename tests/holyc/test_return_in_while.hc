I64 Main() {
  I64 count;
  count = 0;
  while (count < 5) {
    count = count + 1;
    if (count == 3) {
      return 99;
    }
  }
  return count;
}
