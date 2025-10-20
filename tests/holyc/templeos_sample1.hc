// From TempleOS Demo/DateTime.HC (simplified)

I64 IsLeapYear(I64 year) {
  if (year & 3) return 0;
  if (!(year % 100)) {
    if (year % 400) return 0;
    return 1;
  }
  return 1;
}

I64 Main() {
  return IsLeapYear(2024);  // Should return 1 (true)
}
