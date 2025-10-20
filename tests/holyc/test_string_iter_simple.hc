I64 Main() {
  U8 *str;
  str = "Hi";
  while (*str) {
    return 99;  // Should hit this immediately
  }
  return 0;
}
