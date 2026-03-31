// Pattern from TempleOS Demo/DateTime.HC (leap year test only)
I64 IsLeapYear(I64 year) {
  if (year & 3)
    return 0;
  if (!(year % 100)) {
    if (year % 400)
      return 0;
    return 1;
  }
  return 1;
}

I64 main() {
  return IsLeapYear(2024);
}
